import
  std/[json, strutils, unittest],
  rules, worldFixture

suite "Fixed 4x4 world":
  test "Crops objects and seals only outer room edges":
    let rooms = newJArray()
    let terrain = newJArray()
    let objects = newJArray()
    for room in WorldRooms:
      rooms.add %*{"_id": room}
      terrain.add %*{"room": room, "terrain": repeat('0', 2500)}
      objects.add %*{"room": room, "type": "source"}
    rooms.add %*{"_id": "W9N9"}
    terrain.add %*{"room": "W9N9", "terrain": repeat('0', 2500)}
    objects.add %*{"room": "W9N9", "type": "source"}
    let original = %*{"collections": [
      {"name": "rooms", "data": rooms}, {"name": "rooms.terrain", "data": terrain},
      {"name": "rooms.objects", "data": objects},
      {"name": "env", "data": [{"data": {"mapView:W9N9": "{}", "mapView:W1N1": "{}"}}]}]}
    let fixture = smallWorld(original)
    check original["collections"][0]["data"].len == 17
    for collection in fixture["collections"]:
      if collection["name"].getStr == "env":
        let env = collection["data"][0]["data"]
        check not env.hasKey("mapView:W9N9")
        check env.hasKey("mapView:W1N1")
        check parseJson(env["accessibleRooms"].getStr).len == 16
        continue
      check collection["data"].len == 16
      if collection["name"].getStr != "rooms.terrain": continue
      for entry in collection["data"]:
        let room = entry["room"].getStr
        let tiles = entry["terrain"].getStr
        for y in 0..<50:
          for x in 0..<50:
            let outer = (room[1] == '1' and x == 49) or (room[1] == '4' and x == 0) or
              (room[3] == '1' and y == 49) or (room[3] == '4' and y == 0)
            check tiles[y * 50 + x] == (if outer: '1' else: '0')
  test "Rejects an incomplete source world":
    expect ValueError:
      discard smallWorld(%*{"collections": [{"name": "rooms", "data": []}]})
