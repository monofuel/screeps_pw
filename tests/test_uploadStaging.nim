import
  std/[json, os, osproc, streams, strutils, tempfiles, unittest],
  replays, rules,
  ../tools/[common, sdk]

proc stagedEpisode(directory: string, sizes: array[2, int]): int =
  let manifest = parseFile(Root / "dist/coworld_manifest.json")
  let idle = readFile(Root / "build/players/idle.js")
  manifest["certification"]["game_config"]["max_ticks"] = %3
  for slot in 0..1:
    let path = directory / ("policy-" & $slot & ".js")
    if sizes[slot] == 0: writeFile(path, "")
    else: writeFile(path, idle & "\n/*" & repeat(' ', sizes[slot] - idle.len - 5) & "*/")
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
