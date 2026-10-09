import
  std/[json, os, osproc, streams, strutils, tempfiles, unittest],
  replays, rules,
  ../tools/[common, sdk, zipPackages]

proc stagedFiles(directory: string, contents: array[2, string]): int =
  let manifest = parseFile(Root / "dist/coworld_manifest.json")
  for slot in 0..1:
    let path = directory / ("policy-" & $slot & ".js")
    writeFile(path, contents[slot])
    manifest["player"][slot]["file"] = %path.extractFilename
    manifest["certification"]["players"][slot]["player_id"] = manifest["player"][slot]["id"]
  let path = directory / "manifest.json"
  writeFile(path, $manifest)
  let args = sdkCommand(["run-episode", path, "--output-dir", directory / "episode", "--timeout-seconds", "300"])
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

suite "Packaged game-hosted policy staging":
  let parent = getHomeDir() / ".local/share/screeps-pw/upload-checks"
  createDir(parent)
  test "Both seats accept policies above 2 MiB, including exactly 5 MiB":
    let directory = createTempDir("accepted-", "", parent)
    check stagedEpisode(directory, [2 * 1024 * 1024 + 1, PolicyBytes]) == 0
    let result = parseFile(directory / "episode/results.json")
    check result["ticks"].getInt == MatchTicks
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
    check stagedFiles(directory, [package, package]) == 0
    check parseFile(directory / "episode/results.json")["ticks"].getInt == MatchTicks
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
        check parseFile(directory / "episode/results.json")["ticks"].getInt == MatchTicks
      else:
        check code != 0
        let failure = parseFile(directory / "episode/player_failure.json")
        check failure["failed_policy_index"].getInt == 1
        check "16 MiB" in failure["message"].getStr
        check not fileExists(directory / "episode/results.json")
