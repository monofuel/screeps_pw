import
  std/[json, os, strutils],
  rules,
  ./[common, match, sdk]

proc main() =
  ## Stage the native image, verified file players, and generated viewer hook.
  require(paramCount() <= 2, "Usage: package [MAJOR.MINOR.PATCH [EXISTING_GAME_IMAGE]]")
  let version = if paramCount() >= 1: paramStr(1) else: "0.1.10"
  let parts = version.split('.')
  require(parts.len == 3, "Version must contain major, minor and patch")
  for part in parts:
    require(part.len > 0 and part.allCharsInSet({'0'..'9'}), "Version components must be integers")
  let existing = if paramCount() == 2: paramStr(2) else: ""
  let image = if existing.len > 0: existing else: "screeps-pw:" & version
  let dependencies = getEnv("SCREEPS_PW_DEPS", getHomeDir() / ".local/share/screeps-pw/deps")
  let stage = Root / "build/coworld"
  createDir(stage / "players")
  createDir(stage / "tools")
  if existing.len == 0:
    for dependency in ["mummy", "webby", "crunchy", "nimsimd", "zippy"]:
      let destination = Root / "build/dependencies" / dependency
      if dirExists(destination): removeDir(destination)
      copyDir(dependencies / dependency, destination)
    let base = command(["docker", "image", "inspect", "--format", "{{.Id}}", DefaultImage])
    let release = %*{"version": version, "engineImage": base,
      "engineRevision": "7ff972231c0a0a7aa91978297432ddb806976281",
      "sdkVersion": "0.1.56",
      "baselineSha256": hashFile(Root / "build/players/baseline.js"),
      "adapterSha256": [hashFile(Root / "build/runtime/launcher.js"), hashFile(Root / "build/runtime/engine.js"),
        hashFile(Root / "build/runtime/control.js")],
      "dependenciesSha256": hashFile(Root / "nimby.lock")}
    writeFile(Root / "build/release.json", $release)
    run(["docker", "build", "--file", "coworld/Dockerfile", "--build-arg",
      "ENGINE_IMAGE=" & DefaultImage, "--tag", image, Root])
  for player in ["baseline", "idle"]:
    copyFile(Root / "build/players" / (player & ".js"), stage / "players" / (player & ".js"))
  copyFile(Root / "build/players/wasm.zip", stage / "players/wasm.zip")
  run(["nim", "c", "--out:" & stage / "tools/build_replay_viewer.sh", "tools/viewer.nim"])
  let manifest = parseFile(Root / "coworld/coworld_manifest_template.json")
  let competition = manifest["variants"][0]
  require(manifest["game"]["config_schema"]["properties"]["max_ticks"]["maximum"].getInt == MaxTicks and
    manifest["game"]["results_schema"]["properties"]["ticks"]["maximum"].getInt == MaxTicks and
    competition["game_config"]["max_ticks"].getInt == DefaultTicks and
    $DefaultTicks & "-tick" in competition["name"].getStr and
    "in " & $DefaultTicks & " ticks" in manifest["game"]["description"].getStr,
    "Manifest template must allow " & $MaxTicks & " ticks and default to " & $DefaultTicks)
  manifest["game"]["docs"]["readme"]["value"] = %readFile(Root / "README.md")
  writeFile(stage / "coworld_manifest_template.json", pretty(manifest))
  writeFile(stage / "compose.yaml", "services:\n  game:\n    image: " & image & "\n    platform: linux/amd64\n")
  sdkRun(["build", "--project", stage, "--version", version, "--output", Root / "dist/coworld_manifest.json"])

main()
