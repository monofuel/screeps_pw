import
  std/[json, os, osproc, posix, streams, strutils, tables, tempfiles, times, unittest],
  replays, rules,
  ../tools/[common, match]

proc interruptedEpisode(signal: cint, infrastructure: bool) =
  ## Verify incomplete episodes cannot publish normal results or leak containers.
  let parent = createTempDir("interrupted-", "", getHomeDir() / ".local/share/screeps-pw/matches")
  let child = startProcess(Root / "build/match", args = @[
    Root / "build/players/idle.js", Root / "build/players/idle.js", "--output:" & parent],
    options = {poStdErrToStdOut})
  defer: child.close()
  var directory: string
  let deadline = epochTime() + 20
  while true:
    for kind, path in walkDir(parent):
      if kind == pcDir: directory = path
    if directory.len > 0 and fileExists(directory / "progress.json"): break
    rules.require(epochTime() < deadline and child.running(), "Episode never started")
    sleep(50)
  let container = "screeps-pw-" & directory.lastPathPart.toLowerAscii()
  if infrastructure: discard command(["docker", "kill", "--signal", "KILL", container])
  else: rules.require(posix.kill(child.processID.cint, signal) == 0, "Could not cancel runner")
  let log = child.outputStream.readAll()
  check child.waitForExit() != 0
  check not fileExists(directory / "results.json")
  check not fileExists(directory / "match.replay")
  check container notin command(["docker", "ps", "--all", "--format", "{{.Names}}"])
  if infrastructure: check "Engine failed" in log
  else: check "Match cancelled" in log

suite "Disposable official World":
  test "Exact starts, completed ticks and snapshot playback":
    let directory = runMatch([Root / "build/players/idle.js", Root / "build/players/idle.js"], 101)
    let result = parseFile(directory / "results.json")
    check result["ticks"].getInt == 101
    check result["scores"] == %*[0, 0]
    let initial = parseFile(directory / "initial.json")
    check initial["terrain"].len == WorldRooms.len
    for terrain in initial["terrain"]:
      check terrain["room"].getStr in WorldRooms
    var spawns = 0
    for entity in initial["objects"]:
      check entity["room"].getStr in WorldRooms
      if entity["type"].getStr == "spawn":
        inc spawns
        check entity["store"]["energy"].getInt == 300
        check entity["room"].getStr in StartRooms
    check spawns == 2
    var homeTerrain: array[2, string]
    for entry in initial["terrain"]:
      for slot, home in StartRooms:
        if entry["room"].getStr == home: homeTerrain[slot] = entry["terrain"].getStr
    for index in 0..<2500: check homeTerrain[0][index] == homeTerrain[1][2499 - index]
    for home in StartRooms:
      var sources = 0
      for entity in initial["objects"]:
        if entity["room"].getStr == home and entity["type"].getStr == "source": inc sources
      check sources == 2
    for entity in initial["objects"]:
      if entity["room"].getStr != StartRooms[0] or
          entity["type"].getStr notin ["source", "controller", "mineral", "spawn"]: continue
      var matches = 0
      for counterpart in initial["objects"]:
        if counterpart["room"].getStr != StartRooms[1] or counterpart["type"] != entity["type"] or
            counterpart["x"].getInt != 49 - entity["x"].getInt or
            counterpart["y"].getInt != 49 - entity["y"].getInt: continue
        inc matches
        for key in ["energy", "energyCapacity", "ticksToRegeneration", "mineralType",
            "mineralAmount", "density", "level", "progress", "store"]:
          check entity.getOrDefault(key) == counterpart.getOrDefault(key)
      check matches == 1
    var startingCells: seq[(int, int)]
    for user in initial["users"]:
      if user.getOrDefault("username").getStr in ["Seat0", "Seat1"]:
        check user["cpu"].getInt == 20
        check user["cpuAvailable"].getInt == 0
        check not user.hasKey("bot")
        let slot = parseInt(user["username"].getStr[4..^1])
        var accountSpawns = 0
        for entity in initial["objects"]:
          if entity["type"].getStr != "spawn" or entity["user"] != user["_id"]: continue
          inc accountSpawns
          let room = entity["room"].getStr
          let cell = (4 - parseInt(room[1..1]), 4 - parseInt(room[3..3]))
          check cell == [(1, 1), (2, 2)][slot]
          check entity["x"].getInt == StartPositions[slot][0]
          check entity["y"].getInt == StartPositions[slot][1]
          startingCells.add cell
        check accountSpawns == 1
    check startingCells.len == 2
    var replay = openReplay(readFile(directory / "match.replay"))
    check not replay.header["metadata"]["config"].hasKey("tokens")
    for tick in [0, 1, 99, 100, 101, 3]:
      check replay.stateAt(tick).tick == tick
    let start = replay.stateAt(0)
    check replay.startingRoom(0) == "W3N3"
    check replay.startingRoom(1) == "W2N2"
    check start.objects.len == initial["objects"].len
    for entity in initial["objects"]:
      check start.objects.hasKey(entity["_id"].getStr)
  test "Native routing uses the bounded 4x4 terrain":
    run(["nim", "js", "tests/fixtures/navigation.nim"])
    let directory = runMatch([Root / "build/fixtures/navigation.js", Root / "build/players/idle.js"], 300)
    check "SMALL_WORLD_NAVIGATION_OK" in readFile(directory / "private/seat-0.log")
    check "Error" notin readFile(directory / "private/seat-0.log")
    let reverse = runMatch([Root / "build/players/idle.js", Root / "build/fixtures/navigation.js"], 300)
    check "SMALL_WORLD_NAVIGATION_OK" in readFile(reverse / "private/seat-1.log")
    check "Error" notin readFile(reverse / "private/seat-1.log")
  test "The official runner loads a policy at the full 5 MiB limit":
    let path = getHomeDir() / ".local/share/screeps-pw/large-policy.js"
    let idle = readFile(Root / "build/players/idle.js")
    writeFile(path, idle & "\n/*" & repeat(' ', PolicyBytes - idle.len - 5) & "*/")
    check getFileSize(path) == PolicyBytes
    let directory = runMatch([path, Root / "build/players/idle.js"], 3)
    check parseFile(directory / "results.json")["ticks"].getInt == 3
    check "Error" notin readFile(directory / "private/seat-0.log")
  test "Policy errors stay private and never terminate native gameplay":
    run(["nim", "js", "tests/fixtures/throwing.nim"])
    let directory = runMatch([Root / "build/fixtures/throwing.js", Root / "build/players/idle.js"], 30)
    check parseFile(directory / "results.json")["ticks"].getInt == 30
    check "PRIVATE_POLICY_SENTINEL" in readFile(directory / "private/seat-0.log")
    check "PRIVATE_POLICY_SENTINEL" notin readFile(directory / "private/seat-1.log")
    check "PRIVATE_POLICY_SENTINEL" notin readFile(directory / "results.json")
    var replay = openReplay(readFile(directory / "match.replay"))
    check "PRIVATE_POLICY_SENTINEL" notin $replay.header
  test "Infinite scripts are bounded by the official runtime":
    run(["nim", "js", "tests/fixtures/infinite.nim"])
    let directory = runMatch([Root / "build/fixtures/infinite.js", Root / "build/players/idle.js"], 5)
    check parseFile(directory / "results.json")["ticks"].getInt == 5
    check "timed out" in readFile(directory / "private/seat-0.log")
  test "Native VM denies host modules and process access":
    run(["nim", "js", "tests/fixtures/sandbox.nim"])
    let directory = runMatch([Root / "build/fixtures/sandbox.js", Root / "build/players/idle.js"], 3)
    check parseFile(directory / "results.json")["ticks"].getInt == 3
    check "SANDBOX_GUARDS_OK" in readFile(directory / "private/seat-0.log")
    check "HOST_MODULE_EXPOSED" notin readFile(directory / "private/seat-0.log")
    check "HOST_PROCESS_EXPOSED" notin readFile(directory / "private/seat-0.log")
  test "Oversized VM allocations remain an account error":
    run(["nim", "js", "tests/fixtures/heap.nim"])
    let directory = runMatch([Root / "build/fixtures/heap.js", Root / "build/players/idle.js"], 3)
    check parseFile(directory / "results.json")["ticks"].getInt == 3
    let log = readFile(directory / "private/seat-0.log").toLowerAscii()
    check "memory limit" in log or "allocation failed" in log
  test "Cancellation removes the disposable world without a completed result":
    interruptedEpisode(SIGINT, false)
  test "Engine infrastructure failure is never a completed draw":
    interruptedEpisode(SIGKILL, true)
