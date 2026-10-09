import
  std/jsffi,
  screeps_lib,
  ./[worldWorkers, worldScouting, worldMovement]

const
  ClaimerRole* = "claimer".cstring
  ColonistRole* = "colonist".cstring
  ExpansionInterval = 20
  ClaimCost = 650
  ExpansionCpuReserve = 3000
  ExpansionTowerReserve = 500
  MaxClaimTravel = 160
  SettlerTravelTimeout = 300
  ClaimOperationTimeout = 900
  SettlerPathRetryTicks = 30
  SupportWorkers = 3
  EstablishedWorkers = 6

proc expansionState*(): JsObject =
  ## Retain one pending colony and compact operational evidence across reloads.
  let root = memory.toJs
  if root["worldExpansion"].isNil:
    root["worldExpansion"] = newJsObject()
    root["worldExpansion"]["phase"] = "waiting".cstring
  root["worldExpansion"]

proc ownedRoomCount*(): int =
  ## Count visible owned controllers, including colonies without a spawn.
  for room in game.rooms.items:
    if not room.controller.isNil and room.controller.my:
      inc result

proc hasRoomSpawn*(name: cstring): bool =
  ## Check actual owned spawns rather than assuming construction has finished.
  for spawn in game.spawns.items:
    if spawn.room.name == name:
      return true

proc canFundExpansion(spawn: StructureSpawn, desiredWorkers: int): bool =
  ## Preserve home replacement, fuel and defense before sending settlers.
  let room = spawn.room
  if not spawn.spawning.isNil or room.controller.isNil or not room.controller.my or
      room.controller.level < 3 or room.energyAvailable < room.energyCapacityAvailable or
      room.energyAvailable < ClaimCost or game.cpu.bucket < ExpansionCpuReserve or
      workerCount(room.name) < desiredWorkers or room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return false
  for structure in room.findStructures():
    if structure.my and structure.structureType == TowerStructureType and
        structure.store.getUsedCapacity(RESOURCE_ENERGY) < ExpansionTowerReserve:
      return false
  true

proc expansionTarget*(spawn: StructureSpawn): JsObject =
  ## Prefer fresh peaceful destinations with more sources and a complete safe route.
  var bestScore = low(int)
  for nearby in nearbyRoomRoutes(spawn.room.name):
    let name = nearby.target
    let
      record = roomIntel()[name]
      status = game.map.getRoomStatus(name)
    if record.isNil or record["lastSeen"].isNil or
        game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
        not record["blockedUntil"].isNil and record["blockedUntil"].to(int) > game.time or
        status.isNil or status.status == "closed".cstring or
        not record["hasController"].to(bool) or record["hostileCreeps"].to(int) > 0:
      continue
    let control = record["controller"]
    if control.isNil or control["my"].to(bool) or
        not control["owner"].isNil or (not control["reservedBy"].isNil and
          not ownReservation(spawn.room.name, control["reservedBy"].to(cstring))):
      continue
    var sourceCount = 0
    if not record["sources"].isNil:
      for id, source in record["sources"].pairs:
        if source["capacity"].to(int) > 0: inc sourceCount
    if sourceCount == 0 or game.cpu.getUsed() > float(game.cpu.limit - 5):
      continue
    let
      home = spawn.room.name
      allowedRooms = nearby.rooms
      destination = newRoomPosition(control["x"].to(int), control["y"].to(int), name)
      route = searchPath(spawn.pos, PathFinderGoal(pos: destination, range: 1),
        PathFinderOptions(plainCost: 1, swampCost: 5, maxOps: 2000, maxRooms: nearby.rooms.len,
          roomCallback: proc(roomName: cstring): JsObject =
            if roomName in allowedRooms: jsUndefined else: toJs(false)))
      score = min(sourceCount, 2) * MaxClaimTravel - route.cost
    if route.incomplete or route.path.len == 0 or route.cost > MaxClaimTravel or score <= bestScore:
      continue
    bestScore = score
    result = newJsObject()
    result["home"] = home
    result["room"] = name
    result["x"] = destination.x
    result["y"] = destination.y
    result["sources"] = sourceCount
    result["travelEstimate"] = route.cost
    result["allowedRooms"] = toJs(nearby.rooms)

proc deferExpansion(reason: cstring) =
  ## Back off a failed operation while retaining the reason for inspection.
  let state = expansionState()
  state["phase"] = "deferred".cstring
  state["reason"] = reason
  state["failedTick"] = game.time
  let name = state["room"].to(cstring)
  if not name.isNil and name.len > 0 and not roomIntel()[name].isNil:
    roomIntel()[name]["blockedUntil"] = game.time + IntelRefreshTicks

proc planExpansion*(desiredWorkers: int) =
  ## Advance one supported colony before selecting another available GCL slot.
  if game.time mod ExpansionInterval != 0:
    return
  let state = expansionState()
  if state["phase"].to(cstring) in ["claiming".cstring, "bootstrap".cstring]:
    let target = game.rooms[state["room"].to(cstring)]
    if not target.isNil:
      target.observeRoom()
      if target.findCreeps(FIND_HOSTILE_CREEPS).len > 0 or
          target.controller.isNil or not target.controller.owner.isNil and not target.controller.my or
          (not target.controller.reservation.isNil and
            not ownReservation(state["home"].to(cstring), target.controller.reservation.username)):
        deferExpansion("target unsafe".cstring)
      elif target.controller.my:
        state["phase"] = "bootstrap".cstring
        if hasRoomSpawn(target.name) and residentWorkerCount(target.name) >= EstablishedWorkers and
            target.controller.level >= 2 and target.energyAvailable >= WorkerBodyCost:
          state["phase"] = "established".cstring
          state["completedTick"] = game.time
      elif state["phase"].to(cstring) == "bootstrap".cstring:
        deferExpansion("ownership lost".cstring)
    if state["phase"].to(cstring) == "claiming".cstring and
        game.time - state["started"].to(int) > ClaimOperationTimeout:
      deferExpansion("claim operation timeout".cstring)
    return
  for creep in game.creeps.items:
    if creep.memory.role in [ClaimerRole, ColonistRole] and
        not creep.memory.toJs["settlerDone"].to(bool):
      return
  for spawn in game.spawns.items:
    if not canFundExpansion(spawn, desiredWorkers):
      continue
    let exits = game.map.describeExits(spawn.room.name)
    if not exits.isNil:
      for direction, name in exits.pairs:
        let target = game.rooms[name]
        let intel = roomIntel()[name]
        if not target.isNil and not target.controller.isNil and target.controller.my and
            not hasRoomSpawn(name) and target.findCreeps(FIND_HOSTILE_CREEPS).len == 0 and
            (intel.isNil or intel["blockedUntil"].isNil or intel["blockedUntil"].to(int) <= game.time):
          state["home"] = spawn.room.name
          state["room"] = name
          state["allowedRooms"] = toJs(@[spawn.room.name, name])
          state["phase"] = "bootstrap".cstring
          state["started"] = game.time
          return
    for nearby in nearbyRoomRoutes(spawn.room.name):
      if nearby.rooms.len <= 2:
        continue
      let
        name = nearby.target
        target = game.rooms[name]
        intel = roomIntel()[name]
      if target.isNil or target.controller.isNil or not target.controller.my or
          hasRoomSpawn(name) or target.findCreeps(FIND_HOSTILE_CREEPS).len > 0 or
          (not intel.isNil and not intel["blockedUntil"].isNil and
            intel["blockedUntil"].to(int) > game.time) or
          game.cpu.getUsed() > float(game.cpu.limit - 5):
        continue
      let
        allowedRooms = nearby.rooms
        destination = target.controller.pos
        route = searchPath(spawn.pos, PathFinderGoal(pos: destination, range: 1),
          PathFinderOptions(plainCost: 1, swampCost: 5, maxOps: 2000,
            maxRooms: allowedRooms.len,
            roomCallback: proc(roomName: cstring): JsObject =
              if roomName in allowedRooms: jsUndefined else: toJs(false)))
      if route.incomplete or route.path.len == 0 or route.cost > MaxClaimTravel:
        continue
      state["home"] = spawn.room.name
      state["room"] = name
      state["x"] = destination.x
      state["y"] = destination.y
      state["travelEstimate"] = route.cost
      state["allowedRooms"] = toJs(allowedRooms)
      state["phase"] = "bootstrap".cstring
      state["started"] = game.time
      state["reason"] = "".cstring
      return
    if game.gcl.isNil or ownedRoomCount() >= game.gcl.level:
      continue
    let status = game.map.getRoomStatus(spawn.room.name)
    if not status.isNil and status.status == "novice".cstring and ownedRoomCount() >= 3:
      continue
    let target = spawn.expansionTarget()
    if not target.isNil:
      for key, value in target.pairs: state[key] = value
      state["phase"] = "claiming".cstring
      state["started"] = game.time
      state["reason"] = "".cstring
      return

proc bootstrapWorkerCount(roomName: cstring): int =
  ## Count spawnless colony workers with the incoming settler travel lead.
  if hasRoomSpawn(roomName):
    return workerCount(roomName)
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == roomName and
        (creep.spawning or creep.ticksToLive >= SettlerTravelTimeout):
      inc result

proc spawnExpansion*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Fund a single claimer or a bounded bootstrap workforce after home needs.
  let state = expansionState()
  if game.time mod ExpansionInterval != 0 or state["home"].to(cstring) != spawn.room.name or
      not canFundExpansion(spawn, desiredWorkers):
    return OK
  let target = state["room"].to(cstring)
  if target.isNil or target.len == 0:
    return OK
  let route = if state["allowedRooms"].isNil: @[spawn.room.name, target]
    else: state["allowedRooms"].to(seq[cstring])
  if route.len == 0 or route[^1] != target or
      not peacefulRoomRoute(spawn.room.name, route):
    return OK
  var role: cstring
  var body: seq[cstring]
  if state["phase"].to(cstring) == "claiming".cstring:
    if game.gcl.isNil or ownedRoomCount() >= game.gcl.level:
      return OK
    for creep in game.creeps.items:
      if creep.memory.role == ClaimerRole and not creep.memory.toJs["settlerDone"].to(bool):
        return OK
    role = ClaimerRole
    body = @["claim".cstring, "move".cstring]
  elif state["phase"].to(cstring) == "bootstrap".cstring:
    let room = game.rooms[target]
    if room.isNil or room.controller.isNil or not room.controller.my or
        room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
      return OK
    var support = bootstrapWorkerCount(target)
    for creep in game.creeps.items:
      if creep.memory.role == ColonistRole and creep.memory.homeRoom == target and
          not creep.memory.toJs["settlerReturning"].to(bool) and
          (creep.spawning or creep.ticksToLive > SettlerTravelTimeout):
        inc support
    if support >= SupportWorkers:
      return OK
    role = ColonistRole
    body = workerBody(spawn.room.energyAvailable)
  else:
    return OK
  let
    name = cstring($role & "-" & $spawn.name & "-" & $game.time)
    details = CreepMemory(role: role, homeRoom: (if role == ClaimerRole: spawn.room.name else: target), job: GeneralJob)
  details.toJs["settlerOrigin"] = spawn.room.name
  details.toJs["settlerRoom"] = target
  details.toJs["settlerStarted"] = game.time
  details.toJs["settlerX"] = state["x"]
  details.toJs["settlerY"] = state["y"]
  if not state["allowedRooms"].isNil:
    details.toJs["settlerRoute"] = state["allowedRooms"]
  result = spawn.spawnCreep(body, name, SpawnCreepOpts(memory: details))
  if result == OK:
    state["lastSpawn"] = game.time
    state["lastSpawnRole"] = role

proc moveSettler(creep: Creep, destination: RoomPosition, arrival: int) =
  ## Bound failed journeys and return available workers to their origin.
  let details = creep.memory.toJs
  if not details["settlerReturning"].to(bool) and
      game.time - details["settlerStarted"].to(int) > SettlerTravelTimeout:
    details["settlerReturning"] = true
    if creep.memory.role == ClaimerRole:
      deferExpansion("claim travel timeout".cstring)
    return
  if not details["settlerReturning"].to(bool) and
      creep.room.name == details["settlerOrigin"].to(cstring):
    let target = details["settlerRoom"].to(cstring)
    let route = if details["settlerRoute"].isNil:
        @[creep.room.name, target]
      else: details["settlerRoute"].to(seq[cstring])
    if route.len == 0 or route[^1] != target or
        not peacefulRoomRoute(creep.room.name, route):
      return
  let options = if details["settlerRoute"].isNil:
      PathOptions(range: arrival)
    else: travelPathOptions(details["settlerRoute"].to(seq[cstring]), arrival)
  let code = creep.moveTo(destination, options)
  if code == ERR_NO_PATH:
    if details["settlerPathFailed"].isNil:
      details["settlerPathFailed"] = game.time
    elif game.time - details["settlerPathFailed"].to(int) >= SettlerPathRetryTicks:
      details["settlerReturning"] = true
      if creep.memory.role == ClaimerRole:
        deferExpansion("claim path unavailable".cstring)
  elif code == OK:
    discard jsDelete(details["settlerPathFailed"])
  elif code != ERR_TIRED:
    raise newException(ValueError, "Settler move returned " & $ord(code))

proc runSettler*(creep: Creep) =
  ## Claim under actual GCL, then adopt arrivals into ordinary reusable worker logic.
  let details = creep.memory.toJs
  if creep.spawning or details["settlerDone"].to(bool):
    return
  let
    state = expansionState()
    target = details["settlerRoom"].to(cstring)
    origin = details["settlerOrigin"].to(cstring)
  if target.isNil or origin.isNil or target.len == 0 or origin.len == 0:
    return
  if state["room"].to(cstring) != target or state["phase"].to(cstring) == "deferred".cstring:
    details["settlerReturning"] = true
  if details["settlerReturning"].to(bool):
    if creep.room.name == origin:
      if creep.memory.role == ColonistRole:
        creep.memory.role = WorkerRole
        creep.memory.homeRoom = origin
        creep.runWorker()
      else:
        details["settlerDone"] = true
    else:
      creep.moveSettler(newRoomPosition(25, 25, origin), 20)
    return
  if creep.room.name != origin and creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    details["settlerReturning"] = true
    deferExpansion("settler encountered hostiles".cstring)
    return
  if creep.room.name != target:
    let destination = if creep.memory.role == ClaimerRole:
        newRoomPosition(details["settlerX"].to(int), details["settlerY"].to(int), target)
      else: newRoomPosition(25, 25, target)
    creep.moveSettler(destination, if creep.memory.role == ClaimerRole: 1 else: 20)
    return
  creep.room.observeRoom()
  let controller = creep.room.controller
  if controller.isNil or not controller.owner.isNil and not controller.my or
      (not controller.reservation.isNil and not ownReservation(creep.memory.homeRoom, controller.reservation.username)):
    details["settlerReturning"] = true
    deferExpansion("target occupied".cstring)
  elif controller.my:
    state["phase"] = "bootstrap".cstring
    if creep.memory.role == ColonistRole:
      creep.memory.role = WorkerRole
      creep.memory.homeRoom = target
      creep.runWorker()
    else:
      details["settlerDone"] = true
  elif creep.memory.role == ClaimerRole:
    if game.gcl.isNil or ownedRoomCount() >= game.gcl.level:
      details["settlerReturning"] = true
      deferExpansion("GCL unavailable".cstring)
      return
    let code = creep.claimController(controller)
    if code == ERR_NOT_IN_RANGE:
      creep.moveSettler(controller.pos, 1)
    elif code in {ERR_GCL_NOT_ENOUGH, ERR_FULL, ERR_ACCESS_DENIED, ERR_INVALID_TARGET}:
      details["settlerReturning"] = true
      deferExpansion(cstring("claim returned " & $ord(code)))
    elif code != OK:
      raise newException(ValueError, "Claim returned " & $ord(code))
  else:
    details["settlerReturning"] = true
