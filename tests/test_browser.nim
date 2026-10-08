import
  std/[base64, json, os, times],
  pixie,
  ../tools/browser,
  rules

proc click(browser: var Browser, x, y: int) =
  ## Send a real canvas mouse click through Chromium's input pipeline.
  discard browser.call("Input.dispatchMouseEvent", %*{"type": "mouseMoved", "x": x, "y": y})
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mousePressed", "button": "left", "clickCount": 1, "x": x, "y": y})
  sleep(100)
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mouseReleased", "button": "left", "clickCount": 1, "x": x, "y": y})
  sleep(200)

proc tick(browser: var Browser): int =
  ## Read the frame already reported to the public replay shell.
  browser.evaluate("Module.replayTick").getInt

proc main() =
  ## Verify visible drawing, clocks, transport, rooms, resize, and bad input.
  var browser = connectBrowser()
  defer: browser.close()
  discard browser.call("Emulation.setDeviceMetricsOverride", %*{
    "width": 1280, "height": 800, "deviceScaleFactor": 1, "mobile": false})
  let viewer = getEnv("SCREEPS_PW_VIEWER_URL",
    "http://127.0.0.1:8769/?test=" & $epochTime() & "#replay=demo.replay")
  discard browser.call("Page.navigate", %*{"url": viewer})
  sleep(1000)
  let deadline = epochTime() + 60
  while not browser.evaluate("document.querySelector('#status')?.hidden === true").getBool:
    require(epochTime() < deadline, "Viewer never reported ready")
    sleep(250)
  let first = browser.tick()
  echo "Browser viewport: ", browser.evaluate("[innerWidth,innerHeight,Module.canvas.width,Module.canvas.height]")
  sleep(2000)
  require(browser.tick() - first in 17..23, "Default playback is not ten ticks per second")
  browser.click(174, 742)
  echo "After pause: ", browser.evaluate("[Module.replayTick,innerHeight]")
  let paused = browser.tick()
  sleep(1000)
  require(browser.tick() == paused, "Pause continued advancing")
  browser.click(240, 742)
  require(browser.tick() == paused + 1, "Single-step did not advance exactly one tick")
  browser.click(30, 742)
  require(browser.tick() == 0, "Seek to tick zero failed")
  browser.click(315, 742)
  require(browser.tick() == 6000, "Seek to final frame failed")
  browser.click(638, 778)
  require(browser.tick() in 2950..3050, "Timeline seek failed")
  browser.click(460, 742)
  browser.click(174, 742)
  let normal = browser.tick()
  sleep(2000)
  require(browser.tick() - normal in 1..3, "Normal playback is not one tick per second")
  browser.click(1108, 104)
  let screenshot = browser.call("Page.captureScreenshot", %*{"format": "png"})
  let path = getHomeDir() / ".local/share/screeps-pw/viewer-verified.png"
  writeFile(path, decode(screenshot["data"].getStr))
  let picture = readImage(path)
  var visible = 0
  for pixel in picture.data:
    if pixel.r > 30 or pixel.g > 30 or pixel.b > 40: inc visible
  require(visible > picture.width * picture.height div 20, "Replay canvas is blank")
  discard browser.call("Emulation.setDeviceMetricsOverride", %*{
    "width": 960, "height": 600, "deviceScaleFactor": 1, "mobile": false})
  sleep(500)
  require(browser.evaluate("Module.canvas.width").getInt == 960, "Canvas did not resize")
  require(browser.evaluate("GL.currentContext.GLctx.getError()").getInt == 0, "WebGL reported an error")
  discard browser.call("Page.navigate", %*{"url": "http://127.0.0.1:8769/?test=" & $epochTime() & "#replay=missing.replay"})
  sleep(2000)
  require(browser.evaluate("document.querySelector('#status-detail').textContent.includes('HTTP 404')").getBool,
    "Missing replay did not display an error")
  echo "Browser checks passed; screenshot: ", path

main()
