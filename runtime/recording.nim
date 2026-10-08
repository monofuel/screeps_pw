import
  std/[jsffi, json, tables],
  nodeBridge

const PublicFields = ["_id", "type", "room", "x", "y", "user", "name", "body",
  "hits", "hitsMax", "store", "storeCapacity", "storeCapacityResource", "energy",
  "energyCapacity", "level", "progress", "progressTotal", "reservation", "safeMode",
  "safeModeAvailable", "downgradeTime", "spawning", "ageTime", "fatigue", "actionLog",
  "nextRegenerationTime", "deathTime", "structureType", "cooldownTime", "mineralType",
  "mineralAmount", "resourceType", "amount", "decayTime"]

var
  header, frames, chunks: JsonNode
  previous: Table[string, string]
  offset = 0
  startTick = 0

proc buffer(value: cstring): JsObject {.importjs: "Buffer.from(#, 'utf8')".} =
  ## Encode replay JSON into bytes.

proc littleEndian(value: int): JsObject =
  ## Encode the replay header length.
  result = require("buffer").Buffer.alloc(4)
  discard result.writeUInt32LE(value, 0)

proc publicObjects*(objects: JsonNode): JsonNode =
  ## Retain only externally visible entity fields.
  result = newJArray()
  for item in objects:
    var entity = newJObject()
    for key in PublicFields:
      if item.hasKey(key): entity[key] = item[key]
    result.add entity

proc flush() =
  ## Compress an independent seekable chunk.
  if frames.len == 0: return
  let bytes = require("zlib").gzipSync(buffer(cstring($frames)))
  discard fs.appendFileSync("/episode/replay.chunks", bytes)
  chunks.add %*{"start": startTick, "end": frames[^1]["tick"],
    "offset": offset, "length": bytes.length.to(int)}
  offset += bytes.length.to(int)
  frames = newJArray()

proc beginRecording*(metadata, terrain: JsonNode) =
  ## Open a replay without keeping a full episode in memory.
  let publicMetadata = metadata.copy()
  publicMetadata["config"].delete("tokens")
  for account in publicMetadata["accounts"]: account.delete("log")
  var publicTerrain = newJArray()
  for entry in terrain:
    publicTerrain.add %*{"room": entry["room"], "terrain": entry["terrain"]}
  header = %*{"version": 1, "tickRate": 1, "defaultSpeed": 10,
    "metadata": publicMetadata, "terrain": publicTerrain}
  frames = newJArray()
  chunks = newJArray()
  writeText("/episode/replay.chunks", "")

proc record*(tick: int, objects, scores: JsonNode) =
  ## Capture each committed state with a keyframe every hundred ticks.
  if frames.len > 0 and tick >= startTick + 100: flush()
  let keyframe = frames.len == 0
  if keyframe:
    startTick = tick
    previous.clear()
  var
    current = initTable[string, string]()
    changed = newJArray()
    removed = newJArray()
  for entity in publicObjects(objects):
    let id = entity["_id"].getStr
    let encoded = $entity
    current[id] = encoded
    if previous.getOrDefault(id) != encoded: changed.add entity
  for id in previous.keys:
    if not current.hasKey(id): removed.add %id
  frames.add %*{"tick": tick, "keyframe": keyframe, "scores": scores,
    "upsert": changed, "remove": removed}
  previous = current

proc finishRecording*(path: string, verdict: JsonNode) =
  ## Publish the complete indexed replay before the completion marker.
  flush()
  header["chunks"] = chunks
  header["results"] = verdict
  let encoded = buffer(cstring($header))
  let fd = fs.openSync(cstring(path & ".tmp"), "w")
  discard fs.writeSync(fd, buffer("SCR1"))
  discard fs.writeSync(fd, littleEndian(encoded.length.to(int)))
  discard fs.writeSync(fd, encoded)
  let input = fs.openSync("/episode/replay.chunks", "r")
  let blockBuffer = require("buffer").Buffer.alloc(65536)
  while true:
    let count = fs.readSync(input, blockBuffer, 0, 65536, jsNull).to(int)
    if count == 0: break
    discard fs.writeSync(fd, blockBuffer, 0, count)
  fs.closeSync(input)
  fs.closeSync(fd)
  renameFile(cstring(path & ".tmp"), cstring(path))
