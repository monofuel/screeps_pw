import
  std/jsffi,
  screeps_lib

type
  LocalMove = object
    creep: Creep
    target: RoomPosition
    arrival: int
  ControllerWorker = object
    name, room: cstring
    target: RoomPosition

const
  TrafficStuckTicks = 2
  MaxTrafficSwaps = 8
  ImpassableCost = 255
  ControllerWorkRange = 3

var
  localMoves: seq[LocalMove]
  heldPositions: seq[cstring]
  controllerWorkers: seq[ControllerWorker]

proc travelPathOptions*(rooms: seq[cstring], arrival: int): PathOptions =
  ## Keep cross-room movement inside the selected route.
  PathOptions(range: arrival, maxRooms: rooms.len,
    costCallback: proc(name: cstring, matrix: CostMatrix): CostMatrix =
      if name notin rooms:
        for x in 0..49:
          for y in 0..49:
            matrix.set(x, y, ImpassableCost)
      matrix)

proc localPathOptions*(arrival = 1, ignoreCreeps = false): PathOptions =
  ## Exclude room exits from local work routes while preserving engine obstacle costs.
  PathOptions(range: arrival, maxRooms: 1, ignoreCreeps: ignoreCreeps,
    costCallback: proc(name: cstring, matrix: CostMatrix): CostMatrix =
      for cell in 0..49:
        matrix.set(cell, 0, ImpassableCost)
        matrix.set(cell, 49, ImpassableCost)
        matrix.set(0, cell, ImpassableCost)
        matrix.set(49, cell, ImpassableCost)
      matrix)

proc beginLocalTraffic*() =
  ## Discard previous-turn game objects before collecting current movement requests.
  localMoves = @[]
  heldPositions = @[]
  controllerWorkers = @[]

proc holdLocalPosition*(creep: Creep) =
  ## Exclude a working creep from traffic exchanges during this turn.
  if creep.name notin heldPositions:
    heldPositions.add(creep.name)

proc protectControllerWork*(creep: Creep, controller: StructureController) =
  ## Keep traffic exchanges inside the accepted controller work range for this turn.
  controllerWorkers.add(ControllerWorker(name: creep.name, room: creep.room.name, target: controller.pos))

proc canYieldControllerWork(creep, destination: Creep): bool =
  ## Permit productive movement while preventing an exchange outside recorded work range.
  for worker in controllerWorkers:
    if worker.name == creep.name and (destination.room.name != worker.room or
        max(abs(destination.pos.x - worker.target.x), abs(destination.pos.y - worker.target.y)) > ControllerWorkRange):
      return false
  true

proc localTrafficRole(creep: Creep): cstring =
  ## Include admitted home transport in worker traffic without changing its accounting role.
  let state = creep.memory.toJs
  if creep.memory.role == "remote".cstring and state["remoteLocalHaul"].to(bool) and
      state["remoteRetired"].to(bool) and state["remoteReturning"].to(bool) and
      creep.room.name == creep.memory.homeRoom:
    "worker".cstring
  else:
    creep.memory.role

proc moveLocal*(creep: Creep, target: RoomPosition, arrival = 1): ReturnCode =
  ## Attempt ordinary movement and retain bounded evidence for congested local routes.
  result = creep.moveTo(target, localPathOptions(arrival))
  let previous = creep.memory.toJs["localMove"]
  var stuck = 0
  if not previous.isNil and previous["tick"].to(int) == game.time - 1 and
      previous["room"].to(cstring) == creep.room.name and
      previous["x"].to(int) == creep.pos.x and previous["y"].to(int) == creep.pos.y and
      previous["targetX"].to(int) == target.x and previous["targetY"].to(int) == target.y and
      previous["arrival"].to(int) == arrival:
    stuck = min(TrafficStuckTicks, previous["stuck"].to(int) + 1)
  if result == ERR_NO_PATH: stuck = TrafficStuckTicks
  let details = newJsObject()
  details["tick"] = game.time
  details["room"] = creep.room.name
  details["x"] = creep.pos.x
  details["y"] = creep.pos.y
  details["targetX"] = target.x
  details["targetY"] = target.y
  details["arrival"] = arrival
  details["stuck"] = stuck
  creep.memory.toJs["localMove"] = details
  if stuck >= TrafficStuckTicks and result in {OK, ERR_NO_PATH} and
      max(abs(creep.pos.x - target.x), abs(creep.pos.y - target.y)) > arrival:
    localMoves.add(LocalMove(creep: creep, target: target, arrival: arrival))

proc resolveLocalTraffic*() =
  ## Exchange adjacent ready workers after their ordinary intents to open blocked corridors.
  var moved: seq[cstring]
  for request in localMoves:
    let creep = request.creep
    if moved.len >= MaxTrafficSwaps * 2 or game.cpu.getUsed() > float(game.cpu.limit - 5):
      break
    if creep.name in moved or creep.name in heldPositions or not creep.my or creep.spawning or creep.fatigue > 0 or
        creep.getActiveBodyparts("move") == 0 or request.target.roomName != creep.room.name:
      continue
    let route = creep.room.findPath(creep.pos, request.target,
      localPathOptions(request.arrival, true))
    if route.len == 0 or max(abs(route[^1].x - request.target.x),
        abs(route[^1].y - request.target.y)) > request.arrival:
      continue
    let step = route[0]
    if step.direction notin 1..8 or max(abs(step.x - creep.pos.x), abs(step.y - creep.pos.y)) != 1:
      continue
    for blocker in game.creeps.items:
      if blocker.room.name != creep.room.name or blocker.pos.x != step.x or blocker.pos.y != step.y:
        continue
      if blocker.name in moved or blocker.name in heldPositions or not blocker.my or blocker.spawning or blocker.fatigue > 0 or
          blocker.localTrafficRole() != creep.localTrafficRole() or blocker.memory.homeRoom != creep.memory.homeRoom or
          blocker.getActiveBodyparts("move") == 0 or not blocker.canYieldControllerWork(creep):
        break
      let first = creep.move(step.direction)
      let second = blocker.move((step.direction + 3) mod 8 + 1)
      if first != OK or second != OK:
        raise newException(ValueError, "Traffic moves returned " & $ord(first) & "/" & $ord(second))
      moved.add(creep.name)
      moved.add(blocker.name)
      break
