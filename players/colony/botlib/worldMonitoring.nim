import
  std/[jsffi, strutils],
  screeps_lib,
  ./[worldWorkers, worldInfrastructure, worldDiagnostics, worldScouting, worldRemotes,
    worldExpansion, worldReservations, worldFrontier]

export worldDiagnostics

const
  StatusInterval* = 100

proc roomSnapshot(room: Room, previous: JsObject): JsObject =
  ## Sample ownership, growth, workforce, energy, construction and protection.
  result = newJsObject()
  result["tick"] = game.time
  result["energy"] = room.energyAvailable
  result["capacity"] = room.energyCapacityAvailable
  result["status"] = game.map.getRoomStatus(room.name).status
  let jobs = newJsObject()
  for job in [GeneralJob, UpgraderJob, MinerJob, HaulerJob]:
    jobs[job] = 0
  var workers, spawning, scouts, remotes, reservers, defenders = 0
  for creep in game.creeps.items:
    if creep.memory.role == WorkerRole and creep.memory.homeRoom == room.name:
      inc workers
      if creep.spawning: inc spawning
      let job = if creep.memory.job in [UpgraderJob, MinerJob, HaulerJob]: creep.memory.job else: GeneralJob
      jobs[job] = jobs[job].to(int) + 1
    elif creep.memory.role == ScoutRole and creep.memory.homeRoom == room.name:
      inc scouts
    elif creep.memory.role == RemoteRole and creep.memory.homeRoom == room.name:
      inc remotes
    elif creep.memory.role == ReserverRole and creep.memory.homeRoom == room.name:
      inc reservers
    elif creep.memory.role == FrontierRole and creep.memory.homeRoom == room.name:
      inc defenders
  result["workers"] = workers
  result["spawning"] = spawning
  result["scouts"] = scouts
  result["remotes"] = remotes
  result["reservers"] = reservers
  result["defenders"] = defenders
  let defense = frontierStats(room.name)
  result["frontierSpawnCost"] = defense["spawnCost"]
  result["frontierMissions"] = defense["missions"]
  result["frontierLastClear"] = defense["lastClear"].to(int)
  let remote = memory.toJs["worldRemotes"]
  if not remote.isNil and not remote[room.name].isNil:
    result["remoteSpawnCost"] = remote[room.name]["spawnCost"]
    result["remoteHomeEnergy"] = remote[room.name]["homeEnergy"]
    if not remote[room.name]["reservationSpawnCost"].isNil:
      result["reservationSpawnCost"] = remote[room.name]["reservationSpawnCost"]
  result["jobs"] = jobs
  let controller = room.controller
  result["controllerOwned"] = not controller.isNil and controller.my
  result["level"] = if controller.isNil: 0 else: controller.level
  if not controller.isNil and controller.my:
    result["downgradeTicks"] = controller.ticksToDowngrade
    result["safeMode"] = if controller.safeMode > 0: controller.safeMode else: 0
    if controller.level in 1 .. 7:
      result["controllerProgress"] = controller.progress
      result["controllerTotal"] = controller.progressTotal
      if not previous.isNil and previous["controllerOwned"].to(bool):
        let
          oldLevel = previous["level"].to(int)
          oldProgress = previous["controllerProgress"].to(float)
        result["sampleTicks"] = game.time - previous["tick"].to(int)
        if oldLevel == controller.level:
          result["controllerGain"] = controller.progress - oldProgress
        elif oldLevel + 1 == controller.level:
          result["controllerGain"] = previous["controllerTotal"].to(float) - oldProgress + controller.progress
  var sourceEnergy, sourceCount, droppedEnergy, sites, constructionRemaining: int
  for source in room.find(FIND_SOURCES):
    inc sourceCount
    sourceEnergy += source.energy
  for resource in room.findResources():
    if resource.resourceType == RESOURCE_ENERGY:
      droppedEnergy += resource.amount
  for site in room.findConstructionSites():
    if site.my:
      inc sites
      constructionRemaining += site.progressTotal - site.progress
  result["sources"] = sourceCount
  result["sourceEnergy"] = sourceEnergy
  result["droppedEnergy"] = droppedEnergy
  result["sites"] = sites
  result["constructionRemaining"] = constructionRemaining
  var towers, towerEnergy, spawnRampartHits, storages, storageEnergy, containerEnergy: int
  for structure in room.findStructures(FIND_STRUCTURES):
    if structure.my and structure.structureType == TowerStructureType:
      inc towers
      towerEnergy += structure.store.getUsedCapacity(RESOURCE_ENERGY)
    elif structure.my and structure.structureType == StorageStructureType:
      inc storages
      storageEnergy += structure.store.getUsedCapacity(RESOURCE_ENERGY)
    elif structure.structureType == ContainerStructureType:
      containerEnergy += structure.store.getUsedCapacity(RESOURCE_ENERGY)
    elif structure.my and structure.structureType == RampartStructureType:
      for spawn in game.spawns.items:
        if spawn.room.name == room.name and spawn.pos.distance(structure.pos) == 0:
          if spawnRampartHits == 0 or structure.hits < spawnRampartHits:
            spawnRampartHits = structure.hits
  result["towers"] = towers
  result["towerEnergy"] = towerEnergy
  result["spawnRampartHits"] = spawnRampartHits
  result["storages"] = storages
  result["storageEnergy"] = storageEnergy
  result["storageReserve"] = StorageReserveEnergy
  result["containerEnergy"] = containerEnergy

proc updateWorldHealth*() =
  ## Advance the loop heartbeat and periodically replace snapshots and log status.
  let health = worldHealthState()
  health["lastTick"] = game.time
  if not health["snapshotTick"].isNil and (health["snapshotTick"].to(int) == game.time or game.time mod StatusInterval != 0):
    return
  let rooms = newJsObject()
  var spawnCount = 0
  for spawn in game.spawns.items:
    inc spawnCount
    let name = spawn.room.name
    if not rooms[name].isNil:
      continue
    rooms[name] = roomSnapshot(spawn.room, health["rooms"][name])
  for room in game.rooms.items:
    if not room.controller.isNil and room.controller.my and rooms[room.name].isNil:
      rooms[room.name] = roomSnapshot(room, health["rooms"][room.name])
  health["rooms"] = rooms
  health["ownedRooms"] = ownedRoomCount()
  if not game.gcl.isNil:
    health["gcl"] = game.gcl.toJs
  health["expansion"] = expansionState()
  health["spawns"] = spawnCount
  health["snapshotTick"] = game.time
  health["cpuUsed"] = game.cpu.getUsed()
  health["cpuLimit"] = game.cpu.limit
  health["bucket"] = game.cpu.bucket
  if spawnCount == 0:
    echo "[World] tick=", game.time, " spawns=0 errors=", health["errors"].to(int)
  for name, room in rooms.pairs:
    let growth = if room["controllerGain"].isNil: "n/a" else:
      room["controllerGain"].to(float).formatFloat(ffDecimal, 0) & "/" & $room["sampleTicks"].to(int)
    echo "[World] tick=", game.time, " room=", name, " RCL=", room["level"].to(int),
      " growth=", growth, " energy=", room["energy"].to(int), "/", room["capacity"].to(int),
      " workers=", room["workers"].to(int), " spawning=", room["spawning"].to(int),
      " scouts=", room["scouts"].to(int),
      " remotes=", room["remotes"].to(int),
      " reservers=", room["reservers"].to(int),
      " defenders=", room["defenders"].to(int),
      " miners=", room["jobs"][MinerJob].to(int), " haulers=", room["jobs"][HaulerJob].to(int),
      " sites=", room["sites"].to(int), " errors=", health["errors"].to(int),
      " stored=", room["storageEnergy"].to(int),
      " cpu=", health["cpuUsed"].to(float).formatFloat(ffDecimal, 2), " bucket=", health["bucket"].to(int)
