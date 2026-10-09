import
  std/[json, strutils],
  rules

proc connectExit(terrain: var string, x, y, dx, dy: int) =
  for step in 0..<50:
    let index = (y + dy * step) * 50 + x + dx * step
    let connected = step >= 2 and terrain[index] notin {'1', '3'}
    for offset in -1..1: terrain[index + offset * (if dx == 0: 1 else: 50)] = '0'
    if connected: break

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
      collection["idIndex"] = newJArray()
      for entry in retained:
        if entry.hasKey("$loki"): collection["idIndex"].add entry["$loki"]
      collection["binaryIndices"] = newJObject()
    elif name == "env":
      let data = collection["data"][0]["data"]
      var removed: seq[string]
      for key, value in data:
        if key.startsWith("mapView:") and key[8..^1] notin WorldRooms: removed.add key
      for key in removed: data.delete(key)
      data["accessibleRooms"] = %($(%WorldRooms))
