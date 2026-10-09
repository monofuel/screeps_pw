import
  std/[deques, json, sets, strutils, tables, unittest],
  rules, worldFixture

proc collection(db: JsonNode, name: string): JsonNode =
  for entry in db["collections"]:
    if entry["name"].getStr == name: return entry
  raise newException(ValueError, "Missing collection " & name)

proc fixture(): JsonNode =
  let
    rooms = newJArray()
    terrain = newJArray()
    objects = newJArray()
  for room in WorldRooms:
    rooms.add %*{"_id": room}
    var tiles = repeat('0', 2500)
    if room == StartRooms[1]:
      tiles[15 * 50 + 15] = '1'
      tiles[15 * 50 + 16] = '2'
    terrain.add %*{"room": room, "terrain": tiles}
    objects.add %*{"_id": "source-" & room, "room": room, "type": "source",
      "x": 4, "y": 21, "energy": 1500, "energyCapacity": 1500, "ticksToRegeneration": 300}
  objects.add %*{"_id": "second", "room": StartRooms[1], "type": "source",
    "x": 9, "y": 23, "energy": 1500, "energyCapacity": 1500, "ticksToRegeneration": 300}
  objects.add %*{"_id": "controller", "room": StartRooms[1], "type": "controller", "x": 26, "y": 16, "level": 0}
  objects.add %*{"_id": "mineral", "room": StartRooms[1], "type": "mineral",
    "x": 8, "y": 42, "mineralType": "H", "mineralAmount": 45360, "density": 2}
  rooms.add %*{"_id": "W9N9"}
  terrain.add %*{"room": "W9N9", "terrain": repeat('0', 2500)}
  objects.add %*{"_id": "outside", "room": "W9N9", "type": "source"}
  for index, entity in objects.elems: entity["$loki"] = %(index + 1)
  %*{"collections": [
    {"name": "rooms", "data": rooms}, {"name": "rooms.terrain", "data": terrain},
    {"name": "rooms.objects", "data": objects, "maxId": objects.len},
    {"name": "env", "data": [{"data": {
      "mapView:W9N9": "{}", "mapView:W1N1": "{}", "mapView:W3N3": "{}"}}]}]}

proc roomTerrain(db: JsonNode): Table[string, string] =
  for entry in db.collection("rooms.terrain")["data"]:
    result[entry["room"].getStr] = entry["terrain"].getStr

proc roomObjects(db: JsonNode, room: string): seq[JsonNode] =
  for entity in db.collection("rooms.objects")["data"]:
    if entity["room"].getStr == room: result.add entity

proc distances(tiles: string, objects: seq[JsonNode], start: (int, int)): seq[int] =
  var
    blocked = newSeq[bool](2500)
    queue: Deque[int]
  result = newSeq[int](2500)
  for index in 0..<2500:
    blocked[index] = tiles[index] in {'1', '3'}
    result[index] = -1
  for entity in objects: blocked[entity["y"].getInt * 50 + entity["x"].getInt] = true
  let origin = start[1] * 50 + start[0]
  result[origin] = 0
  queue.addLast(origin)
  while queue.len > 0:
    let index = queue.popFirst()
    for dy in -1..1:
      for dx in -1..1:
        let x = index mod 50 + dx
        let y = index div 50 + dy
        if x notin 0..<50 or y notin 0..<50: continue
        let next = y * 50 + x
        if blocked[next] or result[next] >= 0: continue
        result[next] = result[index] + 1
        queue.addLast(next)

suite "Fixed 4x4 world with matched homes":
  test "Crops the world, seals outer borders and preserves unrelated interiors":
    let original = fixture()
    let balanced = smallWorld(original)
    check original.collection("rooms")["data"].len == 17
    check balanced.collection("rooms")["data"].len == 16
    let env = balanced.collection("env")["data"][0]["data"]
    check not env.hasKey("mapView:W9N9")
    check not env.hasKey("mapView:W3N3")
    check env.hasKey("mapView:W1N1")
    check parseJson(env["accessibleRooms"].getStr).len == 16
    for room, tiles in balanced.roomTerrain():
      for tile in 0..<50:
        if room[1] == '1': check tiles[tile * 50 + 49] == '1'
        if room[1] == '4': check tiles[tile * 50] == '1'
        if room[3] == '1': check tiles[49 * 50 + tile] == '1'
        if room[3] == '4': check tiles[tile] == '1'
      if room notin StartRooms:
        for y in 1..48:
          for x in 1..48: check tiles[y * 50 + x] == '0'
    for entity in balanced.collection("rooms.objects")["data"]:
      check entity["room"].getStr in WorldRooms
      if entity["room"].getStr notin StartRooms:
        check entity in original.collection("rooms.objects")["data"].elems

  test "Homes have rotated terrain and matching resources with unique database IDs":
    let balanced = smallWorld(fixture())
    let terrain = balanced.roomTerrain()
    for index in 0..<2500:
      check terrain[StartRooms[0]][index] == terrain[StartRooms[1]][2499 - index]
    let
      blue = balanced.roomObjects(StartRooms[0])
      red = balanced.roomObjects(StartRooms[1])
    check blue.len == 4
    check red.len == 4
    for index, entity in blue:
      let expected = red[index].copy()
      expected["room"] = %StartRooms[0]
      expected["x"] = %(49 - red[index]["x"].getInt)
      expected["y"] = %(49 - red[index]["y"].getInt)
      expected["_id"] = entity["_id"]
      expected["$loki"] = entity["$loki"]
      check entity == expected
      check entity["_id"] != red[index]["_id"]
    var
      ids: HashSet[string]
      lokiIds: HashSet[int]
    let objects = balanced.collection("rooms.objects")
    for entity in objects["data"]:
      check entity["_id"].getStr notin ids
      check entity["$loki"].getInt notin lokiIds
      ids.incl(entity["_id"].getStr)
      lokiIds.incl(entity["$loki"].getInt)
      check entity["$loki"].getInt <= objects["maxId"].getInt
    check objects["idIndex"].len == objects["data"].len

  test "Home entrances match neighbors and harvesting distances are equal":
    let balanced = smallWorld(fixture())
    let terrain = balanced.roomTerrain()
    for home in StartRooms:
      for side in [(1, 0, 0, 49), (-1, 0, 49, 0), (0, 1, 0, 49), (0, -1, 49, 0)]:
        let neighbor = "W" & $(home[1].ord - '0'.ord + side[0]) & "N" & $(home[3].ord - '0'.ord + side[1])
        for tile in 0..<50:
          let
            homeIndex = if side[0] != 0: tile * 50 + side[2] else: side[2] * 50 + tile
            neighborIndex = if side[0] != 0: tile * 50 + side[3] else: side[3] * 50 + tile
            expected = if tile in 23..26: '0' else: '1'
          check terrain[home][homeIndex] == expected
          check terrain[neighbor][neighborIndex] == expected
    let
      blue = distances(terrain[StartRooms[0]], balanced.roomObjects(StartRooms[0]), StartPositions[0])
      red = distances(terrain[StartRooms[1]], balanced.roomObjects(StartRooms[1]), StartPositions[1])
    for index in 0..<2500: check blue[index] == red[2499 - index]
    for entity in balanced.roomObjects(StartRooms[1]):
      var accessible = 0
      for dy in -1..1:
        for dx in -1..1:
          if red[(entity["y"].getInt + dy) * 50 + entity["x"].getInt + dx] >= 0: inc accessible
      check accessible > 0

  test "Rejects incomplete worlds and unsuitable home templates":
    expect ValueError:
      discard smallWorld(%*{"collections": [{"name": "rooms", "data": []}]})
    let invalid = fixture()
    invalid.collection("rooms.objects")["data"].elems.delete(16)
    expect ValueError: discard smallWorld(invalid)
