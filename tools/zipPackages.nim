import
  std/strutils,
  zippy, zippy/crc

proc addWord(bytes: var string, value: uint32, count: int) =
  ## Append a ZIP integer in little-endian order.
  for index in 0..<count: bytes.add char((value shr (index * 8)) and 255)

proc zipPackage*(files: openArray[(string, string)], deflated = true,
    descriptor = false): string =
  ## Build small reproducible ZIP32 packages from authored fixture contents.
  var directory: string
  for (name, contents) in files:
    let
      packed = if deflated: compress(contents, BestSpeed, dfDeflate) else: contents
      checksum = crc32(contents)
      offset = result.len.uint32
      flags = if descriptor: 8'u32 else: 0'u32
      compression = if deflated: 8'u32 else: 0'u32
    result.addWord(0x04034b50, 4)
    for value in [20'u32, flags, compression, 0'u32, 0'u32]: result.addWord(value, 2)
    result.addWord(if descriptor: 0'u32 else: checksum, 4)
    result.addWord(if descriptor: 0'u32 else: packed.len.uint32, 4)
    result.addWord(if descriptor: 0'u32 else: contents.len.uint32, 4)
    result.addWord(name.len.uint32, 2)
    result.addWord(0, 2)
    result.add name
    result.add packed
    if descriptor:
      result.addWord(0x08074b50, 4)
      for value in [checksum, packed.len.uint32, contents.len.uint32]: result.addWord(value, 4)
    directory.addWord(0x02014b50, 4)
    for value in [20'u32, 20'u32, flags, compression, 0'u32, 0'u32]: directory.addWord(value, 2)
    for value in [checksum, packed.len.uint32, contents.len.uint32]: directory.addWord(value, 4)
    directory.addWord(name.len.uint32, 2)
    for value in [0'u32, 0'u32, 0'u32, 0'u32]: directory.addWord(value, 2)
    directory.addWord(0, 4)
    directory.addWord(offset, 4)
    directory.add name
  let start = result.len.uint32
  result.add directory
  result.addWord(0x06054b50, 4)
  result.addWord(0, 2)
  result.addWord(0, 2)
  result.addWord(files.len.uint32, 2)
  result.addWord(files.len.uint32, 2)
  result.addWord(directory.len.uint32, 4)
  result.addWord(start, 4)
  result.addWord(0, 2)

proc addWasm*(): string =
  ## Encode a purpose-built module exporting integer addition, without private bot code.
  let hex = "0061736d0100000001070160027f7f017f030201000707010361646400000a09010700200020016a0b"
  for index in countup(0, hex.len - 2, 2):
    result.add char(parseHexInt(hex[index..index + 1]))
