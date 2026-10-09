import
  ./[common, match]

proc main() =
  ## Download the immutable public engine runtime used by league version 0.1.2.
  run(["docker", "pull", DefaultImage])

when isMainModule: main()
