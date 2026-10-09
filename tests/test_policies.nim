import
  std/[base64, json, os, osproc, streams, strutils, tempfiles, unittest],
  policyUpload, rules,
  ../tools/[common, zipPackages]

proc normalized(bytes: string): tuple[code: int, output: string] =
  ## Exercise the exact trusted runtime used in engine episodes.
  let directory = createTempDir("zip-unit-", "", getTempDir())
  defer: removeDir(directory)
  let path = directory / "extensionless"
  writeFile(path, bytes)
  let child = startProcess("node", args = @[Root / "build/runtime/policyCheck.js", path],
    options = {poUsePath, poStdErrToStdOut})
  defer: child.close()
  result.output = child.outputStream.readAll().strip()
  result.code = child.waitForExit()

proc change(bytes: string, offset: int, value: uint32, count = 4): string =
  ## Alter ZIP metadata to exercise participant rejection paths.
  result = bytes
  for index in 0..<count: result[offset + index] = char((value shr (8 * index)) and 255)

proc rejected(bytes: string) =
  ## Require explicit policy rejection rather than a crash or infrastructure error.
  let outcome = normalized(bytes)
  checkpoint("Rejection outcome: " & $outcome.code & " " & outcome.output[0..<min(200, outcome.output.len)])
  check outcome.code == 2
  check outcome.output.len > 0

suite "JavaScript and ZIP module normalization":
  test "Raw JavaScript retains the inclusive 5 MiB contract":
    check parseJson(normalized("hello").output)["main"].getStr == "hello"
    check normalized(repeat(' ', PolicyBytes)).code == 0
    rejected("")
    rejected(repeat(' ', PolicyBytes + 1))
    rejected("\xff")
  test "Stored, Deflate and descriptor ZIPs preserve modules and binary bytes":
    for compressed in [false, true]:
      for descriptor in [false, true]:
        let outcome = normalized(zipPackage([("main.js", "hello"), ("helper.js", "world"),
          ("brain.wasm", addWasm()), ("weights.bin", "\0\xff\x07")], compressed, descriptor))
        check outcome.code == 0
        let modules = parseJson(outcome.output)
        check modules["main"].getStr == "hello"
        check modules["helper"].getStr == "world"
        check decode(modules["brain"]["binary"].getStr) == addWasm()
        check decode(modules["weights"]["binary"].getStr) == "\0\xff\x07"
  test "The 16 MiB expanded boundary is inclusive and independent of compression":
    check normalized(zipPackage([("main.js", "x"), ("weights.bin", repeat('a', PackageBytes - 1))])).code == 0
    rejected(zipPackage([("main.js", "x"), ("weights.bin", repeat('a', PackageBytes))]))
    rejected("PK\x03\x04" & repeat(' ', ArchiveBytes))
    var files = @[("main.js", "x")]
    for index in 1..<PackageFiles: files.add ($index & ".bin", "")
    check normalized(zipPackage(files)).code == 0
    files.add ("excess.bin", "")
    rejected(zipPackage(files))
  test "Entry points, paths and module collisions are explicit errors":
    for files in [
      @[("helper.js", "x")], @[("main.wasm", "x")], @[("main.js", "x"), ("main.js", "x")],
      @[("main.js", "x"), ("main.bin", "x")], @[("main.js", "x"), ("../escape.bin", "x")],
      @[("main.js", "x"), ("/absolute", "x")], @[("main.js", "x"), ("nested/helper.js", "x")],
      @[("main.js", "x"), ("a\\b", "x")], @[("main.js", "x"), ("C:drive", "x")],
      @[("main.js", "x"), ("__proto__.bin", "x")], @[("main.js", "x"), ("constructor.js", "x")],
      @[("main.js", "x"), ("a\0b", "x")], @[("main.js", "x"), ("lodash.js", "x")]]:
      rejected(zipPackage(files))
  test "Corruption, unsupported formats and dishonest expansion metadata are rejected":
    let good = zipPackage([("main.js", repeat('x', 10000))])
    let central = good.find("PK\x01\x02")
    for length in [4, 20, 40, central, good.len - 1]: rejected(good[0..<length])
    rejected(good.change(central + 8, 1, 2))
    rejected(good.change(central + 10, 99, 2))
    rejected(good.change(central + 6, 45, 2))
    rejected(good.change(central + 38, 0xa1ff0000'u32))
    rejected(good.change(central + 16, 123))
    rejected(good.change(central + 24, 0xffffffff'u32))
    rejected(good.change(central + 24, 1).change(22, 1))
    rejected(good.change(good.len - 18, 1, 2))
    let descriptor = zipPackage([("main.js", "x")], true, true)
    rejected(descriptor.change(descriptor.find("PK\x07\x08") + 4, 123))
  test "Native intake recognizes ZIP bytes without trusting the filename":
    let directory = createTempDir("zip-intake-", "", getTempDir())
    defer: removeDir(directory)
    let path = directory / "policy"
    writeFile(path, zipPackage([("main.js", repeat(' ', PolicyBytes + 1))]))
    validatePolicyUpload(path)
    writeFile(path, repeat(' ', PolicyBytes + 1))
    expect PolicyError: validatePolicyUpload(path)
