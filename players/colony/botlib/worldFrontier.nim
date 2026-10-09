import
  std/jsffi,
  screeps_lib,
  ./[worldWorkers, worldInfrastructure, worldScouting, worldRemotes,
    worldMovement, worldThreats]

const
  FrontierRole* = "frontier".cstring
  FrontierCost* = 780
  FrontierArmoredCost* = 900
  FrontierReserve = 2000
  FrontierTowerReserve = 500
  FrontierPlanInterval = 20
  FrontierMissionTicks = 600
  FrontierArrivalTicks = 250
  FrontierMinimumEnemyLife = 250
  FrontierRetreatHits = 600
  FrontierCpuReserve = 2000
  FrontierParkingInset = 5
  FrontierEntryRange = 23

proc frontierBody*(armored = false): seq[cstring] =
  ## Match declared NPC strength with funded melee parts and full plains movement.
  if armored:
    for part in 0..<2: result.add("tough".cstring)
  for part in 0..<6: result.add("attack".cstring)
  for part in 0..<(if armored: 8 else: 6): result.add("move".cstring)

proc frontierStats*(home: cstring): JsObject =
  ## Charge accepted responder births separately from mining body receipts.
  let root = memory.toJs
  if root["worldFrontier"].isNil: root["worldFrontier"] = newJsObject()
  if root["worldFrontier"][home].isNil:
    let record = newJsObject()
    record["spawnCost"] = 0
    record["missions"] = 0
    record["retryAfter"] = newJsObject()
    root["worldFrontier"][home] = record
  root["worldFrontier"][home]

proc neutralFrontier(home: cstring, record: JsObject): bool =
  ## Respect controller ownership and reservation independently of an NPC's identity.
  if record.isNil or not record["hasController"].to(bool): return false
  let control = record["controller"]
  not control.isNil and not control["my"].to(bool) and control["owner"].isNil and
    (control["reservedBy"].isNil or ownReservation(home, control["reservedBy"].to(cstring)))

proc knownMiningRoom(home, destination: cstring): bool =
  ## Restrict defensive investment to destinations in the home's mining records.
  let stats = remoteStats(home)
  if not stats["deferred"][destination].isNil: return true
  for source, operation in stats["operations"].pairs:
    let target = operation["target"]
    if target["room"].to(cstring) == destination or
        not target["allowedRooms"].isNil and destination in target["allowedRooms"].to(seq[cstring]):
      return true
  for name, lifetime in stats["lifetimes"].pairs:
    let target = lifetime["target"]
    if target["room"].to(cstring) == destination or
        not target["allowedRooms"].isNil and destination in target["allowedRooms"].to(seq[cstring]):
      return true

proc spawnFrontier*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Fund one bounded nearby NPC response after core replacement and home defense.
  let room = spawn.room
  if game.time mod FrontierPlanInterval != 0 or not spawn.spawning.isNil or
      room.controller.isNil or not room.controller.my or room.controller.level < 4 or
      room.energyAvailable < room.energyCapacityAvailable or room.energyAvailable < FrontierCost or
      workerCount(room.name) < desiredWorkers or game.cpu.bucket < FrontierCpuReserve or
      room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return OK
  var bank, towers: int
  for building in room.findStructures():
    if building.my and building.structureType == StorageStructureType:
      bank += building.store.getUsedCapacity(RESOURCE_ENERGY)
    elif building.my and building.structureType == TowerStructureType:
      inc towers
      if building.store.getUsedCapacity(RESOURCE_ENERGY) < FrontierTowerReserve: return OK
  if bank < FrontierReserve or towers == 0: return OK
  let stats = frontierStats(room.name)
  let mining = remoteStats(room.name)
  if mining["homeEnergy"].to(int) - mining["spawnCost"].to(int) -
      mining["infrastructureWorkEnergy"].to(int) - stats["spawnCost"].to(int) < FrontierCost:
    return OK
  for defender in game.creeps.items:
    if defender.memory.role == FrontierRole and defender.memory.homeRoom == room.name:
      return OK
  for route in nearbyRoomRoutes(room.name):
    if route.rooms.len != 2 or not knownMiningRoom(room.name, route.target): continue
    let record = roomIntel()[route.target]
    if not neutralFrontier(room.name, record) or record["lastSeen"].isNil or
        game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
        record["smallInvader"].isNil or
        record["smallInvader"]["expires"].to(int) - game.time < FrontierMinimumEnemyLife or
        stats["retryAfter"][route.target].to(int) > game.time:
      continue
    var assigned = false
    for otherHome, other in memory.toJs["worldFrontier"].pairs:
      if other["lastSpawn"].to(int) == game.time and other["target"].to(cstring) == route.target:
        assigned = true
    for defender in game.creeps.items:
      if defender.memory.role == FrontierRole and
          defender.memory.toJs["frontierRoom"].to(cstring) == route.target:
        assigned = true
    if assigned: continue
    let armored = record["smallInvader"]["armoredResponse"].to(bool)
    let cost = if armored: FrontierArmoredCost else: FrontierCost
    if room.energyAvailable < cost or mining["homeEnergy"].to(int) -
        mining["spawnCost"].to(int) - mining["infrastructureWorkEnergy"].to(int) -
        stats["spawnCost"].to(int) < cost:
      continue
    let state = CreepMemory(role: FrontierRole, homeRoom: room.name)
    state.toJs["frontierArmored"] = armored
    state.toJs["frontierRoom"] = route.target
    state.toJs["frontierStarted"] = game.time
    state.toJs["frontierX"] = record["smallInvader"]["x"]
    state.toJs["frontierY"] = record["smallInvader"]["y"]
    let name = cstring("frontier-" & $spawn.name & "-" & $game.time)
    result = spawn.spawnCreep(frontierBody(armored), name, SpawnCreepOpts(memory: state))
    if result == OK:
      stats["spawnCost"] = stats["spawnCost"].to(int) + cost
      stats["missions"] = stats["missions"].to(int) + 1
      stats["lastSpawn"] = game.time
      stats["target"] = route.target
      stats["retryAfter"][route.target] = game.time + IntelRefreshTicks
    return
  result = OK

proc reopenFrontier(home, cleared: cstring) =
  ## Release mining backoffs only across currently peaceful known corridors.
  let stats = remoteStats(home)
  for route in nearbyRoomRoutes(home):
    if cleared notin route.rooms or stats["deferred"][route.target].isNil: continue
    var peaceful = true
    for name in route.rooms[1..^1]:
      let record = roomIntel()[name]
      if not neutralFrontier(home, record) or record["lastSeen"].isNil or
          game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
          record["hostileCreeps"].to(int) != 0:
        peaceful = false
    if peaceful: discard jsDelete(stats["deferred"][route.target])

proc runFrontier*(defender: Creep) =
  ## Clear a declared NPC locally, then return on completion, danger or bounded timeout.
  if defender.spawning: return
  let
    state = defender.memory.toJs
    home = defender.memory.homeRoom
    target = state["frontierRoom"].to(cstring)
    elapsed = game.time - state["frontierStarted"].to(int)
  if target.isNil or target.len == 0: return
  if defender.hits < FrontierRetreatHits or defender.getActiveBodyparts("attack") < 3 or
      elapsed >= FrontierMissionTicks or defender.ticksToLive < FrontierArrivalTicks:
    state["frontierReturning"] = true
  if not state["frontierReturning"].to(bool) and defender.room.name == target:
    defender.room.observeRoom()
    let enemies = defender.room.findCreeps(FIND_HOSTILE_CREEPS)
    if enemies.len == 0 and neutralFrontier(home, roomIntel()[target]):
      reopenFrontier(home, target)
      frontierStats(home)["lastClear"] = game.time
      state["frontierReturning"] = true
    else:
      let enemy = defender.room.smallInvader()
      if enemy.isNil or not neutralFrontier(home, roomIntel()[target]) or
          enemy.boostedSmallInvader() and not state["frontierArmored"].to(bool):
        state["frontierReturning"] = true
      else:
        let attackCode = defender.attack(enemy)
        if attackCode notin {OK, ERR_NOT_IN_RANGE, ERR_TIRED}:
          raise newException(ValueError, "Frontier attack returned " & $ord(attackCode))
        let onExit = defender.pos.x in [0, 49] or defender.pos.y in [0, 49]
        let inAttackRange = defender.pos.distance(enemy.pos) <= 1
        if onExit or not inAttackRange:
          let code = if onExit and inAttackRange:
              defender.moveLocal(newRoomPosition(25, 25, target), FrontierEntryRange)
            else:
              defender.moveLocal(enemy.pos)
          if code == ERR_NO_PATH: state["frontierReturning"] = true
          elif code notin {OK, ERR_TIRED}:
            raise newException(ValueError, "Frontier approach returned " & $ord(code))
        return
  if elapsed >= FrontierArrivalTicks and defender.room.name != target:
    state["frontierReturning"] = true
  let returning = state["frontierReturning"].to(bool)
  if returning and defender.room.name == home and
      defender.pos.x in FrontierParkingInset..49 - FrontierParkingInset and
      defender.pos.y in FrontierParkingInset..49 - FrontierParkingInset:
    return
  let destination = if returning: home else: target
  let goal = if returning: newRoomPosition(25, 25, home)
    else: newRoomPosition(state["frontierX"].to(int), state["frontierY"].to(int), target)
  let code = defender.moveTo(goal, travelPathOptions(@[home, target], 1))
  if code == ERR_NO_PATH: state["frontierReturning"] = true
  elif code notin {OK, ERR_TIRED}:
    raise newException(ValueError, "Frontier travel returned " & $ord(code))
