import
  std/os,
  rules

proc isZip*(prefix: string): bool =
  ## Recognize ZIP artifacts independently of their staged filename.
  prefix.len >= 4 and prefix[0..1] == "PK" and
    prefix[2..3] in ["\x03\x04", "\x05\x06", "\x07\x08"]

proc validatePolicyUpload*(path: string) =
  ## Bound the artifact before either runner stages it.
  let input = open(path, fmRead)
  defer: input.close()
  var prefix = newString(4)
  prefix.setLen(input.readBuffer(prefix[0].addr, 4))
  let size = getFileSize(path)
  if prefix.isZip:
    if size > ArchiveBytes:
      raise newException(PolicyError, "ZIP upload exceeds 17 MiB")
  elif not validPolicySize(size):
    raise newException(PolicyError, PolicySizeMessage)
