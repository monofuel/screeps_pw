import
  std/os,
  ./common

proc main() =
  ## Build tournament hooks and the existing World reference entrant.
  for source in ["launcher", "control"]:
    run(["nim", "js", "runtime/" & source & ".nim"])
  run(["nim", "js", "players/idle.nim"])
  run(["nim", "js", "--out:" & Root / "build/players/baseline.js",
    "src/world/main.nim"], Root.parentDir / "screeps_bot")
  run(["nim", "c", "--out:" & Root / "build/match", "tools/match.nim"])
  run(["nim", "c", "--out:" & Root / "build/server", "src/server.nim"])

main()
