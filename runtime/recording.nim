import
  std/[jsffi, json],
  nodeBridge

const PublicFields = [cstring"_id", "type", "room", "x", "y", "user", "name", "body",
  "hits", "hitsMax", "store", "storeCapacity", "storeCapacityResource", "energy",
  "energyCapacity", "level", "progress", "progressTotal", "reservation", "safeMode",
  "safeModeAvailable", "downgradeTime", "spawning", "ageTime", "fatigue", "actionLog",
  "nextRegenerationTime", "deathTime", "structureType", "cooldownTime", "mineralType",
  "mineralAmount", "resourceType", "amount", "decayTime"]

var
  header, chunks: JsonNode
  frames, previous: JsObject
  offset = 0
  startTick = 0

proc newArray(): JsObject {.importjs: "[@]".} =
  ## Create a native array for per-tick replay data.

proc newMap(): JsObject {.importjs: "new Map(@)".} =
  ## Create a native map from entity id to encoded public fields.

proc push(target, value: JsObject) {.importjs: "#.push(#)".} =
  ## Append to a native array.

proc pushText(target: JsObject, value: cstring) {.importjs: "#.push(#)".} =
  ## Append an id to a native array.

proc get(map: JsObject, key: cstring): cstring {.importjs: "#.get(#)".} =
  ## Read an encoded entity, or undefined.

proc put(map: JsObject, key, value: cstring) {.importjs: "#.set(#, #)".} =
  ## Remember an encoded entity.

proc contains(map: JsObject, key: cstring): bool {.importjs: "#.has(#)".} =
  ## Check whether an entity is still present.

proc keys(map: JsObject): JsObject {.importjs: "Array.from(#.keys())".} =
  ## Snapshot the remembered entity ids.

proc has(item: JsObject, key: cstring): bool {.importjs: "Object.prototype.hasOwnProperty.call(#, #)".} =
  ## Match JSON field presence, including explicit nulls.

proc gzip(value: cstring): JsObject {.importjs: "require('zlib').gzipSync(Buffer.from(#, 'utf8'))".} =
  ## Compress replay JSON.

proc buffer(value: cstring): JsObject {.importjs: "Buffer.from(#, 'utf8')".} =
  ## Encode replay JSON into bytes.

proc littleEndian(value: int): JsObject =
  ## Encode the replay header length.
  result = require("buffer").Buffer.alloc(4)
  discard result.writeUInt32LE(value, 0)

proc publicEntity(item: JsObject): JsObject =
  ## Retain only externally visible entity fields.
  result = newJsObject()
  for key in PublicFields:
    if item.has(key): result[key] = item[key]

proc flush() =
  ## Compress an independent seekable chunk.
  if frames.isNil or frames.length.to(int) == 0: return
  let bytes = gzip(stringify(frames))
  discard fs.appendFileSync(episodePath("replay.chunks"), bytes)
  let last = frames[frames.length.to(int) - 1]
  chunks.add %*{"start": startTick, "end": last.tick.to(int),
    "offset": offset, "length": bytes.length.to(int)}
  offset += bytes.length.to(int)
  frames = newArray()

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
  frames = newArray()
  previous = newMap()
  chunks = newJArray()
  writeText(episodePath("replay.chunks"), "")

proc record*(tick: int, objects, scores: JsObject) =
  ## Capture each committed state with a keyframe every hundred ticks.
  if frames.length.to(int) > 0 and tick >= startTick + 100: flush()
  let keyframe = frames.length.to(int) == 0
  if keyframe:
    startTick = tick
    previous = newMap()
  let
    current = newMap()
    changed = newArray()
    removed = newArray()
  for index in 0 ..< objects.length.to(int):
    let entity = publicEntity(objects[index])
    let id = entity["_id"].to(cstring)
    let encoded = stringify(entity)
    current.put(id, encoded)
    if previous.get(id) != encoded: changed.push(entity)
  let ids = previous.keys()
  for index in 0 ..< ids.length.to(int):
    let id = ids[index].to(cstring)
    if id notin current: removed.pushText(id)
  let frame = newJsObject()
  frame.tick = tick
  frame.keyframe = keyframe
  frame.scores = scores
  frame.upsert = changed
  frame.remove = removed
  frames.push(frame)
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
  let input = fs.openSync(episodePath("replay.chunks"), "r")
  let blockBuffer = require("buffer").Buffer.alloc(65536)
  while true:
    let count = fs.readSync(input, blockBuffer, 0, 65536, jsNull).to(int)
    if count == 0: break
    discard fs.writeSync(fd, blockBuffer, 0, count)
  fs.closeSync(input)
  fs.closeSync(fd)
  renameFile(cstring(path & ".tmp"), cstring(path))
