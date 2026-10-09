import
  std/os,
  ./[common, zipPackages]

proc main() =
  ## Build the public standalone example and its binary modules.
  for name in ["main", "helper"]: run(["nim", "js", "players/wasm/" & name & ".nim"])
  writeFile(Root / "build/players/wasm/brain.wasm", addWasm())
  writeFile(Root / "build/players/wasm/weights.bin", "\0\xff\x07")
  var files: seq[(string, string)]
  for name in ["main.js", "helper.js", "brain.wasm", "weights.bin"]:
    files.add (name, readFile(Root / "build/players/wasm" / name))
  writeFile(Root / "build/players/wasm.zip", zipPackage(files))

when isMainModule: main()
