import
  std/[jsffi, algorithm, tables],
  screeps_lib,
  ./[worldInfrastructure, worldMovement, worldLinks, worldWorkTasks, worldDiagnostics]

type
  WorkTargets* = object
    observation*: WorkObservation
    refill*: Structure
    repair*: Structure
    build*: ConstructionSite
    controller*: StructureController
  PreparedJobs* = object
    observation*: WorkJobObservation
    targets*: seq[WorkTargets]
    needs*: seq[float32]

var
  reservationTick = -1
  reservedEnergy: Table[string, float32]
  acceptedRefillEnergy: Table[string, int]
  acceptedSupplyEnergy: Table[string, int]

const
  RepairWorkPower = 100.0'f32
  BuildWorkPower = 5.0'f32
  ConstructionPriorityScale = 9.0'f32
  WorkerRole* = "worker".cstring
  WorkerBodyCost* = 200
  WorkBodyCost = 100
  MoveBodyCost = 50
  ControllerUrgencyTicks = 3000
  ControllerWorkRange = 3
  ReplacementTicks = 100
  MinerReplacementTicks = 250
  MinimumMinerCost = 250
  MaxMinerWork = 5
  MinimumDeliveryWorkers = 3
  MinimumRecoveryCarriers = 6
  DesiredHaulers = 3
  MaximumSuppliedUpgraders = 2
  MinimumGeneralWorkers = 2
  AdditionalUpgraderReserveBodies = 2
  MaxWorkerCost = 600
  MaxHaulerCost = MaxWorkerCost + MoveBodyCost
  DevelopedHaulerCost = 1150
  DevelopedHaulerLevel = 4
  RoadHaulerLevel = 5
  MaxUpgraderCost = 1300
  DevelopedUpgraderCost = 900
  MinimumSuppliedUpgraderCost = 500
  UpgraderCarryParts = 2
  DevelopedUpgraderCarryParts = 4
  EarlyUpgraderMoveParts = 1
  UpgraderMoveParts = 2
  TowerCombatReserve = 500
  TowerRefillBatch = 200
  UpgraderJob* = "upgrader".cstring
  GeneralJob* = "general".cstring
  MinerJob* = "miner".cstring
  HaulerJob* = "hauler".cstring
  WorkerSupplyMinimum = 50
  SupplyWaitTicks = 50
  RoadRepairPercent = 80
  RepairRange = 3
  RepairTargetHits* = 20000
  StorageReserveEnergy* = 2000
  SupplementalHaulers = 3
  HaulingPlanTicks = 20
  HaulingCpuReserve = 5
  HaulingBucketReserve = 2000
  SourceRegenerationTicks = 300
  CreepLifetimeTicks = 1500
  CarryCapacity = 50
  HarvestPower = 2
  MoveFatiguePower = 2
  HaulingActions = 2

proc workerBody*(energy: int): seq[cstring] =
  ## Preserve worker capacity and spend spare budget on loaded travel speed.
  if energy < WorkerBodyCost:
    return
  let
    budget = min(energy, MaxWorkerCost)
    segments = budget div WorkerBodyCost
    extraMoves = min(segments, (budget - segments * WorkerBodyCost) div MoveBodyCost)
  for segment in 0 ..< segments:
    result.add(["work".cstring, "carry".cstring, "move".cstring])
  for extra in 0 ..< extraMoves:
    result.add("move".cstring)

proc bodyCost(body: seq[cstring]): int =
  ## Calculate energy spent on a worker's WORK, CARRY and MOVE parts.
  for part in body:
    result += (if part == "work".cstring: WorkBodyCost else: MoveBodyCost)

proc workerCost*(energy: int): int =
  ## Calculate the actual cost of the selected affordable body.
  bodyCost(workerBody(energy))

proc suppliedUpgraderBody(energy: int): seq[cstring] =
  ## Spend additional budget on work while retaining carrying and travel capacity.
  if energy < MinimumSuppliedUpgraderCost:
    return workerBody(energy)
  let
    budget = min(energy, MaxUpgraderCost)
    carryParts = if budget >= DevelopedUpgraderCost: DevelopedUpgraderCarryParts else: UpgraderCarryParts
    moveParts = if budget >= DevelopedUpgraderCost: UpgraderMoveParts else: EarlyUpgraderMoveParts
    supportCost = (carryParts + moveParts) * MoveBodyCost
    workParts = (budget - supportCost) div WorkBodyCost
  for part in 0 ..< workParts:
    result.add("work".cstring)
  for part in 0 ..< carryParts:
    result.add("carry".cstring)
  for part in 0 ..< moveParts:
    result.add("move".cstring)
  if budget - bodyCost(result) >= MoveBodyCost:
    result.add("move".cstring)

proc haulingWorkerBody*(energy: int, roads = false): seq[cstring] =
  ## Retain emergency harvesting capability while increasing carrying capacity.
  if energy < WorkerBodyCost:
    return
  if roads:
    let budget = min(energy, DevelopedHaulerCost)
    var carryParts, moveParts: int
    for carrying in 1 .. budget div MoveBodyCost:
      let moving = (carrying + 2) div 2
      if WorkBodyCost + (carrying + moving) * MoveBodyCost > budget:
        break
      carryParts = carrying
      moveParts = moving
    result.add("work".cstring)
    for part in 0 ..< carryParts: result.add("carry".cstring)
    for part in 0 ..< moveParts: result.add("move".cstring)
    if budget - bodyCost(result) >= MoveBodyCost: result.add("move".cstring)
    return
  let
    budget = min(energy, DevelopedHaulerCost)
    movementReserve = if budget >= MaxHaulerCost: MoveBodyCost else: 0
    pairs = (budget - WorkBodyCost - movementReserve) div (MoveBodyCost * 2)
  result.add("work".cstring)
  for pair in 0 ..< pairs:
    result.add(["carry".cstring, "move".cstring])
  if budget - bodyCost(result) >= MoveBodyCost:
    result.add("move".cstring)

proc minerBody*(energy: int): seq[cstring] =
  ## Build a stationary miner that drops harvested energy for other workers.
  if energy < MinimumMinerCost:
    return
  for part in 0 ..< min(MaxMinerWork, (energy - MoveBodyCost) div WorkBodyCost):
    result.add("work".cstring)
  result.add("move".cstring)

proc productive(creep: Creep): bool =
  ## Count workers until their job's replacement lead time begins.
  let lead = if creep.memory.job == MinerJob: MinerReplacementTicks else: ReplacementTicks
  creep.spawning or not (creep.ticksToLive < lead)

proc supplementalHauler(creep: Creep): bool =
  ## Identify optional transport without replacing the ordinary workforce.
  creep.memory.job == HaulerJob and creep.memory.toJs["supplementalHauler"].to(bool)

proc coreWorkerCount(roomName: cstring, job: cstring = ""): int =
  ## Count ordinary productive workers independently of optional transport.
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == roomName and
        creep.productive() and not creep.supplementalHauler() and
        (job.len == 0 or creep.memory.job == job):
      inc result

proc coreDeliveryCount(roomName: cstring): int =
  ## Preserve recovery body budgets when optional haulers remain alive.
  coreWorkerCount(roomName) - coreWorkerCount(roomName, MinerJob)

proc workerCount*(roomName: cstring): int =
  ## Count living and spawning workers assigned to a room.
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == roomName:
      if creep.productive():
        inc result

proc deliveryWorkerCount*(roomName: cstring): int =
  ## Count productive workers capable of carrying energy and recovering spawning.
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == roomName and
        creep.memory.job != MinerJob and creep.productive():
      inc result

proc residentWorkerCount*(roomName: cstring): int =
  ## Count completed productive carriers physically working in their assigned room.
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == roomName and
        creep.room.name == roomName and not creep.spawning and creep.productive() and
        creep.getActiveBodyparts("work") > 0 and creep.getActiveBodyparts("carry") > 0:
      inc result

proc moveWorker(creep: Creep, target: RoomObject, arrival = 1): ReturnCode =
  ## Keep local work routes within the room instead of taking adjacent-room detours.
  creep.moveLocal(target.pos, arrival)

proc upgradeControllerWork(creep: Creep, controller: StructureController): ReturnCode =
  ## Preserve successful dedicated upgrading through later local traffic exchanges.
  result = creep.upgradeController(controller)
  if result == OK and creep.memory.job == UpgraderJob:
    creep.protectControllerWork(controller)

proc jobCount(roomName, job: cstring): int =
  ## Count productive and spawning workers assigned to one room job.
  for creep in game.creeps.items:
    if creep.memory.homeRoom == roomName and creep.memory.role == WorkerRole and
        creep.memory.job == job and
        creep.productive():
      inc result

proc hasJob(roomName, job: cstring): bool =
  ## Check whether a room has a productive worker performing a given job.
  jobCount(roomName, job) > 0

proc uncoveredSource(spawn: StructureSpawn): Source =
  ## Find a statically reachable source without a productive assigned miner.
  let recovering = deliveryWorkerCount(spawn.room.name) < MinimumRecoveryCarriers
  for source in spawn.room.find(FIND_SOURCES):
    var covered = false
    for creep in game.creeps.items:
      if creep.memory.role == WorkerRole and creep.memory.homeRoom == spawn.room.name and
          creep.memory.job == MinerJob and creep.memory.sourceId == source.id:
        if creep.productive() or (recovering and not creep.spawning and creep.ticksToLive > 0 and
            creep.room.name == spawn.room.name and creep.pos.distance(source.pos) <= 1 and
            creep.getActiveBodyparts("work") > 0):
          covered = true
    if covered:
      continue
    if spawn.pos.distance(source.pos) <= 1:
      return source
    let route = spawn.room.findPath(spawn.pos, source.pos, localPathOptions(1, true))
    if route.len > 0 and RoomPosition(x: route[^1].x, y: route[^1].y).distance(source.pos) <= 1:
      return source

proc haulerBudget(spawn: StructureSpawn): int =
  ## Fund larger transport only behind an established workforce and stored reserve.
  let room = spawn.room
  if room.controller.isNil or not room.controller.my or
      room.controller.level < DevelopedHaulerLevel or
      room.energyCapacityAvailable < DevelopedHaulerCost or
      deliveryWorkerCount(room.name) < MinimumRecoveryCarriers or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return MaxHaulerCost
  for structure in room.findStructures(FIND_STRUCTURES):
    if structure.my and structure.structureType == StorageStructureType and
        structure.store.getUsedCapacity(RESOURCE_ENERGY) >= StorageReserveEnergy:
      return DevelopedHaulerCost
  MaxHaulerCost

proc roadHaulerReady(spawn: StructureSpawn): bool =
  ## Qualify completed core road routes only in a peaceful established home.
  let room = spawn.room
  if room.controller.isNil or not room.controller.my or
      room.controller.level < RoadHaulerLevel or
      deliveryWorkerCount(room.name) < MinimumRecoveryCarriers or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return false
  var roads: seq[tuple[x, y: int]]
  var storage = false
  for structure in room.findStructures(FIND_STRUCTURES):
    if structure.structureType == RoadStructureType and structure.hits > 0:
      roads.add((structure.pos.x, structure.pos.y))
    elif structure.my and structure.structureType == StorageStructureType:
      storage = true
  if not storage: return false
  proc connected(target: RoomPosition, arrival: int): bool =
    ## Require every static core path step to use an actual living road.
    if spawn.pos.distance(target) <= arrival: return true
    let route = room.findPath(spawn.pos, target, localPathOptions(arrival, true))
    if route.len == 0 or RoomPosition(x: route[^1].x, y: route[^1].y).distance(target) > arrival:
      return false
    for step in route:
      if (step.x, step.y) notin roads: return false
    true
  let sources = room.find(FIND_SOURCES)
  if sources.len == 0 or not connected(room.controller.pos, ControllerWorkRange): return false
  for source in sources:
    if not connected(source.pos, 1): return false
  true

proc sourceCargo(sources: seq[Source], drops: seq[Resource], structures: seq[Structure]): int =
  ## Count each harvested load once when it is beside any selected source.
  for drop in drops:
    if drop.resourceType != RESOURCE_ENERGY: continue
    for source in sources:
      if drop.pos.distance(source.pos) <= 1:
        result += drop.amount
        break
  for structure in structures:
    if structure.structureType != ContainerStructureType: continue
    for source in sources:
      if structure.pos.distance(source.pos) <= 1:
        result += structure.store.getUsedCapacity(RESOURCE_ENERGY)
        break

proc sourceCargo(source: Source, drops: seq[Resource], structures: seq[Structure]): int =
  ## Count harvested energy beside one source for hauling assignment.
  @[source].sourceCargo(drops, structures)

proc extraSuppliedUpgrader(spawn: StructureSpawn): bool =
  ## Add affordable controller capacity only behind working mining, hauling and replacement reserves.
  let room = spawn.room
  if room.controller.isNil or not room.controller.my or
      room.energyCapacityAvailable < MinimumSuppliedUpgraderCost or
      residentWorkerCount(room.name) < MinimumRecoveryCarriers or
      jobCount(room.name, UpgraderJob) >= MaximumSuppliedUpgraders or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return false
  let body = suppliedUpgraderBody(min(room.energyCapacityAvailable, MaxUpgraderCost))
  let cost = bodyCost(body)
  if room.energyAvailable < cost:
    return false
  var haulers, generals, dedicatedWork, additionalWork: int
  for part in body:
    if part == "work".cstring: inc additionalWork
  for other in game.creeps.items:
    if other.memory.role != WorkerRole or other.memory.homeRoom != room.name or
        other.room.name != room.name or other.spawning or not other.productive():
      continue
    let work = other.getActiveBodyparts("work")
    if work == 0 or other.getActiveBodyparts("carry") == 0 or
        other.getActiveBodyparts("move") == 0:
      continue
    if other.memory.job == HaulerJob: inc haulers
    elif other.memory.job == GeneralJob: inc generals
    elif other.memory.job == UpgraderJob: dedicatedWork += work
  if haulers < DesiredHaulers or generals < MinimumGeneralWorkers or dedicatedWork == 0:
    return false
  let sources = room.find(FIND_SOURCES)
  if sources.len == 0 or dedicatedWork + additionalWork > sources.len * MaxMinerWork:
    return false
  for source in sources:
    var working = false
    for other in game.creeps.items:
      if other.memory.role == WorkerRole and other.memory.job == MinerJob and
          other.memory.homeRoom == room.name and other.room.name == room.name and
          other.memory.sourceId == source.id and not other.spawning and other.productive() and
          other.getActiveBodyparts("work") >= MaxMinerWork and other.pos.distance(source.pos) <= 1:
        working = true
    if not working: return false
  let drops = room.findResources()
  let structures = room.findStructures(FIND_STRUCTURES)
  let surplus = sources.sourceCargo(drops, structures)
  surplus >= cost * AdditionalUpgraderReserveBodies

proc haulingRate(route: seq[PathStep], terrain: RoomTerrain,
    roads: seq[tuple[x, y: int]], work, carry, moves: int): float =
  ## Estimate payload per source-to-spawn round trip from healthy physical parts.
  if carry <= 0 or moves <= 0: return 0
  var ticks = HaulingActions
  for step in route:
    let fatigue = if (step.x, step.y) in roads: 1
      elif (terrain.get(step.x, step.y) and TerrainSwamp) != 0: 10
      else: 2
    let recovery = moves * MoveFatiguePower
    ticks += max(1, ((work + carry) * fatigue + recovery - 1) div recovery)
    ticks += max(1, (work * fatigue + recovery - 1) div recovery)
  float(carry * CarryCapacity) / float(ticks)

proc supplementalSource(spawn: StructureSpawn, desiredWorkers: int,
    body: seq[cstring]): Source =
  ## Fund bounded extra transport only after healthy core roles cover recovery and growth.
  let room = spawn.room
  let cost = bodyCost(body)
  if room.controller.isNil or not room.controller.my or room.controller.level < 2 or
      body.len == 0 or room.energyAvailable < cost or game.time mod HaulingPlanTicks != 0 or
      game.cpu.bucket < HaulingBucketReserve or game.cpu.getUsed() > float(game.cpu.limit - HaulingCpuReserve) or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return
  for site in room.findConstructionSites():
    if site.my and site.structureType in [SpawnStructureType, TowerStructureType]: return
  var healthy, haulers, generals, upgraders, extra, livingExtra: int
  for other in game.creeps.items:
    if other.memory.role != WorkerRole or other.memory.homeRoom != room.name: continue
    if other.supplementalHauler():
      inc livingExtra
      if other.productive(): inc extra
      continue
    if other.spawning or not other.productive() or other.room.name != room.name or
        other.getActiveBodyparts("work") == 0 or other.getActiveBodyparts("move") == 0:
      continue
    if other.memory.job != MinerJob and other.getActiveBodyparts("carry") == 0: continue
    inc healthy
    if other.memory.job == HaulerJob:
      if other.memory.sourceId.len == 0: return
      inc haulers
    elif other.memory.job == GeneralJob: inc generals
    elif other.memory.job == UpgraderJob: inc upgraders
  if healthy < desiredWorkers or haulers < DesiredHaulers or
      generals < MinimumGeneralWorkers or upgraders == 0 or
      extra >= SupplementalHaulers or livingExtra >= SupplementalHaulers + 1:
    return
  let
    structures = room.findStructures(FIND_STRUCTURES)
    drops = room.findResources()
    terrain = room.getTerrain()
  var roads: seq[tuple[x, y: int]]
  var work, carry, moves: int
  for structure in structures:
    if structure.structureType == RoadStructureType and structure.hits > 0:
      roads.add((structure.pos.x, structure.pos.y))
  for part in body:
    if part == "work".cstring: inc work
    elif part == "carry".cstring: inc carry
    elif part == "move".cstring: inc moves
  var bestDeficit = float(cost) / float(CreepLifetimeTicks)
  for source in room.find(FIND_SOURCES):
    if source.energyCapacity <= 0 or source.sourceCargo(drops, structures) < cost * 2: continue
    var container = false
    for structure in structures:
      if structure.structureType == ContainerStructureType and structure.hits > 0 and
          structure.pos.distance(source.pos) <= 1:
        container = true
    if not container: continue
    var miningWork = 0
    for other in game.creeps.items:
      if other.memory.role == WorkerRole and other.memory.homeRoom == room.name and
          other.memory.sourceId == source.id and other.memory.job == MinerJob and
          not other.spawning and other.productive() and other.room.name == room.name and
          other.pos.distance(source.pos) <= 1:
        miningWork += other.getActiveBodyparts("work")
    if miningWork == 0: continue
    let route = room.findPath(spawn.pos, source.pos, localPathOptions(1, true))
    if spawn.pos.distance(source.pos) > 1 and (route.len == 0 or
        RoomPosition(x: route[^1].x, y: route[^1].y).distance(source.pos) > 1): continue
    var covered = 0.0
    for other in game.creeps.items:
      if other.memory.role == WorkerRole and other.memory.homeRoom == room.name and
          other.memory.job == HaulerJob and other.memory.sourceId == source.id and
          other.productive() and other.room.name == room.name:
        covered += haulingRate(route, terrain, roads, other.getActiveBodyparts("work"),
          other.getActiveBodyparts("carry"), other.getActiveBodyparts("move"))
    let income = min(float(source.energyCapacity) / float(SourceRegenerationTicks),
      float(miningWork * HarvestPower))
    let recoverable = min(income - covered, haulingRate(route, terrain, roads, work, carry, moves))
    if recoverable > bestDeficit:
      result = source
      bestDeficit = recoverable

proc spawnWorker*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Maintain a room's workforce with an affordable bootstrap body.
  if not spawn.spawning.isNil or spawn.room.energyAvailable < WorkerBodyCost:
    return OK
  if coreWorkerCount(spawn.room.name) >= desiredWorkers:
    if desiredWorkers <= MinimumDeliveryWorkers or game.time mod HaulingPlanTicks != 0 or
        game.cpu.bucket < HaulingBucketReserve or game.cpu.getUsed() > float(game.cpu.limit - HaulingCpuReserve):
      return OK
    let body = haulingWorkerBody(min(spawn.haulerBudget(), spawn.room.energyCapacityAvailable),
      spawn.roadHaulerReady())
    let source = spawn.supplementalSource(desiredWorkers, body)
    if source.isNil: return OK
    let options = SpawnCreepOpts(memory: CreepMemory(role: WorkerRole, homeRoom: spawn.room.name,
      delivering: false, job: HaulerJob, sourceId: source.id))
    options.memory.toJs["supplementalHauler"] = true
    return spawn.spawnCreep(body, cstring("worker-" & $spawn.name & "-" & $game.time), options)
  let workers = coreDeliveryCount(spawn.room.name)
  var job = if workers >= 2 and not hasJob(spawn.room.name, UpgraderJob): UpgraderJob else: GeneralJob
  var source: Source
  if job == GeneralJob and workers >= MinimumDeliveryWorkers and
      desiredWorkers > MinimumDeliveryWorkers and spawn.room.energyCapacityAvailable >= MinimumMinerCost:
    source = spawn.uncoveredSource()
    if not source.isNil:
      job = MinerJob
  if job == GeneralJob and workers >= MinimumDeliveryWorkers and
      hasJob(spawn.room.name, MinerJob) and coreWorkerCount(spawn.room.name, HaulerJob) < DesiredHaulers:
    job = HaulerJob
  if job == GeneralJob and spawn.extraSuppliedUpgrader():
    job = UpgraderJob
  let
    suppliedUpgrader = job == UpgraderJob and workers >= MinimumDeliveryWorkers and
      hasJob(spawn.room.name, HaulerJob)
    maximumCost = if job == HaulerJob: spawn.haulerBudget()
      elif suppliedUpgrader: MaxUpgraderCost
      else: MaxWorkerCost
    bodyBudget = if workers < 2: WorkerBodyCost else:
      max(WorkerBodyCost, min(maximumCost,
        (if workers < MinimumRecoveryCarriers: spawn.room.energyAvailable
          else: spawn.room.energyCapacityAvailable)))
    body = if job == MinerJob: minerBody(bodyBudget)
      elif job == HaulerJob: haulingWorkerBody(bodyBudget, spawn.roadHaulerReady())
      elif suppliedUpgrader: suppliedUpgraderBody(bodyBudget)
      else: workerBody(bodyBudget)
    budget = bodyCost(body)
  if body.len == 0 or spawn.room.energyAvailable < budget:
    return OK
  let
    name = cstring("worker-" & $spawn.name & "-" & $game.time)
    options = SpawnCreepOpts(memory: CreepMemory(
      role: WorkerRole, homeRoom: spawn.room.name, delivering: false,
      job: job, sourceId: (if source.isNil: "".cstring else: source.id)))
  spawn.spawnCreep(body, name, options)

proc assignedSource*(creep: Creep): Source =
  ## Keep workers distributed across the sources in their home room.
  let sources = creep.room.find(FIND_SOURCES)
  for source in sources:
    if source.id == creep.memory.sourceId:
      return source
  var bestCount = high(int)
  var closest: seq[Source]
  for source in sources:
    if creep.pos.findClosestByPath(@[source], localPathOptions(1, true)).isNil:
      continue
    var assigned = 0
    for other in game.creeps.items:
      if other.memory.role == WorkerRole and other.memory.homeRoom == creep.memory.homeRoom and
          other.memory.sourceId == source.id and other.name != creep.name and
          (creep.memory.job notin [MinerJob, HaulerJob] or
          other.memory.job == creep.memory.job) and other.productive():
        inc assigned
    if assigned < bestCount:
      result = source
      bestCount = assigned
      closest = @[source]
    elif assigned == bestCount and creep.memory.job == HaulerJob:
      closest.add(source)
  if creep.memory.job == HaulerJob and closest.len > 0:
    let
      drops = creep.room.findResources()
      structures = creep.room.findStructures(FIND_STRUCTURES)
    var
      hub = creep.pos
      hasHub = false
      longestRoute = -1
      largestCargo = -1
      preferred: seq[Source]
    if bestCount > 0 and closest.len > 1:
      for spawn in game.spawns.items:
        if spawn.room.name == creep.room.name and spawn.room.name == creep.memory.homeRoom:
          hub = spawn.pos
          hasHub = true
          break
    for source in closest:
      let
        cargo = source.sourceCargo(drops, structures)
        routeLength = if not hasHub: 0
          elif hub.distance(source.pos) <= 1: 1
          else: creep.room.findPath(hub, source.pos, localPathOptions(1, true)).len
      if routeLength > longestRoute or (routeLength == longestRoute and cargo > largestCargo):
        longestRoute = routeLength
        largestCargo = cargo
        preferred = @[source]
      elif routeLength == longestRoute and cargo == largestCargo:
        preferred.add(source)
    result = creep.pos.findClosestByPath(preferred, localPathOptions(1, true))
  if not result.isNil:
    creep.memory.sourceId = result.id

proc beginWorkJobs*() =
  ## Begin a fresh reservation ledger before controlling the tick's workers.
  reservedEnergy.clear()
  acceptedRefillEnergy.clear()
  acceptedSupplyEnergy.clear()
  reservationTick = game.time

proc remainingSupplyEnergy(creep: Creep): int =
  ## Exclude worker needs covered by accepted transfers during the current tick.
  let free = creep.store.getFreeCapacity(RESOURCE_ENERGY)
  if free < WorkerSupplyMinimum:
    return free
  if reservationTick != game.time:
    beginWorkJobs()
  if acceptedSupplyEnergy.len == 0:
    return free
  max(0, free - acceptedSupplyEnergy.getOrDefault($creep.name))

proc workerSupplyTarget*(creep: Creep): Creep =
  ## Find a reachable worker needing a useful load, prioritizing controller work.
  var upgraders, workers: seq[Creep]
  let controller = creep.room.controller
  for other in game.creeps.items:
    if other.name == creep.name or other.spawning or other.memory.role != WorkerRole or
        other.room.name != creep.room.name or other.memory.homeRoom != creep.room.name or
        other.memory.job in [MinerJob, HaulerJob] or
        other.remainingSupplyEnergy() < WorkerSupplyMinimum:
      continue
    if other.memory.job == UpgraderJob:
      let waiting = other.memory.supplyWaitStart > 0 and
        other.memory.supplyWaitStart <= game.time and
        game.time - other.memory.supplyWaitStart < SupplyWaitTicks
      if not controller.isNil and controller.my and
          (other.pos.distance(controller.pos) <= ControllerWorkRange or
          creep.pos.distance(other.pos) <= 1 or waiting):
        upgraders.add(other)
    else:
      workers.add(other)
  result = creep.pos.findClosestByPath(upgraders)
  if result.isNil:
    result = creep.pos.findClosestByPath(workers)

proc collectionTarget(creep: Creep, targets: seq[RoomObject]): RoomObject =
  ## Let haulers retain reachable cargo destinations through temporary congestion.
  if creep.memory.job == HaulerJob:
    creep.pos.findClosestByPath(targets, localPathOptions(1, true))
  else:
    creep.pos.findClosestByPath(targets)

proc harvestEnergy*(creep: Creep) =
  ## Collect useful stored or dropped loads while miners extract into source containers.
  if creep.memory.job != MinerJob:
    if creep.memory.job == UpgraderJob and
        deliveryWorkerCount(creep.memory.homeRoom) >= MinimumDeliveryWorkers:
      let receiver = creep.room.controllerLinks().receiver
      if not receiver.isNil and receiver.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
        let code = creep.withdraw(receiver, RESOURCE_ENERGY)
        if code == OK:
          creep.memory.delivering = true
          creep.memory.toJs["storageSupply"] = false
          return
        if code == ERR_NOT_IN_RANGE and creep.moveWorker(receiver) != ERR_NO_PATH:
          return
    var
      drops: seq[Resource]
      containers, storages, links: seq[Structure]
      targets, assignedTargets: seq[RoomObject]
    let
      source = if creep.memory.job == HaulerJob: creep.assignedSource() else: nil
      needed = creep.store.getFreeCapacity(RESOURCE_ENERGY)
      hauling = creep.memory.job == HaulerJob
      controller = creep.room.controller
      urgent = not controller.isNil and controller.my and
        controller.ticksToDowngrade < ControllerUrgencyTicks
      spawningNeedsEnergy = creep.room.energyAvailable < creep.room.energyCapacityAvailable
      reserveNeeded = urgent or (spawningNeedsEnergy and
        (creep.memory.job != UpgraderJob or creep.room.energyAvailable < WorkerBodyCost or
        deliveryWorkerCount(creep.memory.homeRoom) < MinimumDeliveryWorkers))
    var combatSupply = false
    for resource in creep.room.findResources():
      if resource.resourceType == RESOURCE_ENERGY and resource.amount >= needed and resource.amount > 0:
        drops.add(resource)
        targets.add(RoomObject(resource))
        if not source.isNil and resource.pos.distance(source.pos) <= 1:
          assignedTargets.add(RoomObject(resource))
    for structure in creep.room.findStructures(FIND_STRUCTURES):
      if structure.my and structure.structureType == TowerStructureType and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) < TowerCombatReserve and
          creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
        combatSupply = true
      if structure.structureType == ContainerStructureType and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) >= needed and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
        containers.add(structure)
        targets.add(RoomObject(structure))
        if not source.isNil and structure.pos.distance(source.pos) <= 1:
          assignedTargets.add(RoomObject(structure))
      elif structure.my and structure.structureType == StorageStructureType:
        storages.add(structure)
      elif structure.my and structure.structureType == LinkStructureType and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) >= needed and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
        links.add(structure)
    var
      storageTargets, emergencyTargets: seq[RoomObject]
      surplusSupply = not hauling
    if hauling and not (reserveNeeded or combatSupply):
      for storage in storages:
        if storage.store.getUsedCapacity(RESOURCE_ENERGY) >= StorageReserveEnergy + needed:
          surplusSupply = deliveryWorkerCount(creep.memory.homeRoom) >= MinimumDeliveryWorkers and
            not creep.workerSupplyTarget().isNil
          break
    for storage in storages:
      let available = storage.store.getUsedCapacity(RESOURCE_ENERGY)
      if available > 0 and ((reserveNeeded or combatSupply) or
          (available >= StorageReserveEnergy + needed and surplusSupply)):
        containers.add(storage)
        targets.add(RoomObject(storage))
        storageTargets.add(RoomObject(storage))
    if reserveNeeded or combatSupply:
      for link in links:
        containers.add(link)
        targets.add(RoomObject(link))
        emergencyTargets.add(RoomObject(link))
    let preferred = if (reserveNeeded or combatSupply) and storageTargets.len > 0:
        creep.collectionTarget(storageTargets)
      elif emergencyTargets.len > 0: creep.collectionTarget(emergencyTargets)
      elif assignedTargets.len > 0: creep.collectionTarget(assignedTargets)
      else: nil
    let target = if preferred.isNil: creep.collectionTarget(targets) else: preferred
    if not target.isNil:
      var code = ERR_INVALID_TARGET
      for drop in drops:
        if RoomObject(drop) == target:
          code = creep.pickup(drop)
      for container in containers:
        if RoomObject(container) == target:
          code = creep.withdraw(container, RESOURCE_ENERGY)
      if code == OK:
        let storageLoad = target in storageTargets
        creep.memory.toJs["storageSupply"] = storageLoad
        if storageLoad:
          creep.memory.delivering = true
        return
      if code == ERR_NOT_IN_RANGE:
        if creep.moveWorker(target) != ERR_NO_PATH:
          return
  let source = creep.assignedSource()
  if source.isNil:
    return
  if creep.memory.job == MinerJob:
    var containers: seq[Structure]
    for structure in creep.room.findStructures(FIND_STRUCTURES):
      if structure.structureType == ContainerStructureType and structure.pos.distance(source.pos) <= 1:
        containers.add(structure)
    let container = creep.pos.findClosestByPath(containers)
    if not container.isNil and creep.pos.distance(container.pos) > 0:
      if creep.moveLocal(container.pos, 0) != ERR_NO_PATH:
        return
  if source.energy > 0:
    let harvested = creep.harvest(source)
    if harvested == OK and creep.memory.job == MinerJob:
      creep.holdLocalPosition()
    elif harvested == ERR_NOT_IN_RANGE:
      let code = creep.moveWorker(source)
      if code == ERR_NO_PATH and creep.memory.job != MinerJob:
        creep.memory.sourceId = "".cstring
  elif creep.memory.job != MinerJob and creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
    creep.memory.delivering = true

proc constructionPriority(site: ConstructionSite, assets: seq[Structure]): int =
  ## Protect completed owned spawns before other construction.
  if site.structureType == RampartStructureType:
    for asset in assets:
      if asset.my and asset.structureType == SpawnStructureType and
          asset.pos.x == site.pos.x and asset.pos.y == site.pos.y:
        return -1
  case $site.structureType
  of "spawn": 0
  of "tower": 1
  of "link": 2
  of "extension": 3
  of "container": 4
  of "storage": 5
  of "rampart": 6
  of "road": 8
  else: 7

proc constructionTarget*(creep: Creep): ConstructionSite =
  ## Concentrate builders on the most advanced reachable useful site.
  var sites: seq[ConstructionSite]
  for site in creep.room.findConstructionSites():
    if site.my:
      sites.add(site)
  let assets = creep.room.findStructures(FIND_STRUCTURES)
  sites.sort(proc(a, b: ConstructionSite): int =
    result = cmp(a.constructionPriority(assets), b.constructionPriority(assets))
    if result == 0:
      result = cmp(b.progress, a.progress))
  for site in sites:
    if not creep.pos.findClosestByPath(@[site]).isNil:
      return site

proc prepareWorkTargets*(creep: Creep, refill: Structure,
    repairs: seq[Structure]): WorkTargets =
  ## Prepare ordinary general-worker tasks without issuing game intents.
  result.refill = refill
  result.build = creep.constructionTarget()
  result.controller = creep.room.controller
  var importantRepairs: seq[Structure]
  for structure in repairs:
    if structure.structureType != RoadStructureType or result.build.isNil or
        result.build.structureType == RoadStructureType:
      importantRepairs.add(structure)
  result.repair = creep.pos.findClosestByPath(importantRepairs)
  let objects = [RoomObject(result.refill), RoomObject(result.repair),
    RoomObject(result.build), RoomObject(result.controller)]
  for task in WorkTask:
    let index = ord(task)
    result.observation.eligible[index] = not objects[index].isNil and
      (task != Upgrade or result.controller.my)
    result.observation.features[index] = if result.observation.eligible[index]: 1 else: 0
    result.observation.features[ActionCount + index] =
      if objects[index].isNil: 1.0'f32
      else: normalized(creep.pos.distance(objects[index].pos).float32, DistanceScale)
  result.observation.features[8] = normalized(
    creep.store.getUsedCapacity(RESOURCE_ENERGY).float32,
    max(1, creep.store.getCapacity(RESOURCE_ENERGY)).float32)
  result.observation.features[9] = normalized(creep.room.energyAvailable.float32,
    max(1, creep.room.energyCapacityAvailable).float32)
  if not result.controller.isNil:
    result.observation.features[10] = normalized(result.controller.level.float32, ControllerLevelScale)
    result.observation.features[11] = normalized(result.controller.ticksToDowngrade.float32, DowngradeScale)

proc executeWorkTask*(creep: Creep, targets: WorkTargets, task: WorkTask): ReturnCode =
  ## Execute one prepared eligible task and reuse local movement on range failures.
  if not targets.observation.eligible[ord(task)]:
    raise newException(ValueError, "Worker selected an unavailable task")
  case task
  of Refill:
    result = creep.transfer(targets.refill, RESOURCE_ENERGY)
    if result == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(targets.refill)
  of Repair:
    result = creep.repair(targets.repair)
    if result == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(targets.repair)
  of Build:
    result = creep.build(targets.build)
    if result == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(targets.build)
  of Upgrade:
    result = creep.upgradeControllerWork(targets.controller)
    if result == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(targets.controller, ControllerWorkRange)

proc targetIdentity(target: RoomObject): string =
  ## Identify real targets and coordinate-only fixtures consistently.
  if not target.toJs["id"].isNil:
    result = $target.id
  if result.len == 0:
    result = $target.pos.x & ":" & $target.pos.y

proc prepareJobs*(creep: Creep, refills, repairs: seq[Structure]): PreparedJobs =
  ## Prepare bounded reachable jobs without issuing any game intents.
  if reservationTick != game.time:
    beginWorkJobs()
  let
    ordinary = creep.prepareWorkTargets(creep.pos.findClosestByPath(refills), repairs)
    base = ordinary.observation.features
    energy = creep.store.getUsedCapacity(RESOURCE_ENERGY).float32
  result.observation.creepId = $creep.name
  result.observation.roomName = $creep.room.name
  for task in WorkTask:
    var objects: seq[RoomObject]
    case task
    of Refill:
      for target in refills: objects.add(RoomObject(target))
    of Repair:
      for target in repairs:
        if target.structureType != RoadStructureType or ordinary.build.isNil or
            ordinary.build.structureType == RoadStructureType:
          objects.add(RoomObject(target))
    of Build:
      for target in creep.room.findConstructionSites():
        if target.my: objects.add(RoomObject(target))
    of Upgrade:
      if not ordinary.controller.isNil and ordinary.controller.my:
        objects.add(RoomObject(ordinary.controller))
    let preferred = case task
      of Refill: RoomObject(ordinary.refill)
      of Repair: RoomObject(ordinary.repair)
      of Build: RoomObject(ordinary.build)
      of Upgrade: RoomObject(ordinary.controller)
    objects.sort(proc(a, b: RoomObject): int =
      result = cmp(a != preferred, b != preferred)
      if result == 0:
        result = cmp(creep.pos.distance(a.pos), creep.pos.distance(b.pos))
      if result == 0: result = cmp(targetIdentity(a), targetIdentity(b)))
    var admitted = 0
    for target in objects:
      if admitted >= CandidatesPerTask:
        break
      var
        job = WorkCandidate(task: task, targetId: targetIdentity(target))
        work = WorkTargets()
        need = energy
      work.observation.eligible[ord(task)] = true
      job.features[ord(task)] = 1
      job.features[4] = normalized(max(0, creep.pos.distance(target.pos) -
        (if task == Refill: 1 else: 3)).float32, DistanceScale)
      job.features[8] = base[8]
      job.features[9] = base[9]
      job.features[10] = base[10]
      job.features[11] = base[11]
      case task
      of Refill:
        work.refill = Structure(target)
        need = work.refill.store.getFreeCapacity(RESOURCE_ENERGY).float32
        job.features[14] = normalized(need,
          max(1, work.refill.store.getCapacity(RESOURCE_ENERGY)).float32)
        job.features[5] = job.features[14]
      of Repair:
        work.repair = Structure(target)
        need = max(0, min(work.repair.hitsMax, RepairTargetHits) - work.repair.hits).float32 / RepairWorkPower
        job.features[12] = normalized((work.repair.hitsMax - work.repair.hits).float32,
          max(1, work.repair.hitsMax).float32)
        job.features[5] = job.features[12]
      of Build:
        work.build = ConstructionSite(target)
        need = (work.build.progressTotal - work.build.progress).float32 / BuildWorkPower
        job.features[13] = normalized(work.build.progress.float32, max(1, work.build.progressTotal).float32)
        job.features[5] = 1 - job.features[13]
        job.features[6] = normalized((work.build.constructionPriority(creep.room.findStructures(FIND_STRUCTURES)) + 1).float32, ConstructionPriorityScale)
      of Upgrade:
        work.controller = StructureController(target)
        job.features[5] = 1
      let reserved = reservedEnergy.getOrDefault($ord(task) & ":" & job.targetId)
      job.features[7] = if task == Upgrade: 0 else: normalized(reserved, max(1.0'f32, need))
      if task != Upgrade and (need <= 0 or reserved >= need):
        continue
      if target != preferred and creep.pos.findClosestByPath(@[target]).isNil:
        continue
      inc admitted
      result.observation.candidates.add(job)
      result.targets.add(work)
      result.needs.add(need)
  if result.observation.candidates.len > 0:
    result.observation.teacherIndex = 0

proc executeJob*(creep: Creep, jobs: PreparedJobs, index: int): ReturnCode =
  ## Validate a selected target immediately and reserve its intended energy.
  if index notin 0 ..< jobs.targets.len:
    raise newException(ValueError, "Policy selected an invalid job index")
  let
    candidate = jobs.observation.candidates[index]
    work = jobs.targets[index]
    energy = creep.store.getUsedCapacity(RESOURCE_ENERGY).float32
  case candidate.task
  of Refill:
    if not work.refill.my or work.refill.store.getFreeCapacity(RESOURCE_ENERGY) <= 0:
      raise newException(ValueError, "Refill target is no longer eligible")
  of Repair:
    if work.repair.hits >= work.repair.hitsMax:
      raise newException(ValueError, "Repair target is complete")
  of Build:
    if not work.build.my or work.build.progress >= work.build.progressTotal:
      raise newException(ValueError, "Build target is no longer eligible")
  of Upgrade:
    if not work.controller.my:
      raise newException(ValueError, "Upgrade target is no longer owned")
  result = creep.executeWorkTask(work, candidate.task)
  if result in [OK, ERR_NOT_IN_RANGE] and candidate.task != Upgrade:
    let key = $ord(candidate.task) & ":" & candidate.targetId
    reservedEnergy[key] = reservedEnergy.getOrDefault(key) +
      min(energy, jobs.needs[index])

proc remainingRefillEnergy(target: Structure): int =
  ## Exclude same-turn spawning deficits covered by accepted worker transfers.
  let free = target.store.getFreeCapacity(RESOURCE_ENERGY)
  if free <= 0:
    return 0
  if reservationTick != game.time:
    beginWorkJobs()
  if acceptedRefillEnergy.len == 0:
    return free
  max(0, free - acceptedRefillEnergy.getOrDefault(target.targetIdentity()))

proc refillEnergy(creep: Creep, target: Structure): ReturnCode =
  ## Account accepted spawning refills while leaving unsuccessful promises unreserved.
  let amount = min(creep.store.getUsedCapacity(RESOURCE_ENERGY),
    target.store.getFreeCapacity(RESOURCE_ENERGY))
  result = creep.transfer(target, RESOURCE_ENERGY)
  if result == OK:
    let key = target.targetIdentity()
    acceptedRefillEnergy[key] = acceptedRefillEnergy.getOrDefault(key) + amount

proc deliverEnergy*(creep: Creep, canWork = true, policy = WorkerTaskPolicy()) =
  ## Refill spawning infrastructure, then build or upgrade the owned controller.
  var targets, towers, repairs, storages: seq[Structure]
  var spawningFuel = creep.room.energyAvailable
  for structure in creep.room.findStructures(FIND_STRUCTURES):
    let repairLimit = if structure.structureType == RoadStructureType and
        creep.pos.distance(structure.pos) > RepairRange:
      min(RepairTargetHits, structure.hitsMax * RoadRepairPercent div 100)
      else: RepairTargetHits
    if structure.my and structure.structureType in [SpawnStructureType, ExtensionStructureType]:
      let remaining = structure.remainingRefillEnergy()
      if remaining > 0: targets.add(structure)
      spawningFuel += structure.store.getFreeCapacity(RESOURCE_ENERGY) - remaining
    if structure.my and structure.structureType == TowerStructureType and
        structure.store.getFreeCapacity(RESOURCE_ENERGY) > 0 and
        (structure.store.getFreeCapacity(RESOURCE_ENERGY) >= TowerRefillBatch or
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0):
      towers.add(structure)
    if structure.my and structure.structureType == StorageStructureType and
        structure.store.getFreeCapacity(RESOURCE_ENERGY) > 0:
      storages.add(structure)
    if (structure.my or structure.structureType in [RoadStructureType, ContainerStructureType]) and
        structure.hits < min(structure.hitsMax, repairLimit):
      repairs.add(structure)
  let
    target = creep.pos.findClosestByPath(targets)
    tower = creep.pos.findClosestByPath(towers)
    storage = creep.pos.findClosestByPath(storages)
    controller = creep.room.controller
    urgent = not controller.isNil and controller.my and
      controller.ticksToDowngrade < ControllerUrgencyTicks
    dedicated = creep.memory.job == UpgraderJob and deliveryWorkerCount(creep.memory.homeRoom) >= MinimumDeliveryWorkers
    bootstrap = creep.room.energyAvailable < WorkerBodyCost
    combatSupply = not tower.isNil and not bootstrap and
      tower.store.getUsedCapacity(RESOURCE_ENERGY) < TowerCombatReserve and
      creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0
  var neuralHandled = false
  if (not policy.choose.isNil or not policy.chooseJob.isNil) and creep.memory.job == GeneralJob and canWork:
    if combatSupply or urgent or bootstrap or not tower.isNil:
      if not policy.overridden.isNil:
        policy.overridden(if combatSupply: "combat" elif urgent: "controller"
          elif bootstrap: "bootstrap" else: "tower")
    else:
      if not policy.chooseJob.isNil:
        let started = game.cpu.getUsed()
        let prepared = creep.prepareJobs(targets, repairs)
        if not policy.prepared.isNil:
          policy.prepared(game.cpu.getUsed() - started)
        if prepared.observation.candidates.len > 0:
          var selected = prepared.observation.teacherIndex
          try:
            selected = policy.chooseJob(prepared.observation)
            if selected notin 0 ..< prepared.observation.candidates.len:
              raise newException(ValueError, "Policy selected an invalid job")
          except:
            recordFailure("Worker job policy " & $creep.name, getCurrentException().msg)
            selected = prepared.observation.teacherIndex
          let candidate = prepared.observation.candidates[selected]
          let code = creep.executeJob(prepared, selected)
          if not policy.selectedJob.isNil: policy.selectedJob(candidate)
          if not policy.executed.isNil: policy.executed(candidate.task, ord(code))
          neuralHandled = true
      else:
        let prepared = creep.prepareWorkTargets(target, repairs)
        if prepared.observation.eligibleCount > 0:
          var task = prepared.observation.teacherTask()
          try:
            task = policy.choose(prepared.observation)
            if not prepared.observation.eligible[ord(task)]:
              raise newException(ValueError, "Policy selected an unavailable task")
          except:
            recordFailure("Worker policy " & $creep.name, getCurrentException().msg)
            task = prepared.observation.teacherTask()
          let code = creep.executeWorkTask(prepared, task)
          if not policy.executed.isNil:
            policy.executed(task, ord(code))
          neuralHandled = true
  if neuralHandled:
    discard
  elif combatSupply:
    if creep.transfer(tower, RESOURCE_ENERGY) == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(tower)
  elif (not urgent or not canWork) and not target.isNil and (not dedicated or bootstrap):
    if creep.refillEnergy(target) == ERR_NOT_IN_RANGE:
      discard creep.moveWorker(target)
  else:
    let
      site = creep.constructionTarget()
      recipient = if (creep.memory.job == HaulerJob or not canWork) and
          deliveryWorkerCount(creep.memory.homeRoom) >= MinimumDeliveryWorkers:
        creep.workerSupplyTarget()
        else: nil
      starvedUpgrader = not storage.isNil and
        storage.store.getUsedCapacity(RESOURCE_ENERGY) < StorageReserveEnergy and
        not recipient.isNil and recipient.memory.job == UpgraderJob and
        recipient.store.getUsedCapacity(RESOURCE_ENERGY) == 0 and
        not controller.isNil and controller.my and
        creep.room.energyAvailable >= creep.room.energyCapacityAvailable and
        deliveryWorkerCount(creep.memory.homeRoom) >= MinimumRecoveryCarriers and
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len == 0
    let pair = if creep.memory.job == HaulerJob: creep.room.controllerLinks() else: ControllerLinkPair()
    let controllerRecipient = not recipient.isNil and recipient.memory.job == UpgraderJob and
      recipient.pos.distance(controller.pos) <= ControllerWorkRange
    var recoveringUpgrader = false
    if not controllerRecipient and not pair.sender.isNil and not pair.receiver.isNil and
        pair.sender.store.getFreeCapacity(RESOURCE_ENERGY) >= WorkerSupplyMinimum and
        pair.receiver.store.getFreeCapacity(RESOURCE_ENERGY) >= MinimumLinkTransfer and
        not controller.isNil and controller.my and
        spawningFuel >= creep.room.energyCapacityAvailable and
        deliveryWorkerCount(creep.memory.homeRoom) >= MinimumRecoveryCarriers and
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len == 0:
      for other in game.creeps.items:
        if other.memory.role == WorkerRole and other.memory.job == UpgraderJob and
            other.memory.homeRoom == creep.room.name and other.room.name == creep.room.name and
            not other.spawning and other.productive() and
            other.getActiveBodyparts("work") > 0 and other.getActiveBodyparts("carry") > 0 and
            other.getActiveBodyparts("move") > 0 and
            other.store.getUsedCapacity(RESOURCE_ENERGY) == 0 and
            other.pos.distance(controller.pos) > ControllerWorkRange:
          recoveringUpgrader = true
          break
    let link = if not pair.sender.isNil and not pair.receiver.isNil and
        (recoveringUpgrader or controllerRecipient) and
        deliveryWorkerCount(creep.memory.homeRoom) >= MinimumRecoveryCarriers and
        (storage.isNil or storage.store.getUsedCapacity(RESOURCE_ENERGY) >= StorageReserveEnergy or
        starvedUpgrader or recoveringUpgrader) and
        pair.sender.store.getFreeCapacity(RESOURCE_ENERGY) >= WorkerSupplyMinimum and
        pair.receiver.store.getFreeCapacity(RESOURCE_ENERGY) >= MinimumLinkTransfer:
      creep.pos.findClosestByPath(@[Structure(pair.sender)])
      else: nil
    var importantRepairs: seq[Structure]
    for structure in repairs:
      if structure.structureType != RoadStructureType or site.isNil or
          site.structureType == RoadStructureType:
        importantRepairs.add(structure)
    if canWork and (urgent or dedicated) and not controller.isNil and controller.my:
      if creep.upgradeControllerWork(controller) == ERR_NOT_IN_RANGE:
        discard creep.moveWorker(controller, ControllerWorkRange)
    elif not tower.isNil:
      if creep.transfer(tower, RESOURCE_ENERGY) == ERR_NOT_IN_RANGE:
        discard creep.moveWorker(tower)
    elif not link.isNil:
      if creep.transfer(link, RESOURCE_ENERGY) == ERR_NOT_IN_RANGE:
        discard creep.moveWorker(link)
    elif (creep.memory.job == HaulerJob or not canWork) and not storage.isNil and
        not creep.memory.toJs["storageSupply"].to(bool) and
        (recipient.isNil or (storage.store.getUsedCapacity(RESOURCE_ENERGY) < StorageReserveEnergy and
        not starvedUpgrader)):
      if creep.transfer(storage, RESOURCE_ENERGY) == ERR_NOT_IN_RANGE:
        discard creep.moveWorker(storage)
    elif not recipient.isNil:
      let amount = min(creep.store.getUsedCapacity(RESOURCE_ENERGY),
        recipient.remainingSupplyEnergy())
      let code = creep.transfer(recipient, RESOURCE_ENERGY)
      if code == OK:
        let key = $recipient.name
        acceptedSupplyEnergy[key] = acceptedSupplyEnergy.getOrDefault(key) + amount
        recipient.memory.delivering = true
        recipient.memory.toJs["workerSupplyTick"] = game.time
      elif code == ERR_NOT_IN_RANGE:
        discard creep.moveWorker(recipient)
    elif canWork:
      let repairTarget = creep.pos.findClosestByPath(importantRepairs)
      if not repairTarget.isNil:
        if creep.repair(repairTarget) == ERR_NOT_IN_RANGE:
          discard creep.moveWorker(repairTarget)
      elif not site.isNil:
        if creep.build(site) == ERR_NOT_IN_RANGE:
          discard creep.moveWorker(site)
      elif not controller.isNil and controller.my:
        if creep.upgradeControllerWork(controller) == ERR_NOT_IN_RANGE:
          discard creep.moveWorker(controller, ControllerWorkRange)

proc awaitSupply(creep: Creep): bool =
  ## Keep an empty supplied upgrader near its work for a bounded delivery window.
  let controller = creep.room.controller
  if creep.memory.job != UpgraderJob or controller.isNil or not controller.my or
      creep.room.energyAvailable < WorkerBodyCost or
      deliveryWorkerCount(creep.memory.homeRoom) < MinimumDeliveryWorkers:
    return false
  let receiver = creep.room.controllerLinks().receiver
  if not receiver.isNil and receiver.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
    return false
  var hauling = false
  for other in game.creeps.items:
    if other.memory.role == WorkerRole and other.memory.homeRoom == creep.memory.homeRoom and
        other.memory.job == HaulerJob and not other.spawning and other.productive():
      hauling = true
      break
  if not hauling:
    return false
  if not (creep.memory.supplyWaitStart > 0):
    creep.memory.supplyWaitStart = game.time
  if game.time - creep.memory.supplyWaitStart >= SupplyWaitTicks:
    return false
  if creep.pos.distance(controller.pos) > ControllerWorkRange and
      creep.moveWorker(controller, ControllerWorkRange) == ERR_NO_PATH:
    return false
  true

proc runWorker*(creep: Creep, policy = WorkerTaskPolicy(), canWork = true) =
  ## Alternate between collecting energy and performing useful work.
  if creep.spawning:
    return
  if not creep.memory.homeRoom.isNil and creep.memory.homeRoom.len > 0 and
      creep.room.name != creep.memory.homeRoom:
    discard creep.moveTo(newRoomPosition(25, 25, creep.memory.homeRoom), PathOptions(range: 20))
    return
  if creep.memory.job == MinerJob:
    creep.harvestEnergy()
    return
  let used = creep.store.getUsedCapacity(RESOURCE_ENERGY)
  if used == 0:
    creep.memory.delivering = false
    creep.memory.toJs["storageSupply"] = false
  elif creep.store.getFreeCapacity(RESOURCE_ENERGY) == 0 or
      (creep.memory.toJs["workerSupplyTick"].to(int) > 0 and
      creep.memory.toJs["workerSupplyTick"].to(int) == game.time - 1) or
      (creep.memory.supplyWaitStart > 0 and
      game.time - creep.memory.supplyWaitStart <= SupplyWaitTicks):
    creep.memory.delivering = true
  if creep.memory.delivering:
    creep.memory.supplyWaitStart = 0
    creep.deliverEnergy(canWork = canWork, policy = policy)
  elif used == 0 and creep.awaitSupply():
    discard
  else:
    creep.harvestEnergy()

proc cleanupCreepMemory*() =
  ## Delete memory belonging to creeps that have died.
  for name in memory.creeps.keys:
    if game.creeps[name].isNil:
      discard jsDelete(memory.creeps[name])
