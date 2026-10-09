import
  std/[os, osproc, net, strutils, tempfiles, times],
  replays, rules,
  ./common

proc available(port: int) =
  ## Fail before starting processes if a loopback test port is already occupied.
  let socket = newSocket()
  defer: socket.close()
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(port), "127.0.0.1")

proc main() =
  ## Run a disposable headless browser and static server for a full replay.
  if getEnv("SCREEPS_PW_BROWSER_TOOLCHAIN") != "1":
    run(@["nix", "develop", "path:" & Root, "--command", "env", "SCREEPS_PW_BROWSER_TOOLCHAIN=1",
      getAppFilename()] & commandLineParams())
    return
  rules.require(paramCount() == 1 and fileExists(paramStr(1)), "Usage: browserCheck MATCH_REPLAY")
  putEnv("SCREEPS_PW_REPLAY_TICKS", $openReplay(readFile(paramStr(1))).lastTick)
  available(8769)
  available(8770)
  let parent = getHomeDir() / ".local/share/screeps-pw/browser"
  createDir(parent)
  let directory = createTempDir("check-", "", parent)
  copyDir(Root / "dist/replay-viewer", directory / "viewer")
  copyFile(absolutePath(paramStr(1)), directory / "viewer/demo.replay")
  run(["nim", "c", "--out:" & Root / "build/serve", "tools/serve.nim"])
  run(["nim", "c", "--out:" & Root / "build/test_browser", "tests/test_browser.nim"])
  let server = startProcess(Root / "build/serve", args = @[directory / "viewer"], options = {poStdErrToStdOut})
  defer:
    server.terminate()
    discard server.waitForExit(5000)
    server.close()
  let chrome = startProcess("chromium", args = @["--headless", "--no-sandbox", "--disable-dev-shm-usage",
    "--disable-background-networking", "--disable-extensions", "--use-gl=angle", "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader", "--remote-debugging-port=8770", "--user-data-dir=" & directory / "profile",
    "--window-size=1280,800", "http://127.0.0.1:8769/"], options = {poUsePath, poStdErrToStdOut})
  defer:
    chrome.terminate()
    discard chrome.waitForExit(5000)
    chrome.close()
  let deadline = epochTime() + 20
  while true:
    let probe = newSocket()
    try:
      probe.connect("127.0.0.1", Port(8770), timeout = 100)
      probe.close()
      break
    except OSError:
      probe.close()
      rules.require(epochTime() < deadline and chrome.running(), "Headless Chromium never started")
      sleep(100)
  run([Root / "build/test_browser"])
  echo "Browser artifacts: ", directory

main()
