import
  std/[jsffi, algorithm],
  screeps_lib,
  botlib/[strategy, worldWorkers, worldInfrastructure, worldDefense, worldMonitoring,
    worldScouting, worldRemotes, worldExpansion, worldMovement, worldReservations, worldLinks,
    worldFrontier, worldWorkTasks]

type
  WorldStrategy* = ref object of Strategy
    desiredWorkers*: int
    workerPolicy*: WorkerTaskPolicy
    infrastructureEnabled*: bool

const
  DefaultWorkers = 10

proc newWorldStrategy*(desiredWorkers = DefaultWorkers,
    workerPolicy = WorkerTaskPolicy()): WorldStrategy =
  ## Create a bootstrap colony strategy without caching live game objects.
  WorldStrategy(desiredWorkers: desiredWorkers, workerPolicy: workerPolicy,
    infrastructureEnabled: true)

method tick*(self: WorldStrategy) =
  ## Maintain workers in each spawn room and control them independently.
  cleanupCreepMemory()
  beginLocalTraffic()
  try:
    planExpansion(self.desiredWorkers)
  except:
    recordFailure("Expansion planning", getCurrentException().msg)
  for room in game.rooms.items:
    if not room.controller.isNil and room.controller.my and not hasRoomSpawn(room.name):
      try:
        room.planColonySpawn()
      except:
        recordFailure("Colony planning " & $room.name, getCurrentException().msg)
  var handledRooms: seq[cstring]
  for spawn in game.spawns.items:
    if spawn.room.name in handledRooms:
      continue
    handledRooms.add(spawn.room.name)
    try:
      spawn.defendRoom()
    except:
      recordFailure("Defense " & $spawn.room.name, getCurrentException().msg)
    try:
      if self.infrastructureEnabled:
        spawn.planInfrastructure()
    except:
      recordFailure("Planning " & $spawn.room.name, getCurrentException().msg)
    try:
      spawn.room.dispatchControllerEnergy()
    except:
      recordFailure("Links " & $spawn.room.name, getCurrentException().msg)
  handledRooms = @[]
  for spawn in game.spawns.items:
    if not spawn.spawning.isNil or spawn.room.name in handledRooms:
      continue
    try:
      let code = spawn.spawnWorker(self.desiredWorkers)
      if code == OK:
        let expansionCode = spawn.spawnExpansion(self.desiredWorkers)
        if expansionCode != OK:
          recordFailure("Expansion spawn " & $spawn.name, $ord(expansionCode))
        if expansionState()["lastSpawn"].to(int) == game.time:
          handledRooms.add(spawn.room.name)
          continue
        let frontierCode = spawn.spawnFrontier(self.desiredWorkers)
        if frontierCode != OK:
          recordFailure("Frontier spawn " & $spawn.name, $ord(frontierCode))
        if frontierStats(spawn.room.name)["lastSpawn"].to(int) == game.time:
          handledRooms.add(spawn.room.name)
          continue
        var hasScout = false
        for creep in game.creeps.items:
          if creep.memory.role == ScoutRole and creep.memory.homeRoom == spawn.room.name:
            hasScout = true
        let scoutNeeded = not hasScout and scoutTarget(spawn.room.name).len > 0
        let scoutCode = spawn.spawnScout(self.desiredWorkers)
        if scoutCode != OK:
          recordFailure("Scout spawn " & $spawn.name, $ord(scoutCode))
        elif not scoutNeeded:
          let remoteCode = spawn.spawnRemote(self.desiredWorkers)
          if remoteCode != OK:
            recordFailure("Remote spawn " & $spawn.name, $ord(remoteCode))
          else:
            let reservationCode = spawn.spawnReservation(self.desiredWorkers)
            if reservationCode != OK:
              recordFailure("Reservation spawn " & $spawn.name, $ord(reservationCode))
        handledRooms.add(spawn.room.name)
      else:
        recordFailure("Spawn " & $spawn.name, $ord(code))
    except:
      recordFailure("Spawn " & $spawn.name, getCurrentException().msg)
  var controlled: seq[Creep]
  for creep in game.creeps.items: controlled.add(creep)
  if not self.workerPolicy.chooseJob.isNil:
    controlled.sort(proc(a, b: Creep): int = cmp($a.name, $b.name))
  for creep in controlled:
    if creep.memory.role == WorkerRole:
      try:
        creep.runWorker(self.workerPolicy)
      except:
        recordFailure("Worker " & $creep.name, getCurrentException().msg)
    elif creep.memory.role == ScoutRole:
      try:
        creep.runScout()
      except:
        recordFailure("Scout " & $creep.name, getCurrentException().msg)
    elif creep.memory.role == FrontierRole:
      try:
        creep.runFrontier()
      except:
        recordFailure("Frontier " & $creep.name, getCurrentException().msg)
    elif creep.memory.role == RemoteRole:
      try:
        creep.runRemote()
      except:
        recordFailure("Remote " & $creep.name, getCurrentException().msg)
    elif creep.memory.role in [ClaimerRole, ColonistRole]:
      try:
        creep.runSettler()
      except:
        recordFailure("Settler " & $creep.name, getCurrentException().msg)
    elif creep.memory.role == ReserverRole:
      try:
        creep.runReserver()
      except:
        recordFailure("Reserver " & $creep.name, getCurrentException().msg)
  try:
    resolveLocalTraffic()
  except:
    recordFailure("Worker traffic", getCurrentException().msg)
