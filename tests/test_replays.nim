import
  std/[json, tables, unittest],
  zippy,
  replays

proc encoded(header, frames: JsonNode): string =
  ## Construct a compact recorded-state fixture.
  let bytes = compress($frames, dataFormat = dfGzip)
  header["chunks"] = %*[{"start": 0, "end": 1, "offset": 0, "length": bytes.len}]
  let text = $header
  result = "SCR1"
  for index in 0..3: result.add char((text.len shr (index * 8)) and 255)
  result.add text
  result.add bytes

suite "Recorded-state playback":
  test "Entity creation, mutation and removal survive seeks":
    let header = %*{"version": 1, "results": {"ticks": 1}}
    let frames = %*[
      {"tick": 0, "keyframe": true, "scores": [0,0], "upsert": [
        {"_id": "creep", "x": 1}, {"_id": "removed"}], "remove": []},
      {"tick": 1, "keyframe": false, "scores": [5,0], "upsert": [
        {"_id": "creep", "x": 2}], "remove": ["removed"]}]
    var replay = openReplay(encoded(header, frames))
    let last = replay.stateAt(1)
    check last.objects.len == 1
    check last.objects["creep"]["x"].getInt == 2
    check replay.stateAt(0).objects.len == 2
  test "Truncated files and unsupported versions fail visibly":
    expect ValueError: discard openReplay("SCR1")
    let header = %*{"version": 2, "results": {"ticks": 1}}
    expect ValueError: discard openReplay(encoded(header, %*[]))
