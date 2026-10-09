import
  std/os,
  ./common

proc sdkCommand*(arguments: openArray[string]): seq[string] =
  ## Invoke the upstream SDK in an isolated uv tool environment.
  let source = getEnv("COWORLD_SOURCE")
  if source.len == 0:
    result = @["uv", "tool", "run", "--from", "coworld[auth]==0.1.56", "coworld"]
    result.add arguments
    return
  if not dirExists(source): raise newException(IOError, "Set COWORLD_SOURCE to the pinned Coworld package")
  let revision = command(["git", "-C", source, "rev-parse", "HEAD"])
  if revision != "d9d2a9a91131e7ef2f7c9ef6ac35c53775a5a386":
    raise newException(ValueError, "Coworld SDK revision differs from the tested toolchain")
  let authSource = source.parentDir / "softmax-cli"
  if not dirExists(authSource): raise newException(IOError, "The pinned softmax-cli package must accompany Coworld")
  let overrides = Root / "build/auth-overrides.txt"
  createDir(overrides.parentDir)
  writeFile(overrides, "softmax-cli @ file://" & authSource & "\n")
  result = @["uv", "tool", "run", "--no-sources", "--overrides", overrides,
    "--from", source & "[auth]", "coworld"]
  result.add arguments

proc sdkRun*(arguments: openArray[string]) =
  ## Run upstream certification or release tooling without browser launching.
  var args = @arguments
  var directory = Root
  if args.len > 1 and args[0] == "certify":
    if not args[1].isAbsolute and fileExists(Root / args[1]): args[1] = Root / args[1]
    directory = getHomeDir() / ".local/share/screeps-pw/certification"
    createDir(directory)
  run(sdkCommand(args), directory)

when isMainModule:
  sdkRun(commandLineParams())
