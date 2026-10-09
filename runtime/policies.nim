import
  std/[jsffi, json, strutils, tables],
  rules

proc readBuffer(path: cstring): JsObject {.importjs: "require('fs').readFileSync(#)".} =
  ## Read a staged artifact without decoding binary bytes.

proc byteLength(data: JsObject): int {.importjs: "#.length".} =
  ## Count exact buffer bytes.

proc word16(data: JsObject, offset: int): int {.importjs: "#.readUInt16LE(#)".} =
  ## Read a checked ZIP word.

proc word32(data: JsObject, offset: int): int {.importjs: "#.readUInt32LE(#)".} =
  ## Read a checked ZIP integer.

proc slice(data: JsObject, first, last: int): JsObject {.importjs: "#.subarray(#, #)".} =
  ## Borrow a bounded buffer range.

proc utf8(data: JsObject): cstring {.importjs: "#.toString('utf8')".} =
  ## Decode module text using Node's UTF-8 decoder.

proc validUtf8(data: JsObject): bool {.importjs: "((data) => Buffer.from(data.toString('utf8'), 'utf8').equals(data))(#)".} =
  ## Reject text that cannot round trip to its exact original bytes.

proc base64(data: JsObject): cstring {.importjs: "#.toString('base64')".} =
  ## Encode native Screeps binary-module contents.

proc crc32(data: JsObject): int {.importjs: "require('zlib').crc32(#)".} =
  ## Verify ZIP contents using Node's unsigned CRC32.

proc inflate(data: JsObject, limit: int): JsObject {.importjs: "((data, limit) => { try { const result = require('zlib').inflateRawSync(data, {maxOutputLength: limit, info: true}); return {value: result.buffer, consumed: result.engine.bytesWritten}; } catch (error) { return {error: error.message}; } })(#, #)".} =
  ## Bound allocation while translating decompressor errors to policy failures.

proc fail(message: string) {.noreturn.} =
  ## Report a malformed participant artifact.
  raise newException(PolicyError, message)

proc need(condition: bool, message = "Malformed ZIP package") =
  ## Validate an archive field before accessing its bytes.
  if not condition: fail(message)

proc text(data: JsObject): string =
  ## Decode only valid UTF-8 script or filename bytes.
  need(validUtf8(data), "Module names and JavaScript must be UTF-8")
  $utf8(data)

proc moduleName(name: string): string =
  ## Resolve a flat filename to a safe native Screeps module name.
  need(name.len in 1..255, "ZIP filenames must contain 1 to 255 bytes")
  for character in name:
    need(character in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'},
      "ZIP files must have flat ASCII names; directories and unsafe paths are not supported")
  need(name[0] != '.' and ".." notin name, "Unsafe ZIP filename")
  let dot = name.rfind('.')
  result = if dot > 0: name[0..<dot] else: name
  need(result notin ["__proto__", "prototype", "constructor", "lodash"], "Reserved module name")

proc loadPolicy*(path: cstring): JsonNode =
  ## Normalize JavaScript or bounded ZIP contents into native Screeps modules.
  let data = readBuffer(path)
  let size = byteLength(data)
  need(size > 0, PolicySizeMessage)
  let signature = if size >= 4: word32(data, 0) else: 0
  if signature notin [0x04034b50, 0x06054b50, 0x08074b50]:
    need(size <= PolicyBytes, PolicySizeMessage)
    return %*{"main": text(data)}
  need(size <= ArchiveBytes, "ZIP upload exceeds 17 MiB")
  need(size >= 22)
  var endOffset = size - 22
  while endOffset >= max(0, size - 65557):
    if word32(data, endOffset) == 0x06054b50 and
        endOffset + 22 + word16(data, endOffset + 20) == size: break
    dec endOffset
  need(endOffset >= max(0, size - 65557), "ZIP end record is missing")
  need(word16(data, endOffset + 4) == 0 and word16(data, endOffset + 6) == 0,
    "Multi-volume ZIP packages are not supported")
  let count = word16(data, endOffset + 10)
  need(word16(data, endOffset + 8) == count)
  need(count in 1..PackageFiles, "ZIP must contain 1 to 256 files; ZIP64 is not supported")
  let centralSize = word32(data, endOffset + 12)
  var offset = word32(data, endOffset + 16)
  need(offset >= 0 and centralSize >= 0 and offset + centralSize == endOffset,
    "Invalid ZIP directory; ZIP64 is not supported")
  let centralStart = offset
  result = newJObject()
  var names = initTable[string, bool]()
  var ranges: seq[(int, int)]
  var total = 0
  for index in 0..<count:
    need(offset + 46 <= endOffset and word32(data, offset) == 0x02014b50)
    let
      flags = word16(data, offset + 8)
      compression = word16(data, offset + 10)
      checksum = word32(data, offset + 16)
      packed = word32(data, offset + 20)
      expanded = word32(data, offset + 24)
      nameLength = word16(data, offset + 28)
      extraLength = word16(data, offset + 30)
      commentLength = word16(data, offset + 32)
      attributes = word32(data, offset + 38)
      local = word32(data, offset + 42)
      next = offset + 46 + nameLength + extraLength + commentLength
    need(next <= endOffset)
    need(word16(data, offset + 6) <= 20, "ZIP64 and newer ZIP formats are not supported")
    need((flags and not 0x080e) == 0, "Encrypted or unsupported ZIP flags")
    need(compression in [0, 8], "ZIP compression must be stored or Deflate")
    need(compression == 8 or (flags and 6) == 0, "Invalid stored ZIP flags")
    need(word16(data, offset + 34) == 0, "Multi-volume ZIP packages are not supported")
    need(((attributes shr 16) and 0xf000) in [0, 0x8000] and (attributes and 16) == 0,
      "ZIP symlinks and directories are not supported")
    need(packed in 0..ArchiveBytes and expanded in 0..PackageBytes,
      "ZIP contents exceed 16 MiB; ZIP64 is not supported")
    need(total + expanded <= PackageBytes, "ZIP contents exceed 16 MiB")
    total += expanded
    let name = text(slice(data, offset + 46, offset + 46 + nameLength))
    let key = moduleName(name)
    need(not names.hasKey(name) and not result.hasKey(key), "Duplicate ZIP filename or module name")
    names[name] = true
    need(local >= 0 and local + 30 <= centralStart and word32(data, local) == 0x04034b50)
    need(word16(data, local + 6) == flags and word16(data, local + 8) == compression)
    let start = local + 30 + word16(data, local + 26) + word16(data, local + 28)
    need(start <= centralStart and start + packed <= centralStart)
    need(text(slice(data, local + 30, local + 30 + word16(data, local + 26))) == name)
    var recordEnd = start + packed
    if (flags and 8) == 0:
      need(word32(data, local + 14) == checksum and word32(data, local + 18) == packed and
        word32(data, local + 22) == expanded)
    else:
      need(recordEnd + 12 <= centralStart)
      var position = recordEnd
      if word32(data, position) == 0x08074b50: position += 4
      need(position + 12 <= centralStart and word32(data, position) == checksum and
        word32(data, position + 4) == packed and word32(data, position + 8) == expanded,
        "Invalid ZIP data descriptor")
      recordEnd = position + 12
    for previous in ranges:
      need(recordEnd <= previous[0] or local >= previous[1], "Overlapping ZIP records")
    ranges.add (local, recordEnd)
    let compressed = slice(data, start, start + packed)
    var contents = compressed
    if compression == 8:
      let decoded = inflate(compressed, max(1, expanded))
      if not decoded.error.isNil: fail("Invalid or oversized ZIP Deflate stream: " & $decoded.error.to(cstring))
      need(decoded.consumed.to(int) == packed, "Trailing ZIP Deflate bytes")
      contents = decoded.value
    need(byteLength(contents) == expanded and crc32(contents) == checksum,
      "ZIP length or checksum mismatch")
    result[key] = if name.endsWith(".js"): %text(contents)
      else: %*{"binary": $base64(contents)}
    offset = next
  need(offset == endOffset)
  need(names.hasKey("main.js") and result["main"].kind == JString,
    "ZIP package requires main.js at its root")
  need(total > 0, "ZIP contents are empty")
