import
  std/[json, tables, unittest],
  replayDirector, replays

proc frame(tick: int, entities: varargs[JsonNode]): ReplayState =
  result = ReplayState(tick: tick, scores: %*[0, 0])
  for entity in entities: result.objects[entity["_id"].getStr] = entity

proc creep(id, room: string, hits = 100, action = ""): JsonNode =
  result = %*{"_id": id, "room": room, "type": "creep", "user": "blue", "hits": hits}
  if action.len > 0: result["actionLog"] = %*{action: {"x": 4, "y": 5}}

suite "Comfortable replay room direction":
  test "quiet active rooms tour after thirty visible playing seconds":
    var director = initReplayDirector("A", @["blue", "red"])
    director.observe(frame(0, creep("a", "A"), creep("b", "B"), creep("c", "C")))
    director.advance(29.9, true)
    check not director.choose(true)
    director.advance(0.1, true)
    check director.choose(true)
    check director.room == "B"
    director.advance(30, true)
    check director.choose(true)
    check director.room == "C"
    director.advance(30, true)
    check director.choose(true)
    check director.room == "A"

  test "combat respects the hold and wins over routine activity":
    var director = initReplayDirector("A", @["blue"])
    director.observe(frame(0, creep("a", "A"), creep("b", "B"), creep("c", "C")))
    director.advance(29, true)
    director.observe(frame(1, creep("a", "A"), creep("b", "B"), creep("c", "C", action = "rangedAttack")))
    check not director.choose(true)
    director.advance(1, true)
    check director.choose(true)
    check director.room == "C"
    director.advance(30, true)
    director.observe(frame(2, creep("a", "A"), creep("b", "B"), creep("c", "C", action = "heal")))
    check not director.choose(true)

  test "damage to creeps and spawns counts as combat, routine decay does not":
    var director = initReplayDirector("A", @["blue"])
    let road = %*{"_id": "r", "room": "B", "type": "road", "user": "blue", "hits": 100}
    let spawn = %*{"_id": "s", "room": "C", "type": "spawn", "user": "blue", "hits": 5000}
    director.observe(frame(0, creep("a", "A"), creep("b", "B"), road, spawn))
    director.advance(30, true)
    let worn = road.copy()
    worn["hits"] = %50
    let damaged = spawn.copy()
    damaged["hits"] = %4999
    director.observe(frame(1, creep("a", "A"), creep("b", "B"), worn, damaged))
    check director.choose(true)
    check director.room == "C"

  test "controller and construction events outrank routine rooms and expire":
    var director = initReplayDirector("A", @["blue"])
    let controller = %*{"_id": "ctrl", "room": "C", "type": "controller", "user": "blue", "level": 1}
    director.observe(frame(0, creep("a", "A"), creep("b", "B"), controller))
    director.advance(30, true)
    let upgraded = controller.copy()
    upgraded["level"] = %2
    director.observe(frame(1, creep("a", "A"), creep("b", "B"), upgraded))
    check director.choose(true)
    check director.room == "C"
    director.advance(30, true)
    check director.choose(true)
    check director.room == "B"
    let extension = %*{"_id": "e", "room": "D", "type": "extension", "user": "blue"}
    director.advance(30, true)
    director.observe(frame(2, creep("a", "A"), creep("b", "B"), upgraded, extension))
    check director.choose(true)
    check director.room == "D"
    director.advance(30, true)
    director.observe(frame(3, creep("a", "A"), creep("b", "B"), upgraded))
    check not director.choose(true)
    director.advance(10, true)
    check director.choose(true)

  test "idle buildings, neutral creeps, and vanished activity do not cause tours":
    var director = initReplayDirector("A", @["blue"])
    let spawn = %*{"_id": "s", "room": "B", "type": "spawn", "user": "blue", "spawning": nil}
    let neutral = %*{"_id": "n", "room": "C", "type": "creep", "user": "invader"}
    director.observe(frame(0, spawn, neutral))
    director.advance(90, true)
    check not director.choose(true)
    let spawning = spawn.copy()
    spawning["spawning"] = %*{"name": "worker"}
    director.observe(frame(1, spawning, neutral))
    check director.choose(true)
    check director.room == "B"
    director.advance(30, true)
    check not director.choose(true)
    director.observe(frame(2, spawn, neutral))
    check not director.choose(true)

  test "manual stays manual, resume preserves the room and starts a fresh hold":
    var director = initReplayDirector("A", @["blue"])
    director.observe(frame(0, creep("a", "A"), creep("b", "B")))
    director.advance(100, true)
    director.manual("D")
    check not director.choose(true)
    check director.room == "D"
    director.resume()
    director.observe(frame(1, creep("a", "A"), creep("b", "B")))
    director.advance(29, true)
    check not director.choose(true)
    check director.room == "D"
    director.advance(1, true)
    check director.choose(true)
    check director.room == "B"

  test "paused and hidden time cannot consume the hold":
    var director = initReplayDirector("A", @["blue"])
    director.observe(frame(0, creep("a", "A"), creep("b", "B")))
    director.advance(29, true)
    director.advance(100, false)
    director.advance(100, true, visible = false)
    check not director.choose(true)
    director.advance(1, true)
    check not director.choose(false)
    check not director.choose(true, visible = false)
    check director.choose(true)

  test "seeks and loops clear events without changing the room or mode":
    var director = initReplayDirector("A", @["blue"])
    director.observe(frame(0, creep("b", "B")))
    director.advance(30, true)
    director.observe(frame(1, creep("b", "B", action = "attack")))
    director.resetHistory()
    director.observe(frame(100, creep("c", "C")))
    check not director.choose(true)
    check director.room == "A"
    director.advance(30, true)
    check director.choose(true)
    check director.room == "C"
    director.manual("D")
    director.resetHistory()
    check not director.automatic
    check director.room == "D"

  test "a long frame produces one cut and no catchup cuts":
    var director = initReplayDirector("A", @["blue"])
    director.observe(frame(0, creep("a", "A"), creep("b", "B"), creep("c", "C")))
    director.advance(1000, true)
    check director.choose(true)
    check not director.choose(true)
    director.advance(29, true)
    check not director.choose(true)
