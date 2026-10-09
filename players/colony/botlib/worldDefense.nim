import
  screeps_lib,
  ./[worldWorkers, worldInfrastructure, worldDiagnostics]

const
  TowerRepairReserve = 700
  SpawnDangerRange = 5
  MeleeWorkerDangerRange = 2
  RangedWorkerDangerRange = 4
  RampartTargets = [RepairTargetHits, RepairTargetHits, RepairTargetHits,
    50000, 100000, 250000, 500000, 1000000, 2000000]

proc defendRoom*(spawn: StructureSpawn) =
  ## Use towers against intruders and protect infrastructure and exposed workers with safe mode.
  let
    room = spawn.room
    hostiles = room.findCreeps(FIND_HOSTILE_CREEPS)
    friendlies = room.findCreeps(FIND_MY_CREEPS)
    structures = room.findStructures(FIND_STRUCTURES)
    controller = room.controller
  var fueledTower = false
  if not controller.isNil and controller.level >= 3:
    for structure in structures:
      if structure.my and structure.structureType == TowerStructureType and
          structure.store.getUsedCapacity(RESOURCE_ENERGY) >= 10:
        fueledTower = true
  var healers, armedHostiles, injured: seq[Creep]
  var repairs: seq[Structure]
  var safeModeActivated = false
  for hostile in hostiles:
    if hostile.getActiveBodyparts("heal") > 0:
      healers.add(hostile)
    let
      melee = hostile.getActiveBodyparts("attack") > 0
      ranged = hostile.getActiveBodyparts("ranged_attack") > 0
      armed = melee or ranged or hostile.getActiveBodyparts("work") > 0
    var workerDanger = false
    if not fueledTower and (melee or ranged):
      for worker in friendlies:
        if worker.spawning or (worker.getActiveBodyparts("work") == 0 and
            worker.getActiveBodyparts("carry") == 0):
          continue
        let distance = hostile.pos.distance(worker.pos)
        if (melee and distance <= MeleeWorkerDangerRange) or
            (ranged and distance <= RangedWorkerDangerRange):
          workerDanger = true
    if armed:
      armedHostiles.add(hostile)
    if not safeModeActivated and armed and (workerDanger or
        hostile.pos.distance(spawn.pos) <= SpawnDangerRange or spawn.hits < spawn.hitsMax) and
        not controller.isNil and controller.my and not (controller.safeMode > 0) and
        controller.safeModeAvailable > 0 and not (controller.safeModeCooldown > 0):
      let code = controller.activateSafeMode()
      if code == OK:
        safeModeActivated = true
      else:
        recordFailure("Safe mode " & $room.name, $ord(code))
  for creep in friendlies:
    if creep.hits < creep.hitsMax:
      injured.add(creep)
  for structure in structures:
    let targetHits = if structure.my and structure.structureType == RampartStructureType and
        not controller.isNil and controller.my:
      RampartTargets[min(max(controller.level, 0), RampartTargets.high)]
      else: RepairTargetHits
    if (structure.my or structure.structureType in [RoadStructureType, ContainerStructureType]) and
        structure.hits < min(structure.hitsMax, targetHits):
      repairs.add(structure)
  let targets = if healers.len > 0: healers
    elif armedHostiles.len > 0: armedHostiles else: hostiles
  var attackTarget: Creep
  for target in targets:
    if attackTarget.isNil or spawn.pos.distance(target.pos) < spawn.pos.distance(attackTarget.pos):
      attackTarget = target
  for tower in structures:
    if not tower.my or tower.structureType != TowerStructureType or tower.store.getUsedCapacity(RESOURCE_ENERGY) < 10:
      continue
    if not attackTarget.isNil:
      discard tower.attack(attackTarget)
    elif injured.len > 0:
      discard tower.heal(tower.pos.findClosestByRange(injured))
    elif tower.store.getUsedCapacity(RESOURCE_ENERGY) > TowerRepairReserve and repairs.len > 0:
      discard tower.repair(tower.pos.findClosestByRange(repairs))
