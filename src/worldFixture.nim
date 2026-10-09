import
  std/[json, strutils, tables],
  rules

proc connectExit(terrain: var string, x, y, dx, dy: int, width = 3) =
  for step in 0..<50:
    let index = (y + dy * step) * 50 + x + dx * step
    let connected = step >= 2 and terrain[index] notin {'1', '3'}
    for offset in -1..(width - 2): terrain[index + offset * (if dx == 0: 1 else: 50)] = '0'
    if connected: break

proc homeExit(terrain: var string, x, y, dx, dy: int) =
  for tile in 0..<50:
    let index = if dx == 0: y * 50 + tile else: tile * 50 + x
    terrain[index] = '1'
  connectExit(terrain, x, y, dx, dy, 4)

proc balanceHomes(db: JsonNode) =
  var
    terrain: Table[string, JsonNode]
    objects: JsonNode
  for collection in db["collections"]:
    case collection["name"].getStr
    of "rooms.terrain":
      for entry in collection["data"]: terrain[entry["room"].getStr] = entry
    of "rooms.objects": objects = collection
    else: discard
  require(not objects.isNil and terrain.hasKey(StartRooms[0]) and
    terrain.hasKey(StartRooms[1]), "Missing starting-room fixture")
  var tiles = terrain[StartRooms[1]]["terrain"].getStr
  for edge in [(0, 24, 1, 0), (49, 24, -1, 0), (24, 0, 0, 1), (24, 49, 0, -1)]:
    homeExit(tiles, edge[0], edge[1], edge[2], edge[3])
  terrain[StartRooms[1]]["terrain"] = %tiles
  var rotated = newString(2500)
  for index in 0..<2500: rotated[index] = tiles[2499 - index]
  terrain[StartRooms[0]]["terrain"] = %rotated
  for home in StartRooms:
    for edge in [(1, 0, 49, 24, -1, 0), (-1, 0, 0, 24, 1, 0),
        (0, 1, 24, 49, 0, -1), (0, -1, 24, 0, 0, 1)]:
      let neighbor = "W" & $(home[1].ord - '0'.ord + edge[0]) &
        "N" & $(home[3].ord - '0'.ord + edge[1])
      require(terrain.hasKey(neighbor), "Missing home neighbor " & neighbor)
      var adjacent = terrain[neighbor]["terrain"].getStr
      homeExit(adjacent, edge[2], edge[3], edge[4], edge[5])
      terrain[neighbor]["terrain"] = %adjacent
  var
    retained = newJArray()
    templateObjects: seq[JsonNode]
    nextId = objects.getOrDefault("maxId").getInt
    sources, controllers, minerals = 0
  for entity in objects["data"]:
    nextId = max(nextId, entity.getOrDefault("$loki").getInt)
    if entity["room"].getStr != StartRooms[0]: retained.add entity
    if entity["room"].getStr == StartRooms[1] and
        entity["type"].getStr in ["source", "controller", "mineral"]:
      templateObjects.add entity
      case entity["type"].getStr
      of "source": inc sources
      of "controller": inc controllers
      of "mineral": inc minerals
      else: discard
  require(sources == 2 and controllers == 1 and minerals == 1,
    "Home template must contain two sources, one controller and one mineral")
  for original in templateObjects:
    let entity = original.copy()
    entity["room"] = %StartRooms[0]
    entity["x"] = %(49 - original["x"].getInt)
    entity["y"] = %(49 - original["y"].getInt)
    inc nextId
    entity["_id"] = %nextId.toHex(24).toLowerAscii()
    entity["$loki"] = %nextId
    retained.add entity
  var ids: Table[string, bool]
  for entity in retained:
    let id = entity["_id"].getStr
    require(not ids.hasKey(id), "Duplicate fixture object " & id)
    ids[id] = true
  objects["data"] = retained
  objects["maxId"] = %nextId

proc smallWorld*(db: JsonNode): JsonNode =
  result = db.copy()
  for collection in result["collections"]:
    let name = collection["name"].getStr
    if name in ["rooms", "rooms.terrain", "rooms.objects", "rooms.intents", "rooms.flags"]:
      var retained = newJArray()
      for entry in collection["data"]:
        let room = entry[if name == "rooms": "_id" else: "room"].getStr
        if room notin WorldRooms: continue
        if name == "rooms.terrain":
          var terrain = entry["terrain"].getStr
          require(terrain.len == 2500, "Invalid world terrain")
          if room[1] != '1': connectExit(terrain, 49, 25, -1, 0)
          if room[1] != '4': connectExit(terrain, 0, 25, 1, 0)
          if room[3] != '1': connectExit(terrain, 25, 49, 0, -1)
          if room[3] != '4': connectExit(terrain, 25, 0, 0, 1)
          for tile in 0..<50:
            if room[1] == '1': terrain[tile * 50 + 49] = '1'
            if room[1] == '4': terrain[tile * 50] = '1'
            if room[3] == '1': terrain[49 * 50 + tile] = '1'
            if room[3] == '4': terrain[tile] = '1'
          entry["terrain"] = %terrain
        retained.add entry
      if name in ["rooms", "rooms.terrain"]:
        require(retained.len == WorldRooms.len, "Missing 4x4 world rooms")
      collection["data"] = retained
    elif name == "env":
      let data = collection["data"][0]["data"]
      var removed: seq[string]
      for key, value in data:
        if key.startsWith("mapView:") and
            (key[8..^1] notin WorldRooms or key[8..^1] in StartRooms): removed.add key
      for key in removed: data.delete(key)
      data["accessibleRooms"] = %($(%WorldRooms))
  balanceHomes(result)
  for collection in result["collections"]:
    if collection["name"].getStr notin
        ["rooms", "rooms.terrain", "rooms.objects", "rooms.intents", "rooms.flags"]: continue
    collection["idIndex"] = newJArray()
    for entry in collection["data"]:
      if entry.hasKey("$loki"): collection["idIndex"].add entry["$loki"]
    collection["binaryIndices"] = newJObject()
