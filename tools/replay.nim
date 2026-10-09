import
  std/[json, os, tables],
  replays, rules

proc main() =
  ## Inspect a replay through the same decoder used by the viewer.
  require(paramCount() == 1, "Usage: nim r tools/replay.nim FILE")
  var replay = openReplay(readFile(paramStr(1)))
  let first = replay.stateAt(0)
  let last = replay.stateAt(replay.lastTick)
  echo $(%*{"ticks": replay.lastTick, "rooms": replay.header["terrain"].len,
    "initialObjects": first.objects.len,
    "terminalObjects": last.objects.len, "scores": last.scores,
    "chunks": replay.header["chunks"].len})

main()
