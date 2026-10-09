import
  std/[json, monotimes, os, parseopt, posix, strutils, tempfiles, times],
  rules,
  ./common

const DefaultImage* = "public.ecr.aws/q5f4m8t9/cogames@sha256:a99178510203da99bf58b48d545c3b3e025a33aeb78f51f0262d543516a9c5d6"

var interrupted = false

proc interrupt() {.noconv.} =
  ## Request episode cleanup on Ctrl-C.
  interrupted = true

proc runMatch*(policies: array[2, string], ticks = CompetitionTicks, seed = 2026,
    output = "", image = DefaultImage): string =
  ## Run a disposable official engine without pacing or a wall-clock cutoff.
  let parent = if output.len > 0: absolutePath(output)
    else: getHomeDir() / ".local/share/screeps-pw/matches"
  createDir(parent)
  result = createTempDir(now().utc.format("yyyyMMdd'T'HHmmss'Z'") & "-", "", parent)
  let directory = result
  let config = %*{"tokens": ["local-0", "local-1"], "players": [
    {"name": policies[0].extractFilename}, {"name": policies[1].extractFilename}],
    "max_ticks": ticks, "seed": seed}
  validateConfig(config)
  createDir(directory / "input")
  createDir(directory / "internal")
  createDir(directory / "private")
  var hashes = newJArray()
  for slot in 0..1:
    rules.require(fileExists(policies[slot]) and getFileSize(policies[slot]) in 1..PolicyBytes,
      "Policy must be an existing file of at most 2 MiB")
    createDir(directory / "input/seat" & $slot)
    copyFile(policies[slot], directory / "input/seat" & $slot / "main.js")
    hashes.add %hashFile(policies[slot])
    writeFile(directory / "private/seat-" & $slot & ".log", "")
  for name in ["launcher", "control"]:
    copyFile(Root / "build/runtime" / (name & ".js"), directory / "input" / (name & ".js"))
  writeFile(directory / "config.json", $config)
  writeFile(directory / "seats.json", "{}")
  writeFile(directory / "mods.json", $(%*{"mods": ["/episode/input/control.js"],
    "bots": {"seat0": "/episode/input/seat0", "seat1": "/episode/input/seat1"}}))
  let imageId = command(["docker", "image", "inspect", "--format", "{{.Id}}", image])
  writeFile(directory / "metadata.json", $(%*{"version": 1, "config": config,
    "image": imageId, "policySha256": hashes, "starts": [
      {"room": StartRooms[0], "x": StartPositions[0][0], "y": StartPositions[0][1]},
      {"room": StartRooms[1], "x": StartPositions[1][0], "y": StartPositions[1][1]}],
    "cpu": 20, "initialBucket": 0,
    "adapterSha256": [hashFile(directory / "input/launcher.js"), hashFile(directory / "input/control.js")]}))
  let container = "screeps-pw-" & directory.lastPathPart.toLowerAscii()
  var created = false
  setControlCHook(interrupt)
  let start = getMonoTime()
  try:
    discard command(["docker", "create", "--name", container, "--init", "--no-healthcheck",
      "--network", "none", "--user", $getuid() & ":" & $getgid(),
      "--tmpfs", "/world:rw,mode=1777,size=256m", "--volume", directory & ":/episode",
      "--volume", directory / "input" & ":/episode/input:ro", "--entrypoint", "node",
      "--env", "PW_REPLAY=/episode/match.replay", "--env", "PW_RESULTS=/episode/results.json",
      imageId, "/episode/input/launcher.js"])
    created = true
    discard command(["docker", "start", container])
    echo "Artifacts: ", directory
    var reported = 0
    while true:
      if interrupted: raise newException(IOError, "Match cancelled")
      let state = parseJson(command(["docker", "inspect", "--format", "{{json .State}}", container]))
      if not state["Running"].getBool:
        rules.require(state["ExitCode"].getInt == 0 and fileExists(directory / "results.json"),
          "Engine failed; inspect " & directory / "failure.json")
        break
      if fileExists(directory / "progress.json"):
        let progress = parseFile(directory / "progress.json")["ticks"].getInt
        if progress >= reported + 1000:
          echo "Completed ticks: ", progress
          reported = progress
      sleep(100)
    echo readFile(directory / "results.json").strip()
    echo "Engine seconds: ", (getMonoTime() - start).inMilliseconds.float / 1000
  finally:
    if created: discard command(["docker", "rm", "--force", container])

proc main() =
  ## Parse the two-policy local match command.
  var
    policies: seq[string]
    ticks = CompetitionTicks
    seed = 2026
    output = ""
    image = DefaultImage
  for kind, key, value in getopt():
    case kind
    of cmdArgument: policies.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "ticks": ticks = parseInt(value)
      of "seed": seed = parseInt(value)
      of "output": output = value
      of "image": image = value
      else: raise newException(ValueError, "Unknown argument: " & key)
    of cmdEnd: discard
  rules.require(policies.len == 2,
    "Usage: build/match POLICY0 POLICY1 [--ticks:6000 --seed:2026 --output:DIR --image:IMAGE]")
  discard runMatch([policies[0], policies[1]], ticks, seed, output, image)

when isMainModule: main()
