import
  std/[os, tempfiles],
  rules,
  ./sdk

proc main() =
  ## Upload for an owned identity without changing the shared active player.
  require(paramCount() == 3, "Usage: playerUpload PLAYER_ID POLICY_FILE POLICY_NAME")
  let parent = getHomeDir() / ".local/share/screeps-pw/auth"
  createDir(parent)
  let directory = createTempDir("player-", "", parent)
  setFilePermissions(directory, {fpUserRead, fpUserWrite, fpUserExec})
  defer: removeDir(directory)
  let source = getEnv("SOFTMAX_CONFIG_DIR", getHomeDir() / ".softmax") / "credentials.yaml"
  copyFile(source, directory / "credentials.yaml")
  setFilePermissions(directory / "credentials.yaml", {fpUserRead, fpUserWrite})
  putEnv("SOFTMAX_CONFIG_DIR", directory)
  sdkRun(["player", "use", paramStr(1)])
  sdkRun(["upload-policy", "--file", absolutePath(paramStr(2)), "--name", paramStr(3)])

main()
