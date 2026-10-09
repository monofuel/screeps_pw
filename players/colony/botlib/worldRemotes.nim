import
  std/jsffi,
  screeps_lib,
  ./[worldWorkers, worldScouting, worldInfrastructure, worldMovement]

const
  RemoteRole* = "remote".cstring
  RemoteCost* = 350
  RemoteCargoCost = 100
  RemoteCarryCapacity = 50
  RemoteHarvestPower = 2
  MaxRemoteCost = RemoteCost * 4
  RemotePlanInterval = 20
  RemoteCpuReserve = 2000
  RemoteTowerReserve = 500
  RemoteRetirementTicks = 200
  RemoteRouteTimeout = 300
  RemoteSourceWait = 100
  RemoteMaxCycle = 300
  RemoteHarvestTicks = 50
  RemoteDeliveryAllowance = 30
  RemoteArrivalRange = 20
  RemotePathRetryTicks* = 30
  RemotePathRetryInterval* = 5
  LocalReuseLifetime = 300
  LocalReuseLoadLifetime = 100
  ParallelRemoteLevel = 4
  ParallelRemoteCapacity = 1000
  RemoteMinerJob* = "remoteMiner".cstring
  RemoteCarrierJob* = "remoteCarrier".cstring
  RemoteSourceRegeneration = 300
  RemoteMinerWorkLimit = 5
  RemoteMiningReserve = 2000
  RemoteInitialOperationLimit = 2
  RemoteOperationLimit = 3
  RemoteInitialCoordinatedLimit = RemoteInitialOperationLimit * 2 + 1
  RemoteCoordinatedLimit = RemoteOperationLimit * 2 + 1
  RemoteReservedCoordinatedLimit = RemoteOperationLimit * 3 + 1
  RemoteReplacementSlack = 50
  RemoteSpawnTicks = 3
  RemoteContainerRepairHits = 100000
  RemoteRepairPower = 100
  RemoteBuildPower = 5

proc remoteCost*(energy: int): int =
  ## Select affordable harvesting and carrying capacity for one remote operation.
  let
    budget = max(0, min(energy, MaxRemoteCost))
    core = budget div RemoteCost * RemoteCost
  result = core
  if budget >= ParallelRemoteCapacity:
    result += (budget - core) div RemoteCargoCost * RemoteCargoCost

proc remoteBody*(energy: int): seq[cstring] =
  ## Preserve loaded travel speed while scaling harvesting and carrying together.
  let cost = remoteCost(energy)
  for unit in 0 ..< cost div RemoteCost:
    result.add(["work".cstring, "carry".cstring, "carry".cstring,
      "move".cstring, "move".cstring, "move".cstring])
  for cargo in 0 ..< (cost mod RemoteCost) div RemoteCargoCost:
    result.add(["carry".cstring, "move".cstring])

proc remoteMinerBody*(sourceCapacity: int): seq[cstring] =
  ## Fund extraction at source regeneration speed with full outbound movement.
  let work = min(RemoteMinerWorkLimit, max(1,
    (sourceCapacity + RemoteSourceRegeneration * RemoteHarvestPower - 1) div
    (RemoteSourceRegeneration * RemoteHarvestPower)))
  for part in 0 ..< work:
    result.add("work".cstring)
  result.add("carry".cstring)
  for part in 0 ..< work:
    result.add("move".cstring)

proc remoteCarrierBody*(energy: int): seq[cstring] =
  ## Preserve full loaded movement while dedicating the budget to transport.
  for part in 0 ..< max(0, min(energy, MaxRemoteCost)) div RemoteCargoCost:
    result.add(["carry".cstring, "move".cstring])

proc remoteBodyCost(body: seq[cstring]): int =
  ## Account for the exact extraction or transport body funded at spawn time.
  for part in body:
    result += (if part == "work".cstring: 100 else: 50)

proc remoteHarvestTime(energy: int): int =
  ## Estimate the harvesting ticks needed to fill the funded body's cargo.
  var work, carry: int
  for part in remoteBody(energy):
    if part == "work".cstring: inc work
    elif part == "carry".cstring: inc carry
  if work == 0:
    return RemoteHarvestTicks
  let power = work * RemoteHarvestPower
  (carry * RemoteCarryCapacity + power - 1) div power

proc remoteLifeBudget*(target: JsObject, departing: bool): int =
  ## Reserve return slack and require a complete cycle before an empty departure.
  if target.isNil or target["travelEstimate"].isNil or target["travelEstimate"].to(int) <= 0:
    return RemoteRetirementTicks
  result = target["travelEstimate"].to(int) * 2 + RemoteDeliveryAllowance
  if departing:
    result += RemoteHarvestTicks
    if not target["cycleEstimate"].isNil:
      result = max(result, target["cycleEstimate"].to(int))

proc remoteStats*(home: cstring): JsObject =
  ## Retain bounded operation totals independently of individual creep lifetimes.
  let root = memory.toJs
  if root["worldRemotes"].isNil:
    root["worldRemotes"] = newJsObject()
  if root["worldRemotes"][home].isNil:
    let stats = newJsObject()
    stats["spawnCost"] = 0
    stats["homeEnergy"] = 0
    stats["spawned"] = 0
    stats["deferred"] = newJsObject()
    root["worldRemotes"][home] = stats
  result = root["worldRemotes"][home]
  for key in ["infrastructureWorkEnergy", "unverifiedWorkEnergy", "carrierLifetimes", "paidCarrierLifetimes"]:
    if result[key].isNil: result[key] = 0
  if result["operations"].isNil:
    result["operations"] = newJsObject()
  if result["lifetimes"].isNil:
    result["lifetimes"] = newJsObject()
  if result["economicDeferred"].isNil:
    result["economicDeferred"] = newJsObject()
  if result["threatDeferred"].isNil:
    result["threatDeferred"] = newJsObject()
  if not result["activeName"].isNil and result["activeName"].to(cstring).len > 0:
    let name = result["activeName"].to(cstring)
    if result["lifetimes"][name].isNil and not result["target"].isNil:
      let lifetime = newJsObject()
      lifetime["cost"] = if result["activeCost"].isNil: RemoteCost else: result["activeCost"].to(int)
      lifetime["homeEnergy"] = result["activeEnergy"].to(int)
      lifetime["target"] = result["target"]
      result["lifetimes"][name] = lifetime

proc remoteSourceOccupied(home, source: cstring): bool =
  ## Reserve an assigned source until its collector has left the live workforce.
  for creep in game.creeps.items:
    if creep.memory.role == RemoteRole and creep.memory.homeRoom == home:
      let target = creep.memory.toJs["remoteTarget"]
      if not target.isNil and target["source"].to(cstring) == source:
        return true

proc finishRemoteLifetimes(stats: JsObject) =
  ## Close actual lifetimes and pause new investment after underpaid collection.
  var finished: seq[cstring]
  for name, lifetime in stats["lifetimes"].pairs:
    if game.creeps[name].isNil:
      let
        cost = lifetime["cost"].to(int)
        energy = lifetime["homeEnergy"].to(int)
      stats["lastLifetimeEnergy"] = energy
      stats["lastLifetimeCost"] = cost
      stats["lastLifetimeEnd"] = game.time
      if not lifetime["job"].isNil and lifetime["job"].to(cstring) == RemoteCarrierJob:
        stats["carrierLifetimes"] = stats["carrierLifetimes"].to(int) + 1
        if energy > cost:
          stats["paidCarrierLifetimes"] = stats["paidCarrierLifetimes"].to(int) + 1
        stats["lastCarrierLifetimeCost"] = cost
        stats["lastCarrierLifetimeEnergy"] = energy
        stats["lastCarrierLifetimeEnd"] = game.time
      if energy < cost and not lifetime["handoff"].to(bool) and
          (lifetime["job"].isNil or lifetime["job"].to(cstring) != RemoteMinerJob):
        stats["economicDeferred"][lifetime["target"]["room"].to(cstring)] = game.time + IntelRefreshTicks
      if not stats["activeName"].isNil and stats["activeName"].to(cstring) == name:
        stats["activeName"] = "".cstring
      finished.add(name)
  for name in finished:
    discard jsDelete(stats["lifetimes"][name])

proc remoteInvestmentOpen*(home, target: cstring): bool =
  ## Keep a financial admission pause separate from physical route safety.
  let until = remoteStats(home)["economicDeferred"][target]
  until.isNil or until.to(int) <= game.time

proc fundedRemoteReplacement(stats, operation: JsObject, cost: int): bool =
  ## Pay an established replacement from both source and complete home receipts.
  not operation.isNil and cost > 0 and
    operation["homeEnergy"].to(int) >= operation["spawnCost"].to(int) +
      operation["infrastructureWorkEnergy"].to(int) + cost and
    stats["homeEnergy"].to(int) >= stats["spawnCost"].to(int) +
      stats["infrastructureWorkEnergy"].to(int) + cost

proc remotePauseOpen(home, target: cstring): bool =
  ## Release only a threat pause after a newer fresh physical peaceful observation.
  let stats = remoteStats(home)
  let deferred = stats["deferred"][target]
  if deferred.isNil or deferred.to(int) <= game.time: return true
  let pause = stats["threatDeferred"][target]
  if pause.isNil or pause["room"].isNil or pause["tick"].isNil: return false
  let proof = roomIntel()[pause["room"].to(cstring)]
  not proof.isNil and not proof["lastSeen"].isNil and
    proof["lastSeen"].to(int) > pause["tick"].to(int) and
    game.time - proof["lastSeen"].to(int) in 0..<IntelRefreshTicks and
    not proof["hostileCreeps"].isNil and proof["hostileCreeps"].to(int) == 0

proc safeIntel*(home, target: cstring): bool =
  ## Require fresh peaceful neutral or self-reserved intelligence and an open room.
  let
    record = roomIntel()[target]
    status = game.map.getRoomStatus(target)
  if record.isNil or record["lastSeen"].isNil or
      game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
      status.isNil or status.status == "closed".cstring or
      not remotePauseOpen(home, target) or
      not record["blockedUntil"].isNil and record["blockedUntil"].to(int) > game.time or
      not record["hasController"].to(bool) or record["hostileCreeps"].to(int) > 0:
    return false
  let control = record["controller"]
  not control.isNil and not control["my"].to(bool) and
    control["owner"].isNil and
    (control["reservedBy"].isNil or ownReservation(home, control["reservedBy"].to(cstring)))

proc remoteRouteRooms(home: cstring, target: JsObject): seq[cstring] =
  ## Preserve declared corridors while adopting old adjacent assignments.
  if target["allowedRooms"].isNil: @[home, target["room"].to(cstring)]
  else: target["allowedRooms"].to(seq[cstring])

proc remoteThreatRoom(home: cstring, target: JsObject): cstring =
  ## Retain the observed threat reason throughout a declared return corridor.
  for name in remoteRouteRooms(home, target):
    let record = roomIntel()[name]
    if not record.isNil and not record["lastSeen"].isNil and
        game.time - record["lastSeen"].to(int) in 0..<IntelRefreshTicks and
        record["hostileCreeps"].to(int) > 0:
      return name
  "".cstring

proc safeRemoteRoute(home: cstring, target: JsObject): bool =
  ## Require fresh peaceful intelligence and actual exits throughout a bounded route.
  if target.isNil or target["room"].isNil or not safeIntel(home, target["room"].to(cstring)):
    return false
  let rooms = remoteRouteRooms(home, target)
  if rooms.len notin 2..MaxTravelRooms or rooms[0] != home or rooms[^1] != target["room"].to(cstring):
    return false
  for index in 1..<rooms.len:
    let name = rooms[index]
    if name in rooms[0..<index]: return false
    let exits = game.map.describeExits(rooms[index - 1])
    if exits.isNil: return false
    var linked = false
    for direction, nextRoom in exits.pairs:
      if nextRoom == name: linked = true
    if not linked: return false
    if index == rooms.high: continue
    let
      record = roomIntel()[name]
      status = game.map.getRoomStatus(name)
    if record.isNil or record["lastSeen"].isNil or
        game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
        status.isNil or status.status == "closed".cstring or
        record["hostileCreeps"].to(int) > 0 or record["hasController"].isNil or
        not record["blockedUntil"].isNil and record["blockedUntil"].to(int) > game.time or
        not remotePauseOpen(home, name):
      return false
    if record["hasController"].to(bool):
      let controller = record["controller"]
      if controller.isNil or not controller["my"].to(bool) and
          (not controller["owner"].isNil or not controller["reservedBy"].isNil and
            not ownReservation(home, controller["reservedBy"].to(cstring))):
        return false
  true

proc remoteTarget*(spawn: StructureSpawn, allowShared = false, dedicated = false): JsObject =
  ## Prefer an unoccupied safe source before sharing a complete affordable route.
  let
    home = spawn.room.name
  var
    bestCost = high(int)
    sharedCost = high(int)
    shared: JsObject
  for nearby in nearbyRoomRoutes(home):
    let target = nearby.target
    let allowedRooms = nearby.rooms
    let routed = newJsObject()
    routed["room"] = target
    routed["allowedRooms"] = allowedRooms
    if not safeRemoteRoute(home, routed) or not remoteInvestmentOpen(home, target):
      continue
    let observed = roomIntel()[target]["sources"]
    if observed.isNil:
      continue
    for id, source in observed.pairs:
      let occupied = remoteSourceOccupied(home, id)
      if source["capacity"].to(int) <= 0 or (occupied and not allowShared) or
          game.cpu.getUsed() > float(game.cpu.limit - 5):
        continue
      let
        destination = newRoomPosition(source["x"].to(int), source["y"].to(int), target)
        options = PathFinderOptions(plainCost: 1, swampCost: 5, maxOps: 2000, maxRooms: allowedRooms.len,
          roomCallback: proc(name: cstring): JsObject =
            if name in allowedRooms: jsUndefined else: toJs(false))
        route = searchPath(spawn.pos, PathFinderGoal(pos: destination, range: 1), options)
        cycle = route.cost * 2 + RemoteDeliveryAllowance +
          (if dedicated: 0 else: remoteHarvestTime(spawn.room.energyAvailable))
      if route.incomplete or route.path.len == 0 or cycle > RemoteMaxCycle or
          (occupied and route.cost >= sharedCost) or (not occupied and route.cost >= bestCost):
        continue
      let selected = newJsObject()
      selected["room"] = target
      selected["allowedRooms"] = allowedRooms
      selected["source"] = id
      selected["x"] = destination.x
      selected["y"] = destination.y
      selected["travelEstimate"] = route.cost
      selected["cycleEstimate"] = cycle
      selected["capacity"] = source["capacity"]
      let dock = route.path[^1]
      if dock.roomName == target and max(abs(dock.x - destination.x), abs(dock.y - destination.y)) == 1:
        selected["dockX"] = dock.x
        selected["dockY"] = dock.y
      if occupied:
        sharedCost = route.cost
        shared = selected
      else:
        bestCost = route.cost
        result = selected
  if result.isNil:
    result = shared

proc miningTarget(spawn: StructureSpawn, selected: JsObject): JsObject =
  ## Resolve an extraction dock within the assignment's safe declared corridor.
  if not safeRemoteRoute(spawn.room.name, selected):
    return
  let record = roomIntel()[selected["room"].to(cstring)]["sources"][selected["source"].to(cstring)]
  if record.isNil:
    return
  result = newJsObject()
  for key, value in selected.pairs:
    result[key] = value
  result["capacity"] = record["capacity"]
  if result["dockX"].isNil or result["dockY"].isNil:
    let home = spawn.room.name
    let destination = selected["room"].to(cstring)
    let allowedRooms = remoteRouteRooms(home, selected)
    let route = searchPath(spawn.pos,
      PathFinderGoal(pos: newRoomPosition(selected["x"].to(int), selected["y"].to(int), destination), range: 1),
      PathFinderOptions(plainCost: 1, swampCost: 5, maxOps: 2000, maxRooms: allowedRooms.len,
        roomCallback: proc(name: cstring): JsObject =
          if name in allowedRooms: jsUndefined else: toJs(false)))
    if route.incomplete or route.path.len == 0 or
        route.cost * 2 + RemoteDeliveryAllowance > RemoteMaxCycle:
      return jsNull
    let dock = route.path[^1]
    if dock.roomName != destination or
        max(abs(dock.x - selected["x"].to(int)), abs(dock.y - selected["y"].to(int))) != 1:
      return jsNull
    result["dockX"] = dock.x
    result["dockY"] = dock.y
    result["travelEstimate"] = route.cost
  result["cycleEstimate"] = result["travelEstimate"].to(int) * 2 + RemoteDeliveryAllowance

proc addOperation(stats, target: JsObject) =
  ## Initialize one bounded source ledger without discarding previous room costs.
  let id = target["source"].to(cstring)
  if not stats["operations"][id].isNil:
    return
  let operation = newJsObject()
  operation["target"] = target
  operation["started"] = game.time
  operation["spawnCost"] = 0
  operation["homeEnergy"] = 0
  operation["infrastructureWorkEnergy"] = 0
  operation["loadedEnergy"] = 0
  operation["loads"] = 0
  stats["operations"][id] = operation

proc remoteContainerReady*(operation: JsObject, minimumEnergy = 0): bool =
  ## Require actual source storage with enough stock for additional transport.
  let
    target = operation["target"]
    roomName = target["room"].to(cstring)
    visible = game.rooms[roomName]
  if visible.isNil:
    return false
  let source = newRoomPosition(target["x"].to(int), target["y"].to(int), roomName)
  for structure in visible.findStructures(FIND_STRUCTURES):
    if structure.structureType == ContainerStructureType and structure.hits > 0 and
        structure.pos.roomName == roomName and structure.pos.distance(source) <= 1 and
        (minimumEnergy == 0 or structure.store.getUsedCapacity(RESOURCE_ENERGY) >= minimumEnergy):
      return true

proc operationalMiningHome(home: cstring): bool =
  ## Require an owned spawn and controller before depending on a partner colony.
  for spawn in game.spawns.items:
    if spawn.room.name == home and not spawn.room.controller.isNil and spawn.room.controller.my:
      return true

proc suppliedRemoteMiner(home: cstring, target: JsObject, replacement: int): bool =
  ## Reuse healthy funded extraction and reserve accepted births across owned homes.
  let
    source = target["source"].to(cstring)
    destination = target["room"].to(cstring)
    body = remoteMinerBody(target["capacity"].to(int))
    cost = remoteBodyCost(body)
  var requiredWork = 0
  for part in body:
    if part == "work".cstring: inc requiredWork
  for miner in game.creeps.items:
    let owner = miner.memory.homeRoom
    if owner == home or miner.memory.role != RemoteRole or miner.memory.job != RemoteMinerJob or
        not operationalMiningHome(owner) or
        miner.memory.toJs["remoteRetired"].to(bool) or miner.memory.toJs["remoteReturning"].to(bool) or
        not miner.memory.toJs["remotePathRetry"].isNil or
        miner.getActiveBodyparts("work".cstring) < requiredWork or
        miner.getActiveBodyparts("carry".cstring) == 0:
      continue
    let assigned = miner.memory.toJs["remoteTarget"]
    let stats = remoteStats(owner)
    if assigned.isNil or assigned["source"].to(cstring) != source or
        assigned["room"].to(cstring) != destination or
        stats["lifetimes"][miner.name].isNil or stats["operations"][source].isNil or
        not safeRemoteRoute(owner, assigned):
      continue
    if miner.spawning or miner.ticksToLive > replacement:
      return true
  for owner, stats in memory.toJs["worldRemotes"].pairs:
    if owner == home or not operationalMiningHome(owner) or stats["lifetimes"].isNil: continue
    for name, lifetime in stats["lifetimes"].pairs:
      let assigned = lifetime["target"]
      if lifetime["started"].to(int) == game.time and lifetime["job"].to(cstring) == RemoteMinerJob and
          lifetime["cost"].to(int) >= cost and not assigned.isNil and
          assigned["source"].to(cstring) == source and assigned["room"].to(cstring) == destination and
          safeRemoteRoute(owner, assigned):
        return true

proc suppliedRemoteCarrier(home: cstring, target: JsObject, body: seq[cstring], replacement: int): bool =
  ## Reserve surplus transport supplied by another owned home or an accepted birth.
  let
    source = target["source"].to(cstring)
    destination = target["room"].to(cstring)
    cost = remoteBodyCost(body)
  var carry = 0
  for part in body:
    if part == "carry".cstring: inc carry
  for carrier in game.creeps.items:
    let owner = carrier.memory.homeRoom
    if owner == home or carrier.memory.role != RemoteRole or carrier.memory.job != RemoteCarrierJob or
        not operationalMiningHome(owner) or carrier.memory.toJs["remoteRetired"].to(bool) or
        not carrier.memory.toJs["remotePathRetry"].isNil or
        carrier.getActiveBodyparts("carry".cstring) < carry or
        carrier.getActiveBodyparts("move".cstring) < carry:
      continue
    let assigned = carrier.memory.toJs["remoteTarget"]
    let stats = remoteStats(owner)
    if assigned.isNil or assigned["source"].to(cstring) != source or
        assigned["room"].to(cstring) != destination or
        stats["lifetimes"][carrier.name].isNil or stats["operations"][source].isNil or
        not safeRemoteRoute(owner, assigned):
      continue
    if carrier.spawning or carrier.ticksToLive > replacement:
      return true
  for owner, stats in memory.toJs["worldRemotes"].pairs:
    if not operationalMiningHome(owner) or stats["lifetimes"].isNil: continue
    for name, lifetime in stats["lifetimes"].pairs:
      let assigned = lifetime["target"]
      if lifetime["started"].to(int) == game.time and lifetime["job"].to(cstring) == RemoteCarrierJob and
          lifetime["cost"].to(int) >= cost and not assigned.isNil and
          assigned["source"].to(cstring) == source and assigned["room"].to(cstring) == destination and
          safeRemoteRoute(owner, assigned):
        return true

proc remoteCarrierDemand*(spawn: StructureSpawn, operation: JsObject): int =
  ## Maintain extra mature transport only behind long-route demand and actual paid extraction.
  let
    home = spawn.room.name
    target = operation["target"]
    control = roomIntel()[target["room"].to(cstring)]["controller"]
  if target["capacity"].to(int) > 1500 and not control["reservedBy"].isNil and
      ownReservation(home, control["reservedBy"].to(cstring)):
    return 2
  if spawn.room.controller.isNil or not spawn.room.controller.my or spawn.room.controller.level < 5 or
      target["capacity"].to(int) != 1500 or not safeRemoteRoute(home, target):
    return 1
  let body = remoteCarrierBody(spawn.room.energyCapacityAvailable)
  var payload = 0
  for part in body:
    if part == "carry".cstring: payload += RemoteCarryCapacity
  let travel = target["travelEstimate"].to(int)
  if payload <= 0 or travel <= 0 or
      (travel * 2 + RemoteDeliveryAllowance) * target["capacity"].to(int) <=
        payload * RemoteSourceRegeneration:
    return 1
  let
    replacement = travel + body.len * RemoteSpawnTicks + RemoteReplacementSlack +
      remoteLifeBudget(target, true)
    minerCost = remoteBodyCost(remoteMinerBody(target["capacity"].to(int)))
    requiredWork = (target["capacity"].to(int) + RemoteSourceRegeneration * RemoteHarvestPower - 1) div
      (RemoteSourceRegeneration * RemoteHarvestPower)
    source = newRoomPosition(target["x"].to(int), target["y"].to(int), target["room"].to(cstring))
    stats = remoteStats(home)
  var supplied = false
  var carriers = 0
  for actor in game.creeps.items:
    if actor.memory.role != RemoteRole or actor.memory.homeRoom != home or
        actor.memory.toJs["remoteRetired"].to(bool) or
        not actor.memory.toJs["remotePathRetry"].isNil:
      continue
    let assigned = actor.memory.toJs["remoteTarget"]
    let lifetime = stats["lifetimes"][actor.name]
    if assigned.isNil or assigned["source"].to(cstring) != target["source"].to(cstring) or
        assigned["room"].to(cstring) != target["room"].to(cstring) or lifetime.isNil:
      continue
    if actor.memory.job == RemoteMinerJob and not actor.spawning and
        actor.room.name == target["room"].to(cstring) and actor.pos.distance(source) == 1 and
        actor.ticksToLive > remoteLifeBudget(target, false) and lifetime["cost"].to(int) >= minerCost and
        actor.getActiveBodyparts("work".cstring) >= requiredWork and actor.getActiveBodyparts("carry".cstring) > 0 and
        not actor.memory.toJs["remoteReturning"].to(bool):
      supplied = true
    elif actor.memory.job == RemoteCarrierJob and (actor.spawning or actor.ticksToLive > 0) and
        actor.getActiveBodyparts("carry".cstring) * RemoteCarryCapacity >= payload and
        actor.getActiveBodyparts("move".cstring) * RemoteCarryCapacity >= payload:
      inc carriers
  if supplied and operation.remoteContainerReady() and
      (carriers >= 2 or operation.remoteContainerReady(payload * 2)) and
      not suppliedRemoteCarrier(home, target, body, replacement):
    return 2
  1

proc spawnMining(spawn: StructureSpawn, stats: JsObject): ReturnCode =
  ## Maintain funded extraction and transport pairs with one bounded handoff overlap.
  let home = spawn.room.name
  var active, coordinatedActors, legacy, operationCount: int
  for creep in game.creeps.items:
    if creep.memory.role == RemoteRole and creep.memory.homeRoom == home:
      if creep.memory.job in [RemoteMinerJob, RemoteCarrierJob]:
        inc coordinatedActors
        if creep.spawning or not creep.memory.toJs["remoteRetired"].to(bool) or
            creep.room.name != home or creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
          inc active
      else:
        inc legacy
  if coordinatedActors >= RemoteReservedCoordinatedLimit:
    return OK
  var discarded: seq[cstring]
  for id, operation in stats["operations"].pairs:
    if not safeRemoteRoute(home, operation["target"]) and not remoteSourceOccupied(home, id):
      discarded.add(id)
    else:
      inc operationCount
  for id in discarded:
    discard jsDelete(stats["operations"][id])
  for creep in game.creeps.items:
    if operationCount >= RemoteOperationLimit: break
    if creep.memory.role != RemoteRole or creep.memory.homeRoom != home: continue
    let selected = creep.memory.toJs["remoteTarget"]
    if selected.isNil or not stats["operations"][selected["source"].to(cstring)].isNil: continue
    let target = spawn.miningTarget(selected)
    if not target.isNil:
      stats.addOperation(target)
      inc operationCount
  var newOperationLimit = RemoteInitialOperationLimit
  for structure in spawn.room.findStructures():
    if structure.my and structure.structureType == StorageStructureType and
        structure.store.getUsedCapacity(RESOURCE_ENERGY) >= RemoteMiningReserve:
      newOperationLimit = RemoteOperationLimit
      break
  if operationCount < newOperationLimit and active + legacy == 0:
    let target = spawn.miningTarget(spawn.remoteTarget(dedicated = spawn.room.controller.level >= 5))
    if not target.isNil:
      stats.addOperation(target)
      inc operationCount
  elif operationCount < newOperationLimit:
    let target = spawn.miningTarget(spawn.remoteTarget(dedicated = spawn.room.controller.level >= 5))
    if not target.isNil and stats["operations"][target["source"].to(cstring)].isNil:
      stats.addOperation(target)
      inc operationCount
  var reserved = false
  var extraCarriers = 0
  for id, operation in stats["operations"].pairs:
    let target = spawn.miningTarget(operation["target"])
    if not target.isNil:
      operation["target"] = target
      let control = roomIntel()[target["room"].to(cstring)]["controller"]
      let own = not control["reservedBy"].isNil and ownReservation(home, control["reservedBy"].to(cstring))
      reserved = reserved or own
      let retained = if operation["carrierSlots"].isNil: 0
        else: min(1, max(0, operation["carrierSlots"].to(int) - 1))
      extraCarriers += max(spawn.remoteCarrierDemand(operation) - 1,
        retained)
  let ordinaryLimit = if operationCount >= RemoteOperationLimit: RemoteCoordinatedLimit
    else: RemoteInitialCoordinatedLimit
  let activeLimit = if reserved: min(RemoteReservedCoordinatedLimit, operationCount * 2 + extraCarriers + 1)
    elif extraCarriers > 0: min(RemoteReservedCoordinatedLimit,
      max(ordinaryLimit, operationCount * 2 + extraCarriers + 1))
    else: ordinaryLimit
  if active >= activeLimit:
    return OK
  for id, operation in stats["operations"].pairs:
    let target = operation["target"]
    if not safeRemoteRoute(home, target): continue
    for job in [RemoteMinerJob, RemoteCarrierJob]:
      if job == RemoteCarrierJob and not operation.remoteContainerReady(): continue
      let body = if job == RemoteMinerJob: remoteMinerBody(target["capacity"].to(int))
        else: remoteCarrierBody(spawn.room.energyAvailable)
      let desired = if job == RemoteCarrierJob: spawn.remoteCarrierDemand(operation) else: 1
      var count, oldest: int
      oldest = high(int)
      var oldCollectors, spawning = false
      for creep in game.creeps.items:
        if creep.memory.role != RemoteRole or creep.memory.homeRoom != home: continue
        let assigned = creep.memory.toJs["remoteTarget"]
        if assigned.isNil or assigned["source"].to(cstring) != id: continue
        if creep.memory.job == job:
          inc count
          if creep.spawning: spawning = true
          else: oldest = min(oldest, creep.ticksToLive)
        elif creep.memory.job != RemoteMinerJob and creep.memory.job != RemoteCarrierJob and
            not creep.memory.toJs["remoteHandoff"].to(bool):
          oldCollectors = true
      if job == RemoteCarrierJob and oldCollectors: continue
      let replacement = target["travelEstimate"].to(int) + body.len * RemoteSpawnTicks + RemoteReplacementSlack +
        remoteLifeBudget(target, job == RemoteCarrierJob)
      if job == RemoteMinerJob and suppliedRemoteMiner(home, target, replacement): continue
      if spawning or count > desired or count == desired and oldest > replacement: continue
      if count > 0 and count < desired and oldest > replacement:
        var funded = false
        for structure in spawn.room.findStructures():
          if structure.my and structure.structureType == StorageStructureType and
              structure.store.getUsedCapacity(RESOURCE_ENERGY) >= RemoteMiningReserve:
            funded = true
        if not funded: continue
      let cost = remoteBodyCost(body)
      if body.len == 0 or cost > spawn.room.energyAvailable: continue
      if not remoteInvestmentOpen(home, target["room"].to(cstring)) and
          (count == 0 or oldest > replacement or not fundedRemoteReplacement(stats, operation, cost)):
        continue
      let state = CreepMemory(role: RemoteRole, homeRoom: home,
        job: (if job == RemoteMinerJob: RemoteMinerJob else: RemoteCarrierJob))
      let details = state.toJs
      details["remoteTarget"] = target
      details["remoteStarted"] = game.time
      details["remoteHomeEnergy"] = 0
      let name = cstring("remote-" & $spawn.name & "-" & $game.time)
      result = spawn.spawnCreep(body, name, SpawnCreepOpts(memory: state))
      if result == OK:
        if job == RemoteCarrierJob and count > 0 and count < desired and oldest > replacement:
          operation["carrierSlots"] = desired
        stats["spawnCost"] = stats["spawnCost"].to(int) + cost
        stats["spawned"] = stats["spawned"].to(int) + 1
        stats["lastSpawn"] = game.time
        operation["spawnCost"] = operation["spawnCost"].to(int) + cost
        let lifetime = newJsObject()
        lifetime["cost"] = cost
        lifetime["homeEnergy"] = 0
        lifetime["target"] = target
        lifetime["job"] = job
        lifetime["started"] = game.time
        stats["lifetimes"][name] = lifetime
      return

proc spawnRemote*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Fund remote income after ordinary replacement and scouting needs.
  let room = spawn.room
  if game.time mod RemotePlanInterval != 0 or not spawn.spawning.isNil or
      room.controller.isNil or not room.controller.my or room.controller.level < 3 or
      room.energyCapacityAvailable < 600 or
      room.energyAvailable < room.energyCapacityAvailable or room.energyAvailable < RemoteCost or
      game.cpu.bucket < RemoteCpuReserve or workerCount(room.name) < desiredWorkers or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return OK
  for structure in room.findStructures():
    if structure.my and structure.structureType == TowerStructureType and
        structure.store.getUsedCapacity(RESOURCE_ENERGY) < RemoteTowerReserve:
      return OK
  let stats = remoteStats(room.name)
  stats.finishRemoteLifetimes()
  if room.controller.level >= ParallelRemoteLevel and room.energyCapacityAvailable >= ParallelRemoteCapacity:
    var hasStorage = false
    for structure in room.findStructures():
      if structure.my and structure.structureType == StorageStructureType:
        hasStorage = true
        if stats["coordinated"].to(bool) or structure.store.getUsedCapacity(RESOURCE_ENERGY) >= RemoteMiningReserve:
          stats["coordinated"] = true
          return spawn.spawnMining(stats)
    if not hasStorage:
      for site in room.findConstructionSites():
        if site.my and site.structureType == StorageStructureType and site.pos.roomName == room.name:
          stats["coordinated"] = true
          return spawn.spawnMining(stats)
  let limit = if room.controller.level >= ParallelRemoteLevel and
    room.energyCapacityAvailable >= ParallelRemoteCapacity: 2 else: 1
  var active = 0
  for creep in game.creeps.items:
    if creep.memory.role == RemoteRole and creep.memory.homeRoom == room.name:
      inc active
  if active >= limit:
    return OK
  let target = spawn.remoteTarget(allowShared = active == 1 and limit == 2)
  if target.isNil:
    return OK
  let
    cost = remoteCost(room.energyAvailable)
    state = CreepMemory(role: RemoteRole, homeRoom: room.name, job: HaulerJob)
    details = state.toJs
    name = cstring("remote-" & $spawn.name & "-" & $game.time)
  details["remoteTarget"] = target
  details["remoteStarted"] = game.time
  details["remoteHomeEnergy"] = 0
  result = spawn.spawnCreep(remoteBody(room.energyAvailable), name, SpawnCreepOpts(memory: state))
  if result == OK:
    stats["spawnCost"] = stats["spawnCost"].to(int) + cost
    stats["spawned"] = stats["spawned"].to(int) + 1
    stats["lastSpawn"] = game.time
    stats["target"] = target
    stats["activeName"] = name
    stats["activeCost"] = cost
    stats["activeEnergy"] = 0
    let lifetime = newJsObject()
    lifetime["cost"] = cost
    lifetime["homeEnergy"] = 0
    lifetime["target"] = target
    stats["lifetimes"][name] = lifetime

proc suspendRemote(creep: Creep, threatRoom: cstring = "") =
  ## Stop outbound work and defer the failed destination for a scouting interval.
  let
    state = creep.memory.toJs
    target = state["remoteTarget"]["room"].to(cstring)
  let stats = remoteStats(creep.memory.homeRoom)
  stats["deferred"][target] = game.time + IntelRefreshTicks
  if threatRoom.len > 0:
    let pause = newJsObject()
    pause["room"] = threatRoom
    pause["tick"] = game.time
    stats["threatDeferred"][target] = pause
  else:
    discard jsDelete(stats["threatDeferred"][target])
  state["remoteHandoff"] = false
  let lifetime = stats["lifetimes"][creep.name]
  if not lifetime.isNil: lifetime["handoff"] = false
  state["remoteReturning"] = true
  state["remoteRetired"] = true

proc settleHomeEnergy(creep: Creep) =
  ## Credit observed cargo spent at home only across one undamaged game tick.
  let state = creep.memory.toJs
  if state["remoteReceipt"].isNil:
    return
  let receipt = state["remoteReceipt"]
  if receipt["tick"].to(int) + 1 == game.time and creep.room.name == creep.memory.homeRoom and
      creep.hits >= receipt["hits"].to(int) and
      creep.store.getCapacity(RESOURCE_ENERGY) == receipt["capacity"].to(int):
    let spent = max(0, receipt["energy"].to(int) - creep.store.getUsedCapacity(RESOURCE_ENERGY))
    let stats = remoteStats(creep.memory.homeRoom)
    stats["homeEnergy"] = stats["homeEnergy"].to(int) + spent
    if creep.memory.job in [RemoteMinerJob, RemoteCarrierJob]:
      let operation = stats["operations"][state["remoteTarget"]["source"].to(cstring)]
      if not operation.isNil:
        operation["homeEnergy"] = operation["homeEnergy"].to(int) + spent
    let lifetime = stats["lifetimes"][creep.name]
    if not lifetime.isNil:
      lifetime["homeEnergy"] = lifetime["homeEnergy"].to(int) + spent
    if not stats["activeName"].isNil and stats["activeName"].to(cstring) == creep.name:
      stats["activeEnergy"] = stats["activeEnergy"].to(int) + spent
    state["remoteHomeEnergy"] = state["remoteHomeEnergy"].to(int) + spent
  discard jsDelete(state["remoteReceipt"])

proc readyRemoteMiner(creep: Creep): Creep =
  ## Find a healthy source-adjacent replacement for an accounted legacy collector.
  let
    home = creep.memory.homeRoom
    target = creep.memory.toJs["remoteTarget"]
    stats = remoteStats(home)
    destination = target["room"].to(cstring)
  if stats["lifetimes"][creep.name].isNil or
    stats["operations"][target["source"].to(cstring)].isNil or not safeRemoteRoute(home, target):
    return
  for miner in game.creeps.items:
    if miner.memory.role != RemoteRole or miner.memory.homeRoom != home or
        miner.memory.job != RemoteMinerJob or miner.spawning or miner.room.name != destination or
        miner.memory.toJs["remoteRetired"].to(bool) or miner.memory.toJs["remoteReturning"].to(bool) or
        miner.getActiveBodyparts("work".cstring) == 0 or miner.getActiveBodyparts("carry".cstring) == 0:
      continue
    let assigned = miner.memory.toJs["remoteTarget"]
    if assigned.isNil or assigned["source"].to(cstring) != target["source"].to(cstring) or
        assigned["room"].to(cstring) != destination or miner.ticksToLive <= remoteLifeBudget(assigned, false) or
        miner.pos.distance(newRoomPosition(target["x"].to(int), target["y"].to(int), destination)) != 1:
      continue
    let controller = miner.room.controller
    if controller.isNil or not controller.owner.isNil or
        (not controller.reservation.isNil and not ownReservation(home, controller.reservation.username)) or
        miner.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
      continue
    return miner

proc remoteMove(creep: Creep, destination: RoomPosition, arrival: int) =
  ## Retry a blocked destination briefly before retiring a failed operation.
  let state = creep.memory.toJs
  var retry = state["remotePathRetry"]
  let sameDestination = not retry.isNil and retry["room"].to(cstring) == destination.roomName and
    retry["x"].to(int) == destination.x and retry["y"].to(int) == destination.y and
    retry["range"].to(int) == arrival
  if sameDestination and game.time < retry["nextAttempt"].to(int):
    return
  let target = state["remoteTarget"]
  let options = if target["allowedRooms"].isNil: PathOptions(range: arrival)
    else: travelPathOptions(remoteRouteRooms(creep.memory.homeRoom, target), arrival)
  let code = creep.moveTo(destination, options)
  if code == ERR_NO_PATH:
    if not sameDestination:
      retry = newJsObject()
      retry["room"] = destination.roomName
      retry["x"] = destination.x
      retry["y"] = destination.y
      retry["range"] = arrival
      retry["started"] = game.time
      retry["attempts"] = 0
    retry["nextAttempt"] = game.time + RemotePathRetryInterval
    retry["attempts"] = retry["attempts"].to(int) + 1
    state["remotePathRetry"] = retry
    discard jsDelete(state["_move"])
    let failure = newJsObject()
    failure["tick"] = game.time
    failure["room"] = creep.room.name
    failure["x"] = creep.pos.x
    failure["y"] = creep.pos.y
    failure["destinationRoom"] = destination.roomName
    failure["destinationX"] = destination.x
    failure["destinationY"] = destination.y
    failure["code"] = ord(code)
    failure["range"] = arrival
    failure["energy"] = creep.store.getUsedCapacity(RESOURCE_ENERGY)
    failure["ticksToLive"] = creep.ticksToLive
    failure["attempts"] = retry["attempts"]
    failure["retryStarted"] = retry["started"]
    creep.memory.toJs["remoteFailure"] = failure
    remoteStats(creep.memory.homeRoom)["lastFailure"] = failure
    var replacement: Creep
    let target = state["remoteTarget"]
    if creep.memory.job notin [RemoteMinerJob, RemoteCarrierJob] and
        not state["remoteRetired"].to(bool) and not state["remoteReturning"].to(bool) and arrival == 1 and
        destination.roomName == target["room"].to(cstring) and
        destination.x == target["x"].to(int) and destination.y == target["y"].to(int):
      replacement = creep.readyRemoteMiner()
    if not replacement.isNil:
      let stats = remoteStats(creep.memory.homeRoom)
      state["remoteHandoff"] = true
      state["remoteRetired"] = true
      state["remoteReturning"] = true
      stats["lifetimes"][creep.name]["handoff"] = true
      let handoff = newJsObject()
      handoff["tick"] = game.time
      handoff["collector"] = creep.name
      handoff["miner"] = replacement.name
      handoff["source"] = target["source"]
      stats["lastHandoff"] = handoff
      discard jsDelete(state["remotePathRetry"])
    elif game.time - retry["started"].to(int) >= RemotePathRetryTicks:
      if (creep.memory.job notin [RemoteMinerJob, RemoteCarrierJob] and not state["remoteHandoff"].to(bool)) or
          not state["remoteRetired"].to(bool) or
          creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0 or destination.roomName != creep.memory.homeRoom:
        creep.suspendRemote()
      discard jsDelete(state["remotePathRetry"])
  elif code == OK:
    discard jsDelete(state["remotePathRetry"])
  elif code notin {OK, ERR_TIRED}:
    raise newException(ValueError, "Remote move returned " & $ord(code))

proc remoteOperation(creep: Creep): JsObject =
  ## Retrieve the bounded accounting record associated with this source.
  remoteStats(creep.memory.homeRoom)["operations"][creep.memory.toJs["remoteTarget"]["source"].to(cstring)]

proc settleRemoteWork(creep: Creep) =
  ## Resolve infrastructure costs conservatively when an observation is missing.
  let state = creep.memory.toJs
  let receipt = state["remoteWorkReceipt"]
  if receipt.isNil: return
  let stats = remoteStats(creep.memory.homeRoom)
  let operation = creep.remoteOperation()
  if receipt["tick"].to(int) + 1 == game.time and creep.hits >= receipt["hits"].to(int) and
      creep.store.getCapacity(RESOURCE_ENERGY) == receipt["capacity"].to(int) and
      creep.room.name == receipt["room"].to(cstring):
    let spent = max(0, receipt["energy"].to(int) - creep.store.getUsedCapacity(RESOURCE_ENERGY))
    let correction = receipt["bound"].to(int) - spent
    stats["infrastructureWorkEnergy"] = stats["infrastructureWorkEnergy"].to(int) - correction
    stats["unverifiedWorkEnergy"] = stats["unverifiedWorkEnergy"].to(int) - receipt["bound"].to(int)
    if not operation.isNil:
      operation["infrastructureWorkEnergy"] = operation["infrastructureWorkEnergy"].to(int) - correction
  discard jsDelete(state["remoteWorkReceipt"])

proc recordRemoteWork(creep: Creep, remaining, progressPerEnergy, energyPerWork: int) =
  ## Charge successful work before the actor can die or lose its next observation.
  let receipt = newJsObject()
  let bound = min(creep.store.getUsedCapacity(RESOURCE_ENERGY),
    min(creep.getActiveBodyparts("work".cstring) * energyPerWork,
      (remaining + progressPerEnergy - 1) div progressPerEnergy))
  receipt["tick"] = game.time
  receipt["room"] = creep.room.name
  receipt["energy"] = creep.store.getUsedCapacity(RESOURCE_ENERGY)
  receipt["hits"] = creep.hits
  receipt["capacity"] = creep.store.getCapacity(RESOURCE_ENERGY)
  receipt["bound"] = bound
  creep.memory.toJs["remoteWorkReceipt"] = receipt
  let stats = remoteStats(creep.memory.homeRoom)
  stats["infrastructureWorkEnergy"] = stats["infrastructureWorkEnergy"].to(int) + bound
  stats["unverifiedWorkEnergy"] = stats["unverifiedWorkEnergy"].to(int) + bound
  let operation = creep.remoteOperation()
  if not operation.isNil:
    operation["infrastructureWorkEnergy"] = operation["infrastructureWorkEnergy"].to(int) + bound

proc sourceContainer(creep: Creep): Structure =
  ## Find public source storage and retain bounded physical observations.
  let target = creep.memory.toJs["remoteTarget"]
  let source = newRoomPosition(target["x"].to(int), target["y"].to(int), creep.room.name)
  for structure in creep.room.findStructures(FIND_STRUCTURES):
    if structure.structureType == ContainerStructureType and structure.pos.distance(source) <= 1:
      result = structure
      let observation = newJsObject()
      observation["id"] = structure.id
      observation["tick"] = game.time
      observation["x"] = structure.pos.x
      observation["y"] = structure.pos.y
      observation["hits"] = structure.hits
      observation["energy"] = structure.store.getUsedCapacity(RESOURCE_ENERGY)
      let operation = creep.remoteOperation()
      if not operation.isNil:
        operation["container"] = observation
      return

proc runRemoteMiner(creep: Creep) =
  ## Buffer extraction in a maintained container without crediting it as home income.
  let state = creep.memory.toJs
  let target = state["remoteTarget"]
  let destination = target["room"].to(cstring)
  let used = creep.store.getUsedCapacity(RESOURCE_ENERGY)
  if creep.room.name == creep.memory.homeRoom and not state["remoteReturning"].to(bool) and
      (not safeRemoteRoute(creep.memory.homeRoom, target) or workerCount(creep.memory.homeRoom) < 3 or
      creep.room.controller.isNil or not creep.room.controller.my):
    creep.suspendRemote()
  if state["remoteReturning"].to(bool):
    if creep.room.name != creep.memory.homeRoom:
      creep.remoteMove(newRoomPosition(25, 25, creep.memory.homeRoom), RemoteArrivalRange)
    elif used > 0:
      let receipt = newJsObject()
      receipt["tick"] = game.time
      receipt["energy"] = used
      receipt["hits"] = creep.hits
      receipt["capacity"] = creep.store.getCapacity(RESOURCE_ENERGY)
      state["remoteReceipt"] = receipt
      creep.deliverEnergy()
    return
  if creep.room.name != destination:
    if game.time - state["remoteStarted"].to(int) >= RemoteRouteTimeout:
      creep.suspendRemote()
    else:
      creep.remoteMove(newRoomPosition(target["dockX"].to(int), target["dockY"].to(int), destination), 0)
    return
  var assigned: Source
  for source in creep.room.find(FIND_SOURCES):
    if source.id == target["source"].to(cstring): assigned = source
  if assigned.isNil:
    creep.suspendRemote()
    return
  let container = creep.sourceContainer()
  let dock = if container.isNil:
    newRoomPosition(target["dockX"].to(int), target["dockY"].to(int), destination)
    else: container.pos
  if creep.pos.distance(dock) > 0:
    for other in game.creeps.items:
      if other.name != creep.name and other.memory.role == RemoteRole and
          other.memory.job == RemoteMinerJob and other.room.name == destination and
          other.pos.distance(dock) == 0 and other.ticksToLive < creep.ticksToLive and
          not other.memory.toJs["remoteReturning"].to(bool):
        if creep.pos.distance(dock) > 1: creep.remoteMove(dock, 1)
        return
    creep.remoteMove(dock, 0)
    return
  if not container.isNil:
    if used > 0 and container.hits < min(container.hitsMax, RemoteContainerRepairHits):
      let code = creep.repair(container)
      if code == OK:
        creep.recordRemoteWork(container.hitsMax - container.hits, RemoteRepairPower, 1)
      elif code notin {ERR_NOT_ENOUGH_ENERGY, ERR_NOT_IN_RANGE}:
        raise newException(ValueError, "Remote container repair returned " & $ord(code))
      return
    if used > 0 and container.store.getFreeCapacity(RESOURCE_ENERGY) > 0:
      let code = creep.transfer(container, RESOURCE_ENERGY)
      if code notin {OK, ERR_FULL, ERR_NOT_ENOUGH_ENERGY}:
        raise newException(ValueError, "Remote container transfer returned " & $ord(code))
    if container.store.getFreeCapacity(RESOURCE_ENERGY) == 0 and
        creep.store.getFreeCapacity(RESOURCE_ENERGY) == 0:
      return
  else:
    var site: ConstructionSite
    for candidate in creep.room.findConstructionSites():
      if candidate.my and candidate.structureType == ContainerStructureType and candidate.pos.distance(dock) == 0:
        site = candidate
    if not site.isNil and used > 0:
      let code = creep.build(site)
      if code == OK:
        creep.recordRemoteWork(site.progressTotal - site.progress, 1, RemoteBuildPower)
      elif code notin {ERR_NOT_ENOUGH_ENERGY, ERR_NOT_IN_RANGE}:
        raise newException(ValueError, "Remote container build returned " & $ord(code))
      return
    if site.isNil and game.time mod RemotePlanInterval == 0:
      if dock.x notin 1..48 or dock.y notin 1..48 or dock.distance(assigned.pos) != 1 or
          creep.room.getTerrain().get(dock.x, dock.y) == TerrainWall:
        creep.suspendRemote()
        return
      for structure in creep.room.findStructures(FIND_STRUCTURES):
        if structure.pos.distance(dock) == 0 and structure.structureType notin [RoadStructureType, RampartStructureType]:
          creep.suspendRemote()
          return
      let code = creep.room.createConstructionSite(dock.x, dock.y, ContainerStructureType)
      if code == ERR_INVALID_TARGET:
        creep.suspendRemote()
        return
      if code notin {OK, ERR_FULL, ERR_INVALID_TARGET, ERR_RCL_NOT_ENOUGH}:
        raise newException(ValueError, "Remote container site returned " & $ord(code))
  if assigned.energy > 0:
    let code = creep.harvest(assigned)
    if code notin {OK, ERR_NOT_ENOUGH_ENERGY}:
      raise newException(ValueError, "Remote miner harvest returned " & $ord(code))

proc waitingPaidRemoteMiner(creep: Creep): bool =
  ## Preserve a paid producer until its bounded arrival and first output deadline.
  let waiting = creep.memory.toJs["remoteWait"]
  if waiting.isNil or waiting.to(int) > game.time or
      game.time - waiting.to(int) >= RemoteRouteTimeout:
    return false
  let home = creep.memory.homeRoom
  let target = creep.memory.toJs["remoteTarget"]
  let source = target["source"].to(cstring)
  let destination = target["room"].to(cstring)
  let stats = remoteStats(home)
  for miner in game.creeps.items:
    let producer = miner.memory.toJs
    if miner.memory.role != RemoteRole or miner.memory.homeRoom != home or
        miner.memory.job != RemoteMinerJob or producer["remoteRetired"].to(bool) or
        producer["remoteReturning"].to(bool) or not producer["remotePathRetry"].isNil or
        producer["remoteStarted"].isNil:
      continue
    let assigned = producer["remoteTarget"]
    let lifetime = stats["lifetimes"][miner.name]
    if assigned.isNil or assigned["source"].to(cstring) != source or
        assigned["room"].to(cstring) != destination or assigned["capacity"].isNil or
        assigned["capacity"].to(int) <= 0 or assigned["travelEstimate"].isNil or
        assigned["travelEstimate"].to(int) <= 0 or lifetime.isNil or lifetime["cost"].isNil or
        lifetime["job"].to(cstring) != RemoteMinerJob or lifetime["started"].isNil or
        lifetime["started"].to(int) != producer["remoteStarted"].to(int) or
        lifetime["target"].isNil or lifetime["target"]["source"].to(cstring) != source or
        lifetime["target"]["room"].to(cstring) != destination or
        lifetime["target"]["capacity"].to(int) != assigned["capacity"].to(int) or
        lifetime["target"]["travelEstimate"].to(int) != assigned["travelEstimate"].to(int) or
        not safeRemoteRoute(home, assigned) or miner.room.name notin remoteRouteRooms(home, assigned):
      continue
    let body = remoteMinerBody(assigned["capacity"].to(int))
    let started = producer["remoteStarted"].to(int)
    let allowance = min(RemoteRouteTimeout,
      body.len * RemoteSpawnTicks + assigned["travelEstimate"].to(int) + RemoteReplacementSlack)
    var requiredWork = 0
    for part in body:
      if part == "work".cstring: inc requiredWork
    if started > game.time or game.time - started >= allowance or
        lifetime["cost"].to(int) < remoteBodyCost(body) or
        miner.getActiveBodyparts("work".cstring) < requiredWork or
        miner.getActiveBodyparts("carry".cstring) < 1 or
        miner.getActiveBodyparts("move".cstring) < requiredWork:
      continue
    if miner.spawning or miner.ticksToLive > remoteLifeBudget(assigned, false):
      return true

proc loadRemoteCargo(creep: Creep, container: Structure): ReturnCode =
  ## Load public stock at the assigned source without occupying its extraction dock.
  let target = creep.memory.toJs["remoteTarget"]
  let source = newRoomPosition(target["x"].to(int), target["y"].to(int), creep.room.name)
  result = ERR_NOT_ENOUGH_ENERGY
  if not container.isNil and container.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
    result = creep.withdraw(container, RESOURCE_ENERGY)
    if result == ERR_NOT_IN_RANGE:
      creep.remoteMove(container.pos, 1)
  else:
    for drop in creep.room.findResources():
      if drop.resourceType == RESOURCE_ENERGY and drop.pos.distance(source) <= 1:
        result = creep.pickup(drop)
        if result == ERR_NOT_IN_RANGE:
          creep.remoteMove(drop.pos, 1)
        break

proc runRemoteCarrier(creep: Creep): bool =
  ## Load container or spilled source cargo without issuing harvest actions.
  let state = creep.memory.toJs
  if not state["remoteLoadReceipt"].isNil:
    let receipt = state["remoteLoadReceipt"]
    if receipt["tick"].to(int) + 1 == game.time and creep.hits >= receipt["hits"].to(int):
      let gained = max(0, creep.store.getUsedCapacity(RESOURCE_ENERGY) - receipt["energy"].to(int))
      let operation = creep.remoteOperation()
      if not operation.isNil:
        operation["loadedEnergy"] = operation["loadedEnergy"].to(int) + gained
        if gained > 0: operation["loads"] = operation["loads"].to(int) + 1
    discard jsDelete(state["remoteLoadReceipt"])
  let target = state["remoteTarget"]
  if creep.room.name == creep.memory.homeRoom or state["remoteReturning"].to(bool):
    return false
  result = true
  if creep.room.name != target["room"].to(cstring):
    if game.time - state["remoteStarted"].to(int) >= RemoteRouteTimeout:
      creep.suspendRemote()
    else:
      creep.remoteMove(newRoomPosition(target["x"].to(int), target["y"].to(int), target["room"].to(cstring)), 1)
    return
  let source = newRoomPosition(target["x"].to(int), target["y"].to(int), creep.room.name)
  let container = creep.sourceContainer()
  let code = creep.loadRemoteCargo(container)
  if code == ERR_NOT_IN_RANGE:
    return
  if code == OK:
    let receipt = newJsObject()
    receipt["tick"] = game.time
    receipt["energy"] = creep.store.getUsedCapacity(RESOURCE_ENERGY)
    receipt["hits"] = creep.hits
    state["remoteLoadReceipt"] = receipt
    discard jsDelete(state["remoteWait"])
    discard jsDelete(state["remoteRepairWait"])
  elif code == ERR_NOT_ENOUGH_ENERGY:
    if creep.pos.distance(source) > 2:
      creep.remoteMove(source, 2)
    else:
      if state["remoteWait"].isNil:
        state["remoteWait"] = game.time
      if creep.store.getUsedCapacity(RESOURCE_ENERGY) == 0 and not container.isNil:
        let previous = state["remoteRepairWait"]
        if not previous.isNil and previous["id"].to(cstring) == container.id and
            container.hits > previous["hits"].to(int) and
            container.hits < min(container.hitsMax, RemoteContainerRepairHits):
          state["remoteWait"] = game.time
        let observation = newJsObject()
        observation["id"] = container.id
        observation["hits"] = container.hits
        state["remoteRepairWait"] = observation
      else:
        discard jsDelete(state["remoteRepairWait"])
      if game.time - state["remoteWait"].to(int) >= RemoteSourceWait:
        if creep.store.getUsedCapacity(RESOURCE_ENERGY) == 0 and creep.waitingPaidRemoteMiner():
          return
        if creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0:
          state["remoteReturning"] = true
        else:
          creep.suspendRemote()
  elif code notin {ERR_FULL, ERR_INVALID_TARGET}:
    raise newException(ValueError, "Remote carrier load returned " & $ord(code))

proc reuseRetiredCollector(creep: Creep): bool =
  ## Recover local transport from safely returned paid collectors without crediting imports.
  let
    state = creep.memory.toJs
    home = creep.memory.homeRoom
    local = state["remoteLocalHaul"].to(bool)
  if not local:
    if creep.memory.job in [RemoteMinerJob, RemoteCarrierJob] or
        not state["remoteRetired"].to(bool) or creep.room.name != home or
        not operationalMiningHome(home) or creep.room.controller.isNil or not creep.room.controller.my or
        creep.store.getUsedCapacity(RESOURCE_ENERGY) != 0 or not (creep.ticksToLive >= LocalReuseLifetime) or
        creep.getActiveBodyparts("work") == 0 or creep.getActiveBodyparts("carry") == 0 or
        creep.getActiveBodyparts("move") == 0 or
        max(abs(creep.pos.x - 25), abs(creep.pos.y - 25)) > RemoteArrivalRange or
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0 or
        remoteStats(home)["lifetimes"][creep.name].isNil or
        not (remoteStats(home)["lifetimes"][creep.name]["cost"].to(int) > 0):
      return false
    state["remoteLocalHaul"] = true
    creep.memory.job = HaulerJob
    creep.memory.sourceId = "".cstring
    discard jsDelete(state["_move"])
    discard jsDelete(state["localMove"])
  if creep.room.name == home and operationalMiningHome(home) and
      not creep.room.controller.isNil and creep.room.controller.my and
      (creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0 or
      (creep.ticksToLive >= LocalReuseLoadLifetime and
      creep.room.findCreeps(FIND_HOSTILE_CREEPS).len == 0)):
    if creep.store.getUsedCapacity(RESOURCE_ENERGY) > 0 and
        (not (creep.ticksToLive >= LocalReuseLoadLifetime) or
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0):
      creep.memory.delivering = true
    creep.runWorker(canWork = false)
  true

proc runRemote*(creep: Creep) =
  ## Collect from the assigned remote source and reuse home delivery priorities.
  if creep.spawning:
    return
  let
    state = creep.memory.toJs
    home = creep.memory.homeRoom
    target = state["remoteTarget"]
  if home.isNil or home.len == 0 or target.isNil:
    return
  if state["remoteLocalHaul"].to(bool):
    discard creep.reuseRetiredCollector()
    return
  creep.settleHomeEnergy()
  if creep.memory.job in [RemoteMinerJob, RemoteCarrierJob]:
    creep.settleRemoteWork()
  if creep.reuseRetiredCollector():
    return
  let
    used = creep.store.getUsedCapacity(RESOURCE_ENERGY)
    destination = target["room"].to(cstring)
  if creep.ticksToLive < remoteLifeBudget(target, creep.room.name == home and used == 0):
    state["remoteRetired"] = true
    state["remoteReturning"] = true
  if creep.room.name == home:
    state["remoteObservedRoom"] = home
  if creep.room.name != home:
    if state["remoteObservedRoom"].isNil or state["remoteObservedRoom"].to(cstring) != creep.room.name or
        game.time mod RemotePlanInterval == 0:
      creep.room.observeRoom()
    state["remoteObservedRoom"] = creep.room.name
    let controller = creep.room.controller
    if creep.room.name notin remoteRouteRooms(home, target) or not safeRemoteRoute(home, target) or
        not controller.isNil and not controller.my and not controller.owner.isNil or
        (not controller.isNil and not controller.reservation.isNil and not ownReservation(home, controller.reservation.username)) or
        creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
      creep.suspendRemote(remoteThreatRoom(home, target))
  if creep.memory.job == RemoteMinerJob:
    creep.runRemoteMiner()
    return
  if creep.store.getFreeCapacity(RESOURCE_ENERGY) == 0:
    state["remoteReturning"] = true
  if creep.memory.job == RemoteCarrierJob and creep.runRemoteCarrier():
    return
  if creep.room.name == home and used > 0 and state["remoteReturning"].to(bool):
    let receipt = newJsObject()
    receipt["tick"] = game.time
    receipt["energy"] = used
    receipt["hits"] = creep.hits
    receipt["capacity"] = creep.store.getCapacity(RESOURCE_ENERGY)
    state["remoteReceipt"] = receipt
    creep.deliverEnergy(canWork = creep.memory.job != RemoteCarrierJob)
  elif creep.room.name == home and used == 0:
    if (state["remoteReturning"].to(bool) or state["remoteRetired"].to(bool)) and
        max(abs(creep.pos.x - 25), abs(creep.pos.y - 25)) > RemoteArrivalRange:
      creep.remoteMove(newRoomPosition(25, 25, home), RemoteArrivalRange)
    elif not state["remoteRetired"].to(bool):
      if not safeRemoteRoute(home, target) or workerCount(home) < 3 or
          creep.room.controller.isNil or not creep.room.controller.my:
        creep.suspendRemote(remoteThreatRoom(home, target))
      elif not state["remoteReturning"].to(bool) and
          game.time - state["remoteStarted"].to(int) >= RemoteRouteTimeout:
        creep.suspendRemote()
      else:
        if state["remoteReturning"].to(bool):
          state["remoteStarted"] = game.time
          discard jsDelete(state["remoteWait"])
          discard jsDelete(state["remoteRepairWait"])
        state["remoteReturning"] = false
        creep.remoteMove(newRoomPosition(target["x"].to(int), target["y"].to(int), destination), 1)
  elif state["remoteReturning"].to(bool):
    creep.remoteMove(newRoomPosition(25, 25, home), RemoteArrivalRange)
  elif game.time - state["remoteStarted"].to(int) >= RemoteRouteTimeout:
    creep.suspendRemote()
  elif creep.room.name != destination:
    creep.remoteMove(newRoomPosition(target["x"].to(int), target["y"].to(int), destination), 1)
  else:
    var assigned: Source
    for source in creep.room.find(FIND_SOURCES):
      if source.id == target["source"].to(cstring):
        assigned = source
    if assigned.isNil:
      creep.suspendRemote()
      return
    let stock = creep.loadRemoteCargo(creep.sourceContainer())
    if stock == OK:
      discard jsDelete(state["remoteWait"])
      discard jsDelete(state["remotePathRetry"])
      return
    if stock == ERR_NOT_IN_RANGE:
      return
    if stock notin {ERR_NOT_ENOUGH_ENERGY, ERR_FULL, ERR_INVALID_TARGET}:
      raise newException(ValueError, "Remote collector load returned " & $ord(stock))
    if assigned.energy == 0:
      if state["remoteWait"].isNil:
        state["remoteWait"] = game.time
      elif game.time - state["remoteWait"].to(int) >= RemoteSourceWait and
          (not (assigned.ticksToRegeneration > 0) or
          game.time - state["remoteWait"].to(int) >= RemoteSourceRegeneration):
        creep.suspendRemote()
    else:
      discard jsDelete(state["remoteWait"])
      let code = creep.harvest(assigned)
      if code == ERR_NOT_IN_RANGE:
        creep.remoteMove(assigned.pos, 1)
      elif code notin {OK, ERR_NOT_ENOUGH_ENERGY}:
        raise newException(ValueError, "Remote harvest returned " & $ord(code))
