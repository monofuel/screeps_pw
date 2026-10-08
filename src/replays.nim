import
  std/[json, tables],
  zippy,
  rules

const
  ReplayLimit* = 64 * 1024 * 1024
  ChunkLimit = 16 * 1024 * 1024

type
  Replay* = object
    header*: JsonNode
    bytes: string
    payload: int
    cachedIndex: int
    cachedFrames: JsonNode
    lastTick*: int
  ReplayState* = object
    tick*: int
    scores*: JsonNode
    objects*: Table[string, JsonNode]

proc littleEndian(bytes: string, offset: int): int =
  ## Read a bounded unsigned header or gzip length.
  require(offset >= 0 and offset + 4 <= bytes.len, "Truncated replay integer")
  for index in 0..3: result = result or (bytes[offset + index].ord shl (index * 8))

proc openReplay*(bytes: sink string): Replay =
  ## Validate the replay container and its complete chunk index.
  require(bytes.len in 8..ReplayLimit and bytes[0..3] == "SCR1", "Invalid Screeps replay")
  let headerLength = littleEndian(bytes, 4)
  require(headerLength > 0 and headerLength <= bytes.len - 8, "Invalid replay header length")
  result.header = parseJson(bytes[8..<8 + headerLength])
  require(result.header["version"].getInt == 1, "Unsupported replay version")
  result.payload = 8 + headerLength
  result.lastTick = result.header["results"]["ticks"].getInt
  require(result.lastTick in 1..CompetitionTicks, "Invalid replay horizon")
  var nextOffset = 0
  var nextTick = 0
  for chunk in result.header["chunks"]:
    let length = chunk["length"].getInt
    require(chunk["offset"].getInt == nextOffset and length > 18 and
      length <= bytes.len - result.payload - nextOffset, "Invalid replay chunk bounds")
    require(chunk["start"].getInt == nextTick and chunk["end"].getInt >= nextTick and
      chunk["end"].getInt < nextTick + 100, "Invalid replay chunk ticks")
    nextOffset += length
    nextTick = chunk["end"].getInt + 1
  require(nextOffset == bytes.len - result.payload and nextTick == result.lastTick + 1,
    "Replay is incomplete")
  result.bytes = move bytes
  result.cachedIndex = -1

proc frames(replay: var Replay, index: int): JsonNode =
  ## Decode only the requested hundred-tick chunk.
  if index != replay.cachedIndex:
    let chunk = replay.header["chunks"][index]
    let offset = replay.payload + chunk["offset"].getInt
    let length = chunk["length"].getInt
    require(littleEndian(replay.bytes, offset + length - 4) <= ChunkLimit,
      "Replay chunk exceeds decoded limit")
    let decoded = uncompress(replay.bytes[offset..<offset + length], dfGzip)
    require(decoded.len <= ChunkLimit, "Replay chunk exceeds decoded limit")
    replay.cachedFrames = parseJson(decoded)
    require(replay.cachedFrames.kind == JArray and replay.cachedFrames.len ==
      chunk["end"].getInt - chunk["start"].getInt + 1, "Invalid replay frame count")
    for offset, frame in replay.cachedFrames.elems:
      require(frame["tick"].getInt == chunk["start"].getInt + offset and
        frame["keyframe"].getBool == (offset == 0), "Invalid replay frame boundary")
    replay.cachedIndex = index
  replay.cachedFrames

proc stateAt*(replay: var Replay, tick: int): ReplayState =
  ## Reconstruct a tick from its preceding keyframe without resimulation.
  require(tick in 0..replay.lastTick, "Tick outside replay")
  var index = 0
  while replay.header["chunks"][index]["end"].getInt < tick: inc index
  for frame in replay.frames(index):
    if frame["tick"].getInt > tick: break
    for id in frame["remove"]: result.objects.del(id.getStr)
    for entity in frame["upsert"]: result.objects[entity["_id"].getStr] = entity
    result.tick = frame["tick"].getInt
    result.scores = frame["scores"]
  require(result.tick == tick, "Missing replay tick")
