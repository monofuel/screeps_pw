import
  std/jsffi,
  screeps_lib,
  ./[worldWorkers, worldMovement, worldThreats]

type
  RoomRoute* = object
    target*: cstring
    rooms*: seq[cstring]

const
  ScoutRole* = "scout".cstring
  IntelRefreshTicks* = 1500
  ScoutRouteTimeout* = 200
  ScoutPlanInterval = 20
  ScoutCpuReserve = 1000
  ScoutCost = 50
  ScoutArrivalRange = 20
  MaxIntelRooms* = 200
  MaxTravelRooms* = 4
  MaxNearbyRooms = 32

proc roomIntel*(): JsObject =
  ## Preserve bounded neighboring-room observations across code reloads.
  let root = memory.toJs
  if root["worldIntel"].isNil:
    root["worldIntel"] = newJsObject()
  if root["worldIntel"]["rooms"].isNil:
    root["worldIntel"]["rooms"] = newJsObject()
  root["worldIntel"]["rooms"]

proc ownReservation*(home, username: cstring): bool =
  ## Recognize account control from an actually owned home controller.
  let room = game.rooms[home]
  not username.isNil and username.len > 0 and not room.isNil and
    not room.controller.isNil and room.controller.my and
    not room.controller.owner.isNil and room.controller.owner.username == username

proc trimIntel(rooms: JsObject) =
  ## Retain recent observations within a fixed room budget.
  var count = 0
  for name, record in rooms.pairs:
    inc count
  while count > MaxIntelRooms:
    var
      oldest = high(int)
      removed: cstring
    for name, record in rooms.pairs:
      let seen = if record["lastSeen"].isNil: 0 else: record["lastSeen"].to(int)
      if removed.isNil or seen < oldest:
        removed = name
        oldest = seen
    discard jsDelete(rooms[removed])
    dec count

proc observeRoom*(room: Room) =
  ## Record actual visible sources, control, threats, status and neighboring rooms.
  let
    rooms = roomIntel()
    record = newJsObject()
    status = game.map.getRoomStatus(room.name)
  record["lastSeen"] = game.time
  record["status"] = if status.isNil: "unknown".cstring else: status.status
  record["exits"] = game.map.describeExits(room.name).toJs
  let sourceRecords = newJsObject()
  for source in room.find(FIND_SOURCES):
    let observed = newJsObject()
    observed["x"] = source.pos.x
    observed["y"] = source.pos.y
    observed["capacity"] = source.energyCapacity
    sourceRecords[source.id] = observed
  record["sources"] = sourceRecords
  record["hostileCreeps"] = room.findCreeps(FIND_HOSTILE_CREEPS).len
  let invader = room.smallInvader()
  if not invader.isNil:
    let threat = newJsObject()
    threat["id"] = invader.id
    threat["x"] = invader.pos.x
    threat["y"] = invader.pos.y
    threat["expires"] = game.time + invader.ticksToLive
    threat["armoredResponse"] = invader.boostedSmallInvader()
    record["smallInvader"] = threat
  let controller = room.controller
  record["hasController"] = not controller.isNil
  if not controller.isNil:
    let control = newJsObject()
    control["x"] = controller.pos.x
    control["y"] = controller.pos.y
    control["level"] = controller.level
    control["my"] = controller.my
    if not controller.owner.isNil:
      control["owner"] = controller.owner.username
    if not controller.reservation.isNil:
      control["reservedBy"] = controller.reservation.username
      control["reservationTicks"] = controller.reservation.ticksToEnd
    record["controller"] = control
  rooms[room.name] = record
  trimIntel(rooms)

proc nearbyRoomRoutes*(home: cstring): seq[RoomRoute] =
  ## Discover bounded routes through fresh peaceful corridors, neutral and owned rooms.
  var routes: seq[RoomRoute]
  proc addExits(path: seq[cstring]) =
    ## Extend a route without repeating destinations or exceeding the room budget.
    let exits = game.map.describeExits(path[^1])
    if exits.isNil: return
    for direction, name in exits.pairs:
      if name == home or routes.len >= MaxNearbyRooms: continue
      var known = false
      for route in routes:
        if route.target == name: known = true
      let status = game.map.getRoomStatus(name)
      if not known and not status.isNil and status.status != "closed".cstring:
        routes.add(RoomRoute(target: name, rooms: path & @[name]))
  addExits(@[home])
  var index = 0
  while index < routes.len:
    let
      route = routes[index]
      record = roomIntel()[route.target]
    inc index
    if route.rooms.len >= MaxTravelRooms or record.isNil or record["lastSeen"].isNil or
        game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
        record["hostileCreeps"].to(int) > 0 or
        not record["blockedUntil"].isNil and record["blockedUntil"].to(int) > game.time:
      continue
    let control = record["controller"]
    if not record["hasController"].isNil and
        (not record["hasController"].to(bool) or not control.isNil and
          (control["my"].to(bool) or control["owner"].isNil and
            (control["reservedBy"].isNil or ownReservation(home, control["reservedBy"].to(cstring))))):
      addExits(route.rooms)
  routes

proc peacefulRoomRoute*(home: cstring, route: seq[cstring]): bool =
  ## Recheck declared travel against current visibility or fresh peaceful intelligence.
  if route.len notin 2..MaxTravelRooms or route[0] != home:
    return false
  for index in 1..<route.len:
    let name = route[index]
    if name in route[0..<index]: return false
    let exits = game.map.describeExits(route[index - 1])
    if exits.isNil: return false
    var connected = false
    for direction, nextRoom in exits.pairs:
      if nextRoom == name: connected = true
    let status = game.map.getRoomStatus(name)
    if not connected or status.isNil or status.status == "closed".cstring:
      return false
    let record = roomIntel()[name]
    if not record.isNil and not record["blockedUntil"].isNil and
        record["blockedUntil"].to(int) > game.time:
      return false
    let visible = game.rooms[name]
    if not visible.isNil:
      if visible.findCreeps(FIND_HOSTILE_CREEPS).len > 0: return false
      let control = visible.controller
      if not control.isNil and not control.my and
          (not control.owner.isNil or not control.reservation.isNil and
            not ownReservation(home, control.reservation.username)):
        return false
    else:
      if record.isNil or record["lastSeen"].isNil or
          game.time - record["lastSeen"].to(int) >= IntelRefreshTicks or
          record["hostileCreeps"].isNil or record["hostileCreeps"].to(int) > 0 or
          record["hasController"].isNil:
        return false
      if record["hasController"].to(bool):
        let control = record["controller"]
        if control.isNil or not control["my"].to(bool) and
            (not control["owner"].isNil or not control["reservedBy"].isNil and
              not ownReservation(home, control["reservedBy"].to(cstring))):
          return false
  true

proc scoutTarget*(home: cstring): cstring =
  ## Choose the least recently observed destination on a bounded safe route.
  let
    rooms = roomIntel()
    routes = nearbyRoomRoutes(home)
  var oldest = high(int)
  result = "".cstring
  for route in routes:
    let name = route.target
    let record = rooms[name]
    var verifyExpiry = false
    if not record.isNil:
      if not record["blockedUntil"].isNil and record["blockedUntil"].to(int) > game.time:
        continue
      let threat = record["smallInvader"]
      let control = record["controller"]
      verifyExpiry = record["hasController"].to(bool) and not record["lastSeen"].isNil and
        record["hostileCreeps"].to(int) == 1 and not threat.isNil and
        not threat["expires"].isNil and threat["expires"].to(int) > record["lastSeen"].to(int) and
        threat["expires"].to(int) <= game.time and
        not control.isNil and not control["my"].to(bool) and control["owner"].isNil and
        (control["reservedBy"].isNil or ownReservation(home, control["reservedBy"].to(cstring)))
      if not verifyExpiry and not record["lastSeen"].isNil and
          game.time - record["lastSeen"].to(int) < IntelRefreshTicks:
        continue
    let seen = if verifyExpiry: -1
      elif record.isNil or record["lastSeen"].isNil: 0 else: record["lastSeen"].to(int)
    if seen < oldest:
      oldest = seen
      result = name

proc spawnScout*(spawn: StructureSpawn, desiredWorkers: int): ReturnCode =
  ## Fund one cheap scout after the home workforce and spawning reserve are ready.
  let room = spawn.room
  if game.time mod ScoutPlanInterval != 0 or not spawn.spawning.isNil or
      room.controller.isNil or not room.controller.my or room.controller.level < 3 or
      room.energyAvailable < room.energyCapacityAvailable or room.energyAvailable < ScoutCost or
      game.cpu.bucket < ScoutCpuReserve or workerCount(room.name) < desiredWorkers:
    return OK
  for creep in game.creeps.items:
    if creep.memory.role == ScoutRole and creep.memory.homeRoom == room.name:
      return OK
  if room.findCreeps(FIND_HOSTILE_CREEPS).len > 0 or scoutTarget(room.name).len == 0:
    return OK
  let
    name = cstring("scout-" & $spawn.name & "-" & $game.time)
    options = SpawnCreepOpts(memory: CreepMemory(role: ScoutRole, homeRoom: room.name))
  spawn.spawnCreep(@["move".cstring], name, options)

proc deferRoom(name: cstring) =
  ## Back off from a failed route without pretending the room was observed.
  let rooms = roomIntel()
  if rooms[name].isNil:
    rooms[name] = newJsObject()
  rooms[name]["blockedUntil"] = game.time + IntelRefreshTicks
  trimIntel(rooms)

proc runScout*(creep: Creep) =
  ## Observe a neighboring room and return home before choosing another target.
  if creep.spawning:
    return
  let
    state = creep.memory.toJs
    home = creep.memory.homeRoom
  if home.isNil or home.len == 0:
    return
  if creep.room.name != home:
    if state["scoutObservedRoom"].isNil or state["scoutObservedRoom"].to(cstring) != creep.room.name or
        game.time mod ScoutPlanInterval == 0:
      creep.room.observeRoom()
    if creep.room.findCreeps(FIND_HOSTILE_CREEPS).len > 0 and
        not state["scoutTarget"].isNil and state["scoutTarget"].to(cstring) != home:
      deferRoom(state["scoutTarget"].to(cstring))
      state["scoutTarget"] = home
    if state["scoutTarget"].isNil or state["scoutTarget"].to(cstring) in [creep.room.name, "".cstring]:
      state["scoutTarget"] = home
  else:
    state["scoutObservedRoom"] = home
    let observed = roomIntel()[home]
    if observed.isNil or game.time mod ScoutPlanInterval == 0:
      creep.room.observeRoom()
    if state["scoutTarget"].isNil or state["scoutTarget"].to(cstring) in [home, "".cstring]:
      if max(abs(creep.pos.x - 25), abs(creep.pos.y - 25)) > ScoutArrivalRange:
        let code = creep.moveTo(newRoomPosition(25, 25, home), PathOptions(range: ScoutArrivalRange))
        if code notin {OK, ERR_TIRED, ERR_NO_PATH}:
          raise newException(ValueError, "Scout return move returned " & $ord(code))
        return
      let target = scoutTarget(home)
      if target.len == 0:
        state["scoutTarget"] = "".cstring
        return
      state["scoutTarget"] = target
      state["scoutStarted"] = game.time
      for route in nearbyRoomRoutes(home):
        if route.target == target: state["scoutRoute"] = toJs(route.rooms)
  state["scoutObservedRoom"] = creep.room.name
  let target = state["scoutTarget"].to(cstring)
  if target.len == 0:
    return
  if target != home and game.time - state["scoutStarted"].to(int) >= ScoutRouteTimeout:
    deferRoom(target)
    state["scoutTarget"] = home
    return
  let options = if state["scoutRoute"].isNil:
      PathOptions(range: ScoutArrivalRange)
    else: travelPathOptions(state["scoutRoute"].to(seq[cstring]), ScoutArrivalRange)
  let code = creep.moveTo(newRoomPosition(25, 25, target), options)
  if code == ERR_NO_PATH:
    if target != home:
      deferRoom(target)
      state["scoutTarget"] = home
  elif code notin {OK, ERR_TIRED}:
    raise newException(ValueError, "Scout move returned " & $ord(code))
