import
  std/[os, strutils],
  rules,
  ./common

const
  AssetRevision = "f78d18d8eeb899ed3aa7a304944be448aec34dcf"

proc buildViewer*(output: string) =
  ## Build a clean WASM bundle using only pinned shared HUD assets.
  if getEnv("SCREEPS_PW_VIEWER_LOCK") != "1":
    let lock = getHomeDir() / ".cache/screeps-pw/viewer.lock"
    createDir(lock.parentDir)
    run(["flock", lock, "env", "SCREEPS_PW_VIEWER_LOCK=1", getAppFilename(), output])
    return
  if findExe("emcc").len == 0:
    run(["nix", "develop", "path:" & Root, "--command", "nim", "r", "tools/viewer.nim", output])
    return
  let cache = getHomeDir() / ".cache/screeps-pw/emscripten"
  createDir(cache)
  putEnv("EM_CACHE", cache)
  let dependencies = getEnv("SCREEPS_PW_DEPS", getHomeDir() / ".local/share/screeps-pw/deps")
  let source = getEnv("SCREEPS_PW_ART", getHomeDir() / ".local/share/screeps-pw/ui-source")
  if not dirExists(source):
    run(["git", "clone", "--filter=blob:none", "--no-checkout",
      "https://github.com/Metta-AI/polyworld_art.git", source])
    run(["git", "-C", source, "sparse-checkout", "set", "fonts", "icons", "themes/main", "ui"])
    run(["git", "-C", source, "checkout", AssetRevision])
  require(command(["git", "-C", source, "rev-parse", "HEAD"]) == AssetRevision,
    "HUD asset revision mismatch")
  let stage = Root / "build/ui-assets"
  if dirExists(stage): removeDir(stage)
  createDir(stage)
  for directory in ["fonts", "icons", "themes/main", "ui"]:
    copyDir(source / directory, stage / directory)
  copyFile(source / "LICENSE", stage / "LICENSE")
  createDir(Root / "build/viewer")
  writeFile(Root / "build/viewer/shell.html",
    readFile(dependencies / "polyworld/src/polyworld/replay.html").replace("<!-- GAME_LOGO -->", ""))
  run(["nim", "c", "-d:emscripten", "viewer/viewer.nim"])
  let target = absolutePath(output)
  require(target != Root and not Root.isRelativeTo(target) and not symlinkExists(target),
    "Viewer output must not contain the repository or be a symlink")
  if dirExists(target): removeDir(target)
  createDir(target)
  for suffix in ["js", "wasm", "data"]:
    copyFile(Root / "build/viewer/viewer." & suffix, target / "viewer." & suffix)
  copyFile(Root / "build/viewer/viewer.html", target / "index.html")
  copyFile(dependencies / "polyworld/LICENSE", target / "LICENSE-polyworld")
  copyFile(Root / "THIRD_PARTY.md", target / "THIRD_PARTY.md")

proc main() =
  ## Implement the SDK's executable clean-build hook in Nim.
  require(paramCount() <= 1, "Usage: viewer [OUTPUT]")
  buildViewer(if paramCount() == 1: paramStr(1) else: Root / "dist/replay-viewer")

when isMainModule: main()
