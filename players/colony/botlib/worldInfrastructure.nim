import
  std/jsffi,
  screeps_lib,
  ./[worldMovement, worldLinks]

const
  PlanInterval = 20
  MaxPendingSites = 6
  MaxNewSites = 2
  ColonyPlacementRadius = 12
  ColonyPlacementChecks = 20
  OuterPlacementRadius = 12
  OuterPlacementChecks = 20
  PlainRoadLevel = 3

proc distance*(a, b: RoomPosition): int =
  ## Measure Chebyshev distance within a room.
  max(abs(a.x - b.x), abs(a.y - b.y))

proc planColonySpawn*(room: Room) =
  ## Place one reachable first spawn in an owned colony using bounded rotating searches.
  if game.time mod PlanInterval != 0 or room.controller.isNil or not room.controller.my:
    return
  let
    structures = room.findStructures(FIND_STRUCTURES)
    sites = room.findConstructionSites(FIND_CONSTRUCTION_SITES)
    sources = room.find(FIND_SOURCES)
    terrain = room.getTerrain()
  for structure in structures:
    if structure.my and structure.structureType == SpawnStructureType:
      return
  for site in sites:
    if site.my and site.structureType == SpawnStructureType:
      return
  var spawnSlots = 0
  for structure in structures:
    if structure.structureType == SpawnStructureType:
      inc spawnSlots
  for site in sites:
    if site.structureType == SpawnStructureType:
      inc spawnSlots
  if spawnSlots >= structureLimit(SpawnStructureType, room.controller.level):
    if room.findCreeps(FIND_HOSTILE_CREEPS).len > 0:
      return
    for structure in structures:
      if not structure.my and structure.structureType == SpawnStructureType:
        let code = structure.destroy()
        if code notin {OK, ERR_BUSY}:
          raise newException(ValueError, "Colony spawn removal in " & $room.name & ": " & $code)
        return
  if sources.len == 0 or sites.len >= MaxPendingSites:
    return
  var
    anchorX = room.controller.pos.x
    anchorY = room.controller.pos.y
    candidates: seq[PathStep]
  for source in sources:
    anchorX += source.pos.x
    anchorY += source.pos.y
  anchorX = anchorX div (sources.len + 1)
  anchorY = anchorY div (sources.len + 1)
  for radius in 0 .. ColonyPlacementRadius:
    for x in anchorX - radius .. anchorX + radius:
      for y in anchorY - radius .. anchorY + radius:
        if max(abs(x - anchorX), abs(y - anchorY)) == radius:
          candidates.add(PathStep(x: x, y: y))
  let root = memory.toJs
  if root["worldSpawnPlans"].isNil:
    root["worldSpawnPlans"] = newJsObject()
  let plans = root["worldSpawnPlans"]
  var cursor = if plans[room.name].isNil: 0 else: plans[room.name].to(int)
  for checked in 0 ..< ColonyPlacementChecks:
    let tile = candidates[cursor mod candidates.len]
    inc cursor
    plans[room.name] = cursor
    if game.cpu.getUsed() > float(game.cpu.limit - 5):
      return
    if tile.x < 3 or tile.y < 3 or tile.x > 46 or tile.y > 46 or
        (terrain.get(tile.x, tile.y) and TerrainWall) != 0:
      continue
    let position = room.getPositionAt(tile.x, tile.y)
    if position.isNil or position.distance(room.controller.pos) <= 3:
      continue
    var blocked = false
    for source in sources:
      if position.distance(source.pos) <= 1: blocked = true
    for structure in structures:
      if position.distance(structure.pos) == 0: blocked = true
    for site in sites:
      if position.distance(site.pos) == 0: blocked = true
    var exits = 0
    for x in tile.x - 1 .. tile.x + 1:
      for y in tile.y - 1 .. tile.y + 1:
        if (x != tile.x or y != tile.y) and (terrain.get(x, y) and TerrainWall) == 0:
          inc exits
    if blocked or exits < 3:
      continue
    let controllerPath = room.findPath(position, room.controller.pos, localPathOptions(3, true))
    if controllerPath.len == 0 or RoomPosition(x: controllerPath[^1].x,
        y: controllerPath[^1].y).distance(room.controller.pos) > 3:
      continue
    var reachableSources = true
    for source in sources:
      let route = room.findPath(position, source.pos, localPathOptions(1, true))
      if route.len == 0 or RoomPosition(x: route[^1].x, y: route[^1].y).distance(source.pos) > 1:
        reachableSources = false
    if reachableSources:
      let code = room.createConstructionSite(tile.x, tile.y, SpawnStructureType,
        cstring("Colony-" & $room.name & "-" & $game.time))
      if code == OK:
        discard jsDelete(plans[room.name])
        return
      if code in {ERR_FULL, ERR_RCL_NOT_ENOUGH, ERR_NOT_OWNER}:
        return

proc planInfrastructure*(spawn: StructureSpawn) =
  ## Place infrastructure within controller limits while reserving access lanes.
  let room = spawn.room
  if game.time mod PlanInterval != 0 or room.controller.isNil or not room.controller.my or room.controller.level < 2:
    return
  let
    structures = room.findStructures(FIND_STRUCTURES)
    sites = room.findConstructionSites(FIND_CONSTRUCTION_SITES)
    sources = room.find(FIND_SOURCES)
    terrain = room.getTerrain()
    level = room.controller.level
  if sites.len >= MaxPendingSites:
    return
  var
    paths, sourcePaths: seq[PathStep]
    placed: seq[PathStep]
    newSites = 0
  for source in sources:
    let route = room.findPath(spawn.pos, source.pos, PathOptions(range: 1, ignoreCreeps: true))
    paths.add(route)
    sourcePaths.add(route)
  paths.add(room.findPath(spawn.pos, room.controller.pos, PathOptions(range: 3, ignoreCreeps: true)))

  proc count(kind: cstring): int =
    ## Count completed and planned structures of one kind.
    for structure in structures:
      if (structure.my or kind == ContainerStructureType) and structure.structureType == kind:
        inc result
    for site in sites:
      if site.my and site.structureType == kind:
        inc result

  proc placementAllowed(kind: cstring, x, y: int): ReturnCode =
    ## Check construction limits, occupancy and reserved access before placing a site.
    if newSites >= MaxNewSites or sites.len + newSites >= MaxPendingSites:
      return ERR_FULL
    if x < 2 or y < 2 or x > 47 or y > 47 or terrain.get(x, y) == TerrainWall:
      return ERR_INVALID_TARGET
    for tile in placed:
      if tile.x == x and tile.y == y:
        return ERR_INVALID_TARGET
    for site in sites:
      if site.pos.x == x and site.pos.y == y:
        return ERR_INVALID_TARGET
    for structure in structures:
      if structure.pos.x == x and structure.pos.y == y:
        let overlay = (kind == RampartStructureType and structure.my and
          structure.structureType != RampartStructureType) or
          (kind in [RoadStructureType, ContainerStructureType] and
          structure.structureType in [RoadStructureType, ContainerStructureType, RampartStructureType] and
          kind != structure.structureType)
        if not overlay:
          return ERR_INVALID_TARGET
    let position = RoomPosition(x: x, y: y, roomName: room.name)
    if kind notin [RoadStructureType, ContainerStructureType, RampartStructureType]:
      if position.distance(spawn.pos) <= 1 or
          position.distance(room.controller.pos) <= (if kind == LinkStructureType: 0 else: 2):
        return ERR_INVALID_TARGET
      for source in sources:
        if position.distance(source.pos) <= 1:
          return ERR_INVALID_TARGET
      for tile in paths:
        if tile.x == x and tile.y == y:
          return ERR_INVALID_TARGET
    OK

  proc create(kind: cstring, x, y: int): ReturnCode =
    ## Place an eligible site and reserve its tile for this planning turn.
    result = placementAllowed(kind, x, y)
    if result != OK:
      return
    result = room.createConstructionSite(x, y, kind)
    if result == OK:
      placed.add(PathStep(x: x, y: y))
      inc newSites

  proc placeNearSpawn(kind: cstring): ReturnCode =
    ## Find a reachable tile near the spawn with room for traffic.
    if newSites >= MaxNewSites or sites.len + newSites >= MaxPendingSites:
      return ERR_FULL
    for radius in 2 .. 6:
      for x in spawn.pos.x - radius .. spawn.pos.x + radius:
        for y in spawn.pos.y - radius .. spawn.pos.y + radius:
          if max(abs(x - spawn.pos.x), abs(y - spawn.pos.y)) != radius or
              (x + y) mod 2 != (spawn.pos.x + spawn.pos.y) mod 2 or
              placementAllowed(kind, x, y) != OK:
            continue
          let position = room.getPositionAt(x, y)
          if position.isNil:
            continue
          let route = room.findPath(spawn.pos, position, PathOptions(range: 1, ignoreCreeps: true))
          if route.len > 0 and max(abs(route[^1].x - x), abs(route[^1].y - y)) <= 1 and create(kind, x, y) == OK:
            return OK
    var candidates: seq[PathStep]
    for radius in 7 .. OuterPlacementRadius:
      for x in spawn.pos.x - radius .. spawn.pos.x + radius:
        for y in spawn.pos.y - radius .. spawn.pos.y + radius:
          if max(abs(x - spawn.pos.x), abs(y - spawn.pos.y)) == radius and
              (x + y) mod 2 == (spawn.pos.x + spawn.pos.y) mod 2:
            candidates.add(PathStep(x: x, y: y))
    let root = memory.toJs
    if root["worldStructurePlans"].isNil:
      root["worldStructurePlans"] = newJsObject()
    if root["worldStructurePlans"][spawn.name].isNil:
      root["worldStructurePlans"][spawn.name] = newJsObject()
    let plans = root["worldStructurePlans"][spawn.name]
    var cursor = if plans[kind].isNil: 0 else: plans[kind].to(int)
    for checked in 0 ..< OuterPlacementChecks:
      if game.cpu.getUsed() > float(game.cpu.limit - 5):
        return ERR_BUSY
      let tile = candidates[cursor mod candidates.len]
      cursor = (cursor + 1) mod candidates.len
      plans[kind] = cursor
      if placementAllowed(kind, tile.x, tile.y) != OK:
        continue
      let position = room.getPositionAt(tile.x, tile.y)
      if position.isNil:
        continue
      let route = room.findPath(spawn.pos, position, PathOptions(range: 1, ignoreCreeps: true))
      if route.len > 0 and RoomPosition(x: route[^1].x, y: route[^1].y).distance(position) <= 1 and
          create(kind, tile.x, tile.y) == OK:
        discard jsDelete(plans[kind])
        return OK
    ERR_NOT_FOUND

  discard create(RampartStructureType, spawn.pos.x, spawn.pos.y)
  if count(TowerStructureType) < structureLimit(TowerStructureType, level):
    discard placeNearSpawn(TowerStructureType)
  if level >= 4 and count(StorageStructureType) < structureLimit(StorageStructureType, level):
    discard placeNearSpawn(StorageStructureType)
  for structure in structures:
    if structure.my and structure.structureType in
        [SpawnStructureType, TowerStructureType, StorageStructureType]:
      discard create(RampartStructureType, structure.pos.x, structure.pos.y)
  var completedExtensions = 0
  for structure in structures:
    if structure.my and structure.structureType == ExtensionStructureType:
      inc completedExtensions
  let readyExtensions = structureLimit(ExtensionStructureType, min(level, 4))
  if completedExtensions < readyExtensions:
    if count(ExtensionStructureType) < structureLimit(ExtensionStructureType, level):
      discard placeNearSpawn(ExtensionStructureType)
    return
  if level >= 5 and count(LinkStructureType) < min(2, structureLimit(LinkStructureType, level)):
    var storage: Structure
    for structure in structures:
      if structure.my and structure.structureType == StorageStructureType:
        storage = structure
        break
    if not storage.isNil:
      for controllerSide in [false, true]:
        let
          anchor = if controllerSide: room.controller.pos else: storage.pos
          radius = if controllerSide: ControllerLinkRange else: StorageLinkRange
        var covered = false
        for structure in structures:
          if structure.my and structure.structureType == LinkStructureType and
              structure.pos.distance(anchor) <= radius and
              (if controllerSide: structure.pos.distance(storage.pos) > StorageLinkRange
                else: structure.pos.distance(room.controller.pos) > ControllerLinkRange):
            covered = true
        for site in sites:
          if site.my and site.structureType == LinkStructureType and
              site.pos.distance(anchor) <= radius and
              (if controllerSide: site.pos.distance(storage.pos) > StorageLinkRange
                else: site.pos.distance(room.controller.pos) > ControllerLinkRange):
            covered = true
        if covered:
          continue
        var placedLink = false
        for x in anchor.x - radius .. anchor.x + radius:
          for y in anchor.y - radius .. anchor.y + radius:
            if placedLink or newSites >= MaxNewSites or sites.len + newSites >= MaxPendingSites:
              continue
            let position = room.getPositionAt(x, y)
            if position.isNil or position.distance(anchor) == 0 or
                (if controllerSide: position.distance(storage.pos) <= StorageLinkRange
                  else: position.distance(room.controller.pos) <= ControllerLinkRange):
              continue
            let route = room.findPath(spawn.pos, position, PathOptions(range: 1, ignoreCreeps: true))
            if route.len > 0 and RoomPosition(x: route[^1].x, y: route[^1].y).distance(position) <= 1 and
                create(LinkStructureType, x, y) == OK:
              placedLink = true
  if count(ExtensionStructureType) < structureLimit(ExtensionStructureType, level):
    discard placeNearSpawn(ExtensionStructureType)
  if completedExtensions < structureLimit(ExtensionStructureType, level):
    return
  var containers = count(ContainerStructureType)
  for source in sources:
    if containers >= structureLimit(ContainerStructureType, level):
      break
    var covered = false
    for structure in structures:
      if structure.structureType == ContainerStructureType and structure.pos.distance(source.pos) <= 1:
        covered = true
    for site in sites:
      if site.my and site.structureType == ContainerStructureType and site.pos.distance(source.pos) <= 1:
        covered = true
    if covered:
      continue
    let route = room.findPath(spawn.pos, source.pos, PathOptions(range: 1, ignoreCreeps: true))
    if route.len > 0:
      let tile = route[^1]
      if RoomPosition(x: tile.x, y: tile.y).distance(source.pos) <= 1 and
          create(ContainerStructureType, tile.x, tile.y) == OK:
        inc containers
  let roadPaths = if level < PlainRoadLevel: sourcePaths else: paths
  for tile in roadPaths:
    if level >= PlainRoadLevel or (terrain.get(tile.x, tile.y) and TerrainSwamp) != 0:
      discard create(RoadStructureType, tile.x, tile.y)
