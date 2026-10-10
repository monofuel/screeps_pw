import
  std/[json, os, osproc, posix, streams, strutils, tables, tempfiles, times, unittest],
  replays, rules,
  ../tools/[common, sdk, zipPackages]

proc stagedFiles(directory: string, contents: array[2, string], ticks = 3): int =
  let manifest = parseFile(Root / "dist/coworld_manifest.json")
  manifest["certification"]["game_config"]["max_ticks"] = %ticks
  for slot in 0..1:
    let path = directory / ("policy-" & $slot & ".js")
    writeFile(path, contents[slot])
    manifest["player"][slot]["file"] = %path.extractFilename
    manifest["certification"]["players"][slot]["player_id"] = manifest["player"][slot]["id"]
  let path = directory / "manifest.json"
  writeFile(path, $manifest)
  let args = sdkCommand(["run-episode", path, "--output-dir", directory / "episode", "--timeout-seconds", "60"])
  let child = startProcess(args[0], workingDir = directory, args = args[1..^1], options = {poUsePath, poStdErrToStdOut})
  defer: child.close()
  let output = child.outputStream.readAll()
  result = child.waitForExit()
  writeFile(directory / "sdk.log", output)

proc stagedEpisode(directory: string, sizes: array[2, int]): int =
  ## Generate exact artifact-byte boundaries for the packaged runner.
  let idle = readFile(Root / "build/players/idle.js")
  var contents: array[2, string]
  for slot in 0..1:
    if sizes[slot] > 0:
      contents[slot] = idle & "\n/*" & repeat(' ', sizes[slot] - idle.len - 5) & "*/"
  stagedFiles(directory, contents)

proc sharedEpisode(directory, port: string, policies: array[2, string], ticks: int): seq[string] =
  ## Stage one server episode and return the environment for a shared container.
  createDir(directory)
  var seats = %*{"schema": "coworld-player-seats/2", "seats": [],
    "player_status_uri": "file://" & directory / "status.json"}
  for slot in 0..1:
    let policy = directory / "policy-" & $slot
    copyFile(policies[slot], policy)
    seats["seats"].add %*{"slot": slot, "file_uri": "file://" & policy,
      "log_uri": "file://" & directory / "seat-" & $slot & ".log", "content_hash": hashFile(policy)}
  writeFile(directory / "config.json", $(%*{"tokens": ["a", "b"],
    "players": [{"name": "A"}, {"name": "B"}], "seed": 2026, "max_ticks": ticks}))
  writeFile(directory / "seats.json", $seats)
  result = @["--env", "COGAME_HOST=127.0.0.1", "--env", "COGAME_PORT=" & port]
  for (key, name) in [("CONFIG", "config.json"), ("PLAYER_SEATS", "seats.json"),
      ("RESULTS", "results.json"), ("SAVE_REPLAY", "replay"), ("PLAYER_FAILURE", "failure.json")]:
    result.add ["--env", "COGAME_" & key & "_URI=file://" & directory / name]

suite "Packaged game-hosted policy staging":
  let parent = getHomeDir() / ".local/share/screeps-pw/upload-checks"
  createDir(parent)
  test "Both seats accept policies above 2 MiB, including exactly 5 MiB":
    let directory = createTempDir("accepted-", "", parent)
    check stagedEpisode(directory, [2 * 1024 * 1024 + 1, PolicyBytes]) == 0
    let result = parseFile(directory / "episode/results.json")
    check result["ticks"].getInt == 3
    check result["scores"] == %*[0, 0]
    var replay = openReplay(readFile(directory / "episode/replay"))
    check replay.startingRoom(0) == StartRooms[0]
    check replay.startingRoom(1) == StartRooms[1]
    for slot in 0..1:
      check "Error" notin readFile(directory / "episode/logs/policy_agent_" & $slot & ".log")
  test "Empty and oversized policies report the correct failed seat":
    for invalid in [(0, 0), (1, PolicyBytes + 1)]:
      let directory = createTempDir("rejected-", "", parent)
      var sizes = [8192, 8192]
      sizes[invalid[0]] = invalid[1]
      check stagedEpisode(directory, sizes) != 0
      let failure = parseFile(directory / "episode/player_failure.json")
      check failure["failed_policy_index"].getInt == invalid[0]
      check failure["message"].getStr == PolicySizeMessage
      check not fileExists(directory / "episode/results.json")
  test "Extensionless ZIP staging executes WASM in both seats":
    let directory = createTempDir("wasm-", "", parent)
    let package = readFile(Root / "build/players/wasm.zip")
    check stagedFiles(directory, [package, package], 6) == 0
    check parseFile(directory / "episode/results.json")["ticks"].getInt == 6
    for slot in 0..1:
      let log = readFile(directory / "episode/logs/policy_agent_" & $slot & ".log")
      check "ZIP_WASM_OK 13" in log
      check "Error" notin log
  test "Invalid ZIP contents report the failed seat without normal results":
    let idle = readFile(Root / "build/players/idle.js")
    for slot in 0..1:
      let directory = createTempDir("bad-zip-", "", parent)
      var contents = [idle, idle]
      contents[slot] = zipPackage([("main.js", idle), ("../escape.wasm", addWasm())])
      check stagedFiles(directory, contents) != 0
      let failure = parseFile(directory / "episode/player_failure.json")
      check failure["failed_policy_index"].getInt == slot
      check "flat ASCII" in failure["message"].getStr
      check not fileExists(directory / "episode/results.json")
  test "Packages can exceed 5 MiB while retaining the 16 MiB expanded boundary":
    let idle = readFile(Root / "build/players/idle.js")
    for expanded in [PackageBytes, PackageBytes + 1]:
      let directory = createTempDir("zip-limit-", "", parent)
      let package = zipPackage([("main.js", idle), ("weights.bin", repeat('a', expanded - idle.len))])
      let code = stagedFiles(directory, [idle, package])
      if expanded == PackageBytes:
        check code == 0
        check parseFile(directory / "episode/results.json")["ticks"].getInt == 3
      else:
        check code != 0
        let failure = parseFile(directory / "episode/player_failure.json")
        check failure["failed_policy_index"].getInt == 1
        check "16 MiB" in failure["message"].getStr
        check not fileExists(directory / "episode/results.json")
  test "Two packaged matches run concurrently in one container":
    let directory = createTempDir("shared-", "", parent)
    let image = parseFile(Root / "dist/coworld_manifest.json")["game"]["runnable"]["image"].getStr
    let wasm = Root / "build/players/wasm.zip"
    let idle = Root / "build/players/idle.js"
    let first = sharedEpisode(directory / "a", "8080", [wasm, idle], 600)
    let second = sharedEpisode(directory / "b", "8081", [idle, wasm], 600)
    let container = "screeps-pw-shared-" & directory.lastPathPart.toLowerAscii()
    discard command(@["docker", "run", "--detach", "--name", container, "--network", "none",
      "--user", $getuid() & ":" & $getgid(), "--volume", directory & ":" & directory] & first & @[image])
    try:
      discard command(@["docker", "exec", "--detach"] & second & @[container, "/app/server"])
      check not fileExists(directory / "a/results.json")
      let deadline = epochTime() + 300
      while not (fileExists(directory / "a/results.json") and fileExists(directory / "b/results.json")):
        require(epochTime() < deadline, "Shared container episodes did not finish")
        sleep(200)
      for (name, wasmSlot) in [("a", 0), ("b", 1)]:
        let episode = directory / name
        check parseFile(episode / "results.json")["ticks"].getInt == 600
        check "ZIP_WASM_OK 13" in readFile(episode / "seat-" & $wasmSlot & ".log")
        check "ZIP_WASM_OK" notin readFile(episode / "seat-" & $(1 - wasmSlot) & ".log")
        var replay = openReplay(readFile(episode / "replay"))
        let account = replay.header["metadata"]["accounts"][wasmSlot]["user"]
        var owners: seq[JsonNode]
        for entity in replay.stateAt(6).objects.values:
          if entity["type"].getStr == "creep": owners.add entity["user"]
        check owners == @[account]
    finally:
      discard command(["docker", "rm", "--force", container])
