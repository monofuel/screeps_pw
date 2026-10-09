import
  screeps_lib

type
  ControllerLinkPair* = object
    sender*, receiver*: StructureLink

const
  ControllerLinkRange* = 2
  StorageLinkRange* = 1
  MinimumLinkTransfer* = 50

proc linkDistance(a, b: RoomPosition): int =
  ## Measure local range without retaining engine objects across ticks.
  max(abs(a.x - b.x), abs(a.y - b.y))

proc controllerLinks*(room: Room): ControllerLinkPair =
  ## Discover a distinct owned storage sender and controller receiver from live geometry.
  if room.controller.isNil or not room.controller.my or room.controller.level < 5:
    return
  let structures = room.findStructures(FIND_STRUCTURES)
  var storage: Structure
  for structure in structures:
    if structure.my and structure.structureType == StorageStructureType:
      storage = structure
      break
  if storage.isNil:
    return
  for structure in structures:
    if not structure.my or structure.structureType != LinkStructureType or
        structure.pos.isNil or structure.pos.roomName != room.name:
      continue
    if structure.pos.linkDistance(storage.pos) <= StorageLinkRange and
        structure.pos.linkDistance(room.controller.pos) > ControllerLinkRange:
      if result.sender.isNil: result.sender = StructureLink(structure)
    elif structure.pos.linkDistance(room.controller.pos) <= ControllerLinkRange and
        structure.pos.linkDistance(storage.pos) > StorageLinkRange:
      if result.receiver.isNil: result.receiver = StructureLink(structure)

proc dispatchControllerEnergy*(room: Room) =
  ## Send only a useful load into available receiver capacity when the sender is ready.
  let pair = room.controllerLinks()
  if pair.sender.isNil or pair.receiver.isNil or pair.sender.cooldown > 0:
    return
  let amount = min(pair.sender.store.getUsedCapacity(RESOURCE_ENERGY),
    pair.receiver.store.getFreeCapacity(RESOURCE_ENERGY))
  if amount < MinimumLinkTransfer:
    return
  let code = pair.sender.transferEnergy(pair.receiver, amount)
  if code notin {OK, ERR_TIRED, ERR_FULL, ERR_NOT_ENOUGH_ENERGY, ERR_RCL_NOT_ENOUGH}:
    raise newException(ValueError, "Controller link transfer returned " & $ord(code))
