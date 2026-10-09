import
  std/jsffi,
  screeps_lib,
  ./[worldWorkers, worldScouting, worldRemotes, worldMovement]

const
  ReserverRole* = "reserver".cstring
  ReservationCost* = 1300
  ReservationBank = 5000
  ReservationInterval = 20
  ReservationCpuReserve = 2000
  ReservationTowerReserve = 500
  ReservationMaxTravel = 120
  ReservationTravelTimeout = 300
  ReservationSpawnTicks = 12
  ReservationSlack = 50
  ReservationActorLimit = 2
  ReservationMinimumResidents = 6

proc reservationStats*(home: cstring): JsObject =
  ## Retain reservation costs and target history without mixing carrier lifetimes.
  let root = memory.toJs
  if root["worldReservations"].isNil: root["worldReservations"] = newJsObject()
  if root["worldReservations"][home].isNil:
    let state = newJsObject()
    state["spawnCost"] = 0
    state["spawned"] = 0
    state["rooms"] = newJsObject()
    root["worldReservations"][home] = state
  root["worldReservations"][home]

proc reservationBody*(): seq[cstring] =
  ## Build a fully mobile reserver that accumulates time between replacement trips.
  @["claim".cstring, "claim".cstring, "move".cstring, "move".cstring]

proc fundedReservationRoom(spawn: StructureSpawn, name: cstring): bool =
  ## Require two physically supplied source operations with receipts above setup spending.
  let home = spawn.room.name
  if not safeIntel(home, name) or not remoteInvestmentOpen(home, name): return false
  let record = roomIntel()[name]
  if record["sources"].isNil or game.rooms[name].isNil: return false
  var sources, supplied, receipts, costs: int
  for id, source in record["sources"].pairs:
    if source["capacity"].to(int) > 0: inc sources
  for id, operation in remoteStats(home)["operations"].pairs:
    if operation["target"]["room"].to(cstring) == name:
      if not operation.remoteContainerReady(): return false
      inc supplied
      receipts += operation["homeEnergy"].to(int)
      costs += operation["spawnCost"].to(int) + operation["infrastructureWorkEnergy"].to(int)
  let previous = reservationStats(home)["rooms"][name]
  if not previous.isNil: costs += previous["spawnCost"].to(int)
  sources == 2 and supplied == 2 and receipts > costs

proc reservationTarget*(spawn: StructureSpawn): JsObject =
  ## Select one funded adjacent room through a complete bounded controller route.
  let exits = game.map.describeExits(spawn.room.name)
  if exits.isNil: return
  let state = reservationStats(spawn.room.name)
  if not state["target"].isNil:
    let name = state["target"]["room"].to(cstring)
    if spawn.fundedReservationRoom(name): return state["target"]
    for creep in game.creeps.items:
      if creep.memory.role == ReserverRole and creep.memory.homeRoom == spawn.room.name and
          not creep.memory.toJs["reservationReturning"].to(bool):
        return
    discard jsDelete(state["target"])
  for direction, name in exits.pairs:
    if not spawn.fundedReservationRoom(name) or game.cpu.getUsed() > float(game.cpu.limit - 5): continue
    let control = roomIntel()[name]["controller"]
    let route = searchPath(spawn.pos,
      PathFinderGoal(pos: newRoomPosition(control["x"].to(int), control["y"].to(int), name), range: 1),
      PathFinderOptions(plainCost: 1, swampCost: 5, maxOps: 2000, maxRooms: 2,
        roomCallback: proc(room: cstring): JsObject =
          if room in [spawn.room.name, name]: jsUndefined else: toJs(false)))
    if route.incomplete or route.path.len == 0 or route.cost > ReservationMaxTravel: continue
    let target = newJsObject()
    target["room"] = name
    target["x"] = control["x"]
    target["y"] = control["y"]
    target["travelEstimate"] = route.cost
    return target

proc spawnReservation*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Spend spare reserves after the local workforce and existing mining needs are funded.
  let home = spawn.room.name
  if game.time mod ReservationInterval != 0 or not spawn.spawning.isNil or
      spawn.room.controller.isNil or not spawn.room.controller.my or spawn.room.controller.level < 4 or
      spawn.room.controller.owner.isNil or spawn.room.controller.owner.username.isNil or
      spawn.room.controller.owner.username.len == 0 or
      spawn.room.energyAvailable < spawn.room.energyCapacityAvailable or
      spawn.room.energyCapacityAvailable < ReservationCost or
      workerCount(home) < desiredWorkers or residentWorkerCount(home) < ReservationMinimumResidents or
      game.cpu.bucket < ReservationCpuReserve or
      spawn.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
    return OK
  let income = remoteStats(home)
  if not income["lastSpawn"].isNil and income["lastSpawn"].to(int) == game.time: return OK
  var bank = 0
  for structure in spawn.room.findStructures():
    if structure.my and structure.structureType == TowerStructureType and
        structure.store.getUsedCapacity(RESOURCE_ENERGY) < ReservationTowerReserve: return OK
    if structure.my and structure.structureType == StorageStructureType:
      bank += structure.store.getUsedCapacity(RESOURCE_ENERGY)
  if bank < ReservationBank: return OK
  let target = spawn.reservationTarget()
  if target.isNil: return OK
  var actors, productive: int
  for creep in game.creeps.items:
    if creep.memory.role != ReserverRole or creep.memory.homeRoom != home: continue
    inc actors
    if creep.spawning: return OK
    if not creep.memory.toJs["reservationReturning"].to(bool) and
        creep.ticksToLive > target["travelEstimate"].to(int) + ReservationSpawnTicks + ReservationSlack:
      inc productive
  if actors >= ReservationActorLimit or productive > 0: return OK
  let control = roomIntel()[target["room"].to(cstring)]["controller"]
  if not control["reservationTicks"].isNil and control["reservationTicks"].to(int) >
      target["travelEstimate"].to(int) + ReservationSpawnTicks + ReservationSlack:
    return OK
  let state = CreepMemory(role: ReserverRole, homeRoom: home)
  state.toJs["reservationTarget"] = target
  state.toJs["reservationStarted"] = game.time
  let name = cstring("reserver-" & $spawn.name & "-" & $game.time)
  result = spawn.spawnCreep(reservationBody(), name, SpawnCreepOpts(memory: state))
  if result == OK:
    let stats = reservationStats(home)
    let room = target["room"].to(cstring)
    if stats["rooms"][room].isNil:
      stats["rooms"][room] = newJsObject()
      stats["rooms"][room]["spawnCost"] = 0
    stats["target"] = target
    stats["spawnCost"] = stats["spawnCost"].to(int) + ReservationCost
    stats["rooms"][room]["spawnCost"] = stats["rooms"][room]["spawnCost"].to(int) + ReservationCost
    stats["spawned"] = stats["spawned"].to(int) + 1
    stats["lastSpawn"] = game.time
    income["spawnCost"] = income["spawnCost"].to(int) + ReservationCost
    if income["reservationSpawnCost"].isNil: income["reservationSpawnCost"] = 0
    income["reservationSpawnCost"] = income["reservationSpawnCost"].to(int) + ReservationCost
    income["lastSpawn"] = game.time

proc runReserver*(creep: Creep) =
  ## Extend only safe neutral or self-reserved control and retreat from danger or failed travel.
  if creep.spawning: return
  let
    state = creep.memory.toJs
    home = creep.memory.homeRoom
    target = state["reservationTarget"]
  if home.isNil or target.isNil: return
  let destination = target["room"].to(cstring)
  if creep.room.name != home:
    if not safeIntel(home, destination) or creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0 or
        creep.ticksToLive < target["travelEstimate"].to(int) + ReservationSlack:
      state["reservationReturning"] = true
    if creep.room.name == destination:
      creep.room.observeRoom()
      let controller = creep.room.controller
      if controller.isNil or not controller.owner.isNil or
          (not controller.reservation.isNil and not ownReservation(home, controller.reservation.username)):
        state["reservationReturning"] = true
      elif not state["reservationReturning"].to(bool):
        if not controller.reservation.isNil:
          let stats = reservationStats(home)
          stats["lastObservedReservation"] = game.time
          stats["observedTicks"] = controller.reservation.ticksToEnd
        let code = creep.reserveController(controller)
        if code == OK:
          state["lastReserveIntent"] = game.time
          return
        if code notin {ERR_NOT_IN_RANGE, ERR_INVALID_TARGET, ERR_NO_BODYPART}:
          raise newException(ValueError, "Reserve controller returned " & $ord(code))
        if code in {ERR_INVALID_TARGET, ERR_NO_BODYPART}: state["reservationReturning"] = true
  if not safeIntel(home, destination) or
      game.time - state["reservationStarted"].to(int) >= ReservationTravelTimeout and
      state["lastReserveIntent"].isNil:
    state["reservationReturning"] = true
  if creep.room.name == home and state["reservationReturning"].to(bool): return
  let pos = if state["reservationReturning"].to(bool): newRoomPosition(25, 25, home)
    else: newRoomPosition(target["x"].to(int), target["y"].to(int), destination)
  let code = creep.moveTo(pos, travelPathOptions(@[home, destination],
    if state["reservationReturning"].to(bool): 20 else: 1))
  if code == ERR_NO_PATH:
    if state["reservationPathFailed"].isNil: state["reservationPathFailed"] = game.time
    if game.time - state["reservationPathFailed"].to(int) >= RemotePathRetryTicks:
      if not state["reservationReturning"].to(bool):
        roomIntel()[destination]["blockedUntil"] = game.time + IntelRefreshTicks
      state["reservationReturning"] = true
      discard jsDelete(state["reservationPathFailed"])
  elif code == OK:
    discard jsDelete(state["reservationPathFailed"])
  elif code != ERR_TIRED:
    raise newException(ValueError, "Reserver move returned " & $ord(code))
