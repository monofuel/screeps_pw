import
  std/jsffi,
  rules

var
  game {.importc: "Game", nodecl.}: JsObject
  console {.importc, nodecl.}: JsObject
  module {.importc, nodecl.}: JsObject

proc roomPosition(x, y: int, room: cstring): JsObject {.importjs: "new RoomPosition(#, #, #)".}

proc loop() =
  let exits = game.map.describeExits("W1N1".cstring)
  doAssert exits["3"].isNil and exits["5"].isNil
  doAssert exits["1"].to(cstring) == "W1N2".cstring
  doAssert exits["7"].to(cstring) == "W2N1".cstring
  let route = game.map.findRoute(cstring(StartRooms[0]), cstring(StartRooms[1]))
  doAssert route.length.to(int) == 2
  let terrain = game.map.getRoomTerrain("W1N1".cstring)
  for tile in 0..<50:
    doAssert terrain.get(49, tile).to(int) == 1
    doAssert terrain.get(tile, 49).to(int) == 1
  doAssert game.map.findRoute(cstring(StartRooms[0]), "W9N9").to(int) == -2
  for room in WorldRooms:
    if room == StartRooms[0]: continue
    doAssert game.map.findRoute(cstring(StartRooms[0]), cstring(room)).length.to(int) > 0
  if game.time.to(int) == 1:
    discard game.spawns.Spawn1.spawnCreep(toJs(["move".cstring]), "MapScout")
  let scout = game.creeps.MapScout
  if not scout.isNil:
    discard scout.moveTo(roomPosition(25, 25, cstring(StartRooms[1])))
  if game.time.to(int) == 300:
    doAssert not scout.isNil and scout.pos.roomName.to(cstring) == cstring(StartRooms[1])
    console.log("SMALL_WORLD_NAVIGATION_OK")

module.exports.loop = loop
