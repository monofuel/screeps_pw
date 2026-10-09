import
  ./consts

when defined(js):
  import std/jsffi
else:
  import std/tables

type
  Effects* {.exportc.} = object
    effect*: int
    level*: int
    ticksRemaining*: int
  RoomPosition* {.exportc.} = ref object
    x*: int
    y*: int
    roomName*: cstring
  RoomObject* {.exportc.} = ref object of RootObj
    id*: cstring
    pos*: RoomPosition
    room*: Room
  Store* {.exportc.} = ref object
    energy*: int
  Structure* {.exportc.} = ref object of RoomObject
    hits*: int
    hitsMax*: int
    structureType*: cstring
    my*: bool
    store*: Store
  Spawning* {.exportc.} = ref object
    name*: cstring
    needTime*: int
    remainingTime*: int
  StructureSpawn* {.exportc.} = ref object of Structure
    name*: cstring
    spawning*: Spawning
  StructureLink* {.exportc.} = ref object of Structure
    cooldown*: int
  RoomOwner* {.exportc.} = ref object
    username*: cstring
  CreepBodyPart* {.exportc.} = object
    `type`*: cstring
    hits*: int
    boost*: cstring
  ControllerReservation* {.exportc.} = ref object
    username*: cstring
    ticksToEnd*: int
  StructureController* {.exportc.} = ref object of RoomObject
    my*: bool
    owner*: RoomOwner
    reservation*: ControllerReservation
    level*: int
    progress*, progressTotal*: float
    ticksToDowngrade*: int
    safeMode*: int
    safeModeAvailable*: int
    safeModeCooldown*: int
  RoomTerrain* {.exportc.} = ref object
  CostMatrix* {.exportc.} = ref object
  GameCpu* {.exportc.} = ref object
    limit*, tickLimit*, bucket*: int
  GameGcl* {.exportc.} = ref object
    level*: int
    progress*, progressTotal*: float
  GameMap* {.exportc.} = ref object
  RoomStatus* {.exportc.} = ref object
    status*: cstring
  PathStep* {.exportc.} = object
    x*, y*: int
    dx*, dy*, direction*: int
  PathOptions* {.exportc.} = ref object
    range*: int
    maxRooms*: int
    ignoreCreeps*: bool
    when defined(js):
      costCallback*: proc(roomName: cstring, matrix: CostMatrix): CostMatrix
  PathFinderGoal* {.exportc.} = ref object
    pos*: RoomPosition
    range*: int
  PathFinderOptions* {.exportc.} = ref object
    plainCost*, swampCost*, maxOps*, maxRooms*: int
    when defined(js):
      roomCallback*: proc(roomName: cstring): JsObject
  PathFinderResult* {.exportc.} = ref object
    path*: seq[RoomPosition]
    ops*, cost*: int
    incomplete*: bool
  Room* {.exportc.} = ref object
    energyAvailable*: int
    energyCapacityAvailable*: int
    name*: cstring
    controller*: StructureController
  CreepMemory* {.exportc.} = ref object
    role*: cstring
    homeRoom*: cstring
    delivering*: bool
    sourceId*: cstring
    job*: cstring
    supplyWaitStart*: int
  Creep* {.exportc.} = ref object of RoomObject
    name*: cstring
    owner*: RoomOwner
    body*: seq[CreepBodyPart]
    my*: bool
    spawning*: bool
    store*: Store
    memory*: CreepMemory
    ticksToLive*: int
    hits*, hitsMax*: int
    fatigue*: int
  Source* {.exportc.} = ref object of RoomObject
    effects*: seq[Effects]
    energy*: int
    energyCapacity*: int
    ticksToRegeneration*: int
  Resource* {.exportc.} = ref object of RoomObject
    amount*: int
    resourceType*: cstring
  ConstructionSite* {.exportc.} = ref object of RoomObject
    my*: bool
    progress*: int
    progressTotal*: int
    structureType*: cstring
  SpawnCreepOpts* {.exportc.} = ref object
    dryRun*: bool
    memory*: CreepMemory

when defined(js):
  type
    GameType* {.exportc.} = object
      time*: int
      cpu*: GameCpu
      gcl*: GameGcl
      map*: GameMap
      spawns*: JsAssoc[cstring, StructureSpawn]
      creeps*: JsAssoc[cstring, Creep]
      rooms*: JsAssoc[cstring, Room]
    MemoryType* {.exportc.} = object
      creeps*: JsAssoc[cstring, CreepMemory]
else:
  type
    GameType* {.exportc.} = object
      time*: int
      cpu*: GameCpu
      gcl*: GameGcl
      map*: GameMap
      spawns*: Table[cstring, StructureSpawn]
      creeps*: Table[cstring, Creep]
      rooms*: Table[cstring, Room]
    MemoryType* {.exportc.} = object
      creeps*: Table[cstring, CreepMemory]

when defined(js):
  proc searchPath*(origin: RoomPosition, goal: PathFinderGoal,
      opts: PathFinderOptions): PathFinderResult {.importjs: "PathFinder.search(#, #, #)".} =
    ## Find a bounded multi-room path and report whether the goal was reached.
  proc newRoomPosition*(x, y: int, roomName: cstring): RoomPosition {.importjs: "new RoomPosition(#, #, #)".} =
    ## Construct an engine position accepted by movement and pathfinding APIs.
  proc getUsed*(cpu: GameCpu): float {.importjs: "#.getUsed()".} =
    ## Read CPU used by the current game tick.
  proc getRoomStatus*(map: GameMap, roomName: cstring): RoomStatus {.importjs: "#.getRoomStatus(#)".} =
    ## Read whether a room is normal, novice, respawn or closed.
  proc describeExits*(map: GameMap, roomName: cstring): JsAssoc[cstring, cstring] {.importjs: "#.describeExits(#)".} =
    ## Read neighboring room names by exit direction without requiring vision.
  proc spawnCreep*(spawn: StructureSpawn, body: openArray[cstring],
      name: cstring): ReturnCode {.importjs: "#.spawnCreep(#, #)".}
  proc spawnCreep*(spawn: StructureSpawn, body: openArray[cstring],
      name: cstring, opts: SpawnCreepOpts): ReturnCode {.importjs: "#.spawnCreep(#, #, #)".}
  proc find*(room: Room, target: FindTargetsType): seq[Source] {.importjs: "#.find(#)".}
  proc findStructures*(room: Room, target: FindTargetsType = FIND_MY_STRUCTURES): seq[Structure] {.importjs: "#.find(#)".}
  proc findConstructionSites*(room: Room, target: FindTargetsType = FIND_MY_CONSTRUCTION_SITES): seq[ConstructionSite] {.importjs: "#.find(#)".}
  proc harvest*(creep: Creep, source: Source): ReturnCode {.importjs: "#.harvest(#)".}
  proc findResources*(room: Room, target: FindTargetsType = FIND_DROPPED_RESOURCES): seq[Resource] {.importjs: "#.find(#)".}
  proc pickup*(creep: Creep, resource: Resource): ReturnCode {.importjs: "#.pickup(#)".}
  proc transfer*(creep: Creep, target: Structure,
      resource: cstring): ReturnCode {.importjs: "#.transfer(#, #)".}
  proc transfer*(creep: Creep, target: Creep,
      resource: cstring): ReturnCode {.importjs: "#.transfer(#, #)".} =
    ## Transfer a resource directly into another creep's store.
  proc transferEnergy*(link, target: StructureLink, amount: int): ReturnCode {.importjs: "#.transferEnergy(#, #)".} =
    ## Schedule energy delivery from an owned link to another link in its room.
  proc build*(creep: Creep, site: ConstructionSite): ReturnCode {.importjs: "#.build(#)".}
  proc destroy*(structure: Structure): ReturnCode {.importjs: "#.destroy()".} =
    ## Request structure removal in an owned room when no hostile creeps are present.
  proc upgradeController*(creep: Creep, controller: StructureController): ReturnCode {.importjs: "#.upgradeController(#)".}
  proc claimController*(creep: Creep, controller: StructureController): ReturnCode {.importjs: "#.claimController(#)".} =
    ## Claim a neutral controller subject to the account's room allowance.
  proc reserveController*(creep: Creep, controller: StructureController): ReturnCode {.importjs: "#.reserveController(#)".} =
    ## Extend a neutral controller's reservation using active CLAIM parts.
  proc repair*(creep: Creep, target: Structure): ReturnCode {.importjs: "#.repair(#)".}
  proc withdraw*(creep: Creep, target: Structure, resource: cstring): ReturnCode {.importjs: "#.withdraw(#, #)".}
  proc findCreeps*(room: Room, target: FindTargetsType): seq[Creep] {.importjs: "#.find(#)".}
  proc attack*(tower: Structure, target: Creep): ReturnCode {.importjs: "#.attack(#)".}
  proc attack*(creep: Creep, target: Creep): ReturnCode {.importjs: "#.attack(#)".} =
    ## Submit a melee attack against a creep within one tile.
  proc heal*(tower: Structure, target: Creep): ReturnCode {.importjs: "#.heal(#)".}
  proc repair*(tower: Structure, target: Structure): ReturnCode {.importjs: "#.repair(#)".}
  proc activateSafeMode*(controller: StructureController): ReturnCode {.importjs: "#.activateSafeMode()".}
  proc getActiveBodyparts*(creep: Creep, part: cstring): int {.importjs: "#.getActiveBodyparts(#)".}
  proc getTerrain*(room: Room): RoomTerrain {.importjs: "#.getTerrain()".}
  proc getPositionAt*(room: Room, x, y: int): RoomPosition {.importjs: "#.getPositionAt(#, #)".}
  proc get*(terrain: RoomTerrain, x, y: int): int {.importjs: "#.get(#, #)".}
  proc createConstructionSite*(room: Room, x, y: int, kind: cstring): ReturnCode {.importjs: "#.createConstructionSite(#, #, #)".}
  proc createConstructionSite*(room: Room, x, y: int, kind, name: cstring): ReturnCode {.importjs: "#.createConstructionSite(#, #, #, #)".} =
    ## Create a named spawn construction site.
  proc findPath*(room: Room, start, target: RoomPosition, opts: PathOptions): seq[PathStep] {.importjs: "#.findPath(#, #, #)".}
  proc structureLimit*(kind: cstring, level: int): int {.importjs: "CONTROLLER_STRUCTURES[#][#]".}
  proc moveTo*(creep: Creep, x, y: int): ReturnCode {.importjs: "#.moveTo(#, #)".}
  proc move*(creep: Creep, direction: int): ReturnCode {.importjs: "#.move(#)".} =
    ## Submit one directional movement intent.
  proc set*(matrix: CostMatrix, x, y, cost: int) {.importjs: "#.set(#, #, #)".} =
    ## Set a pathfinding cost while retaining the engine's other obstacles.
  proc moveTo*(creep: Creep, target: RoomPosition): ReturnCode {.importjs: "#.moveTo(#)".}
  proc moveTo*(creep: Creep, target: RoomPosition, opts: PathOptions): ReturnCode {.importjs: "#.moveTo(#, #)".}
  proc moveTo*(creep: Creep, target: RoomObject): ReturnCode {.importjs: "#.moveTo(#)".}
  proc getCapacity*(store: Store, resource: cstring): int {.importjs: "#.getCapacity(#)".}
  proc getFreeCapacity*(store: Store, resource: cstring): int {.importjs: "#.getFreeCapacity(#)".}
  proc getUsedCapacity*(store: Store, resource: cstring): int {.importjs: "#.getUsedCapacity(#)".}
  proc findClosestByPath*[T: RoomObject](position: RoomPosition,
      targets: seq[T]): T {.importjs: "#.findClosestByPath(#)".}
  proc findClosestByPath*[T: RoomObject](position: RoomPosition,
      targets: seq[T], options: PathOptions): T {.importjs: "#.findClosestByPath(#, #)".} =
    ## Select reachable objects using explicit traffic and cost options.
  proc findClosestByRange*[T: RoomObject](position: RoomPosition,
      targets: seq[T]): T {.importjs: "#.findClosestByRange(#)".}
