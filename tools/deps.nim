import
  std/os,
  ./common

proc main() =
  ## Sync a private Nimby workspace without moving shared dependencies.
  let directory = getEnv("SCREEPS_PW_DEPS", getHomeDir() / ".local/share/screeps-pw/deps")
  createDir(directory)
  if not fileExists(directory / "nim.cfg"): run(["nimby", "create"], directory)
  copyFile(Root / "nimby.lock", directory / "nimby.lock")
  run(["nimby", "sync", "nimby.lock"], directory)

main()
