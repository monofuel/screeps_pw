import
  std/[base64, json, os, strutils, times],
  pixie,
  ../tools/browser,
  replays, rules

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

proc picture(browser: var Browser): Image =
  let screenshot = browser.call("Page.captureScreenshot", %*{"format": "png"})
  let path = getHomeDir() / ".local/share/screeps-pw/viewer-verified.png"
  writeFile(path, decode(screenshot["data"].getStr))
  readImage(path)

proc pixels(image: Image, x, y, width, height: int, red, green, blue: int): int =
  for row in y..<y + height:
    for col in x..<x + width:
      let pixel = image[col, row]
      if abs(pixel.r.int - red) <= 5 and abs(pixel.g.int - green) <= 5 and
          abs(pixel.b.int - blue) <= 5: inc result

proc difference(first, last: Image, x, y, width, height: int): int =
  for row in y..<y + height:
    for col in x..<x + width:
      if first[col, row] != last[col, row]: inc result

proc drag(browser: var Browser, x, y, targetX, targetY: int) =
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mouseMoved", "x": x, "y": y})
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mousePressed", "button": "left", "buttons": 1, "clickCount": 1, "x": x, "y": y})
  sleep(100)
  for step in 1..5:
    discard browser.call("Input.dispatchMouseEvent", %*{
      "type": "mouseMoved", "buttons": 1,
      "x": x + (targetX - x) * step div 5, "y": y + (targetY - y) * step div 5})
    sleep(50)
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mouseReleased", "button": "left", "clickCount": 1, "x": targetX, "y": targetY})
  sleep(200)

proc main() =
  ## Verify visible drawing, clocks, transport, rooms, resize, and bad input.
  var browser = connectBrowser()
  let horizon = parseInt(getEnv("SCREEPS_PW_REPLAY_TICKS", "6000"))
  var replay = openReplay(readFile(getEnv("SCREEPS_PW_REPLAY_FILE")))
  let compact = replay.header["terrain"].len == 16
  let startingRoom = replay.startingRoom()
  let initialBox = if compact:
      (669 + (4 - parseInt(startingRoom[1..1])) * 147,
        114 + (4 - parseInt(startingRoom[3..3])) * 147, 138, 138)
    else: (1145, 590, 60, 60)
  let targetBox = if compact: (964, 409, 138, 138) else: (720, 165, 60, 60)
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
  require(browser.tick() == horizon, "Seek to final frame failed")
  browser.click(638, 778)
  require(abs(browser.tick() - horizon div 2) <= max(horizon div 100, 5), "Timeline seek failed")
  browser.click(460, 742)
  browser.click(174, 742)
  let normal = browser.tick()
  sleep(2000)
  require(browser.tick() - normal in 1..3, "Normal playback is not one tick per second")
  browser.click(174, 742)
  let initial = browser.picture()
  require(initial.pixels(670, 114, 584, 584, 87, 99, 117) > 20000, "World terrain walls are missing")
  require(initial.pixels(670, 114, 584, 584, 42, 79, 58) > 1000, "World terrain swamps are missing")
  require(initial.pixels(initialBox[0], initialBox[1], initialBox[2], initialBox[3], 255, 237, 139) > 100,
    "Initial room outline is missing")
  browser.click(targetBox[0] + targetBox[2] div 2, targetBox[1] + targetBox[3] div 2)
  let switched = browser.picture()
  require(switched.pixels(targetBox[0], targetBox[1], targetBox[2], targetBox[3], 255, 237, 139) > 100,
    "Map click did not select the other room")
  require(switched.pixels(initialBox[0], initialBox[1], initialBox[2], initialBox[3], 255, 237, 139) == 0,
    "Previous room stayed selected")
  require(initial.difference(switched, 20, 120, 590, 580) > 1000, "Map selection did not switch the 3D room")
  discard browser.call("Input.dispatchMouseEvent", %*{
    "type": "mouseWheel", "x": 960, "y": 410, "deltaX": 0, "deltaY": -400})
  sleep(300)
  let zoomed = browser.picture()
  require(switched.difference(zoomed, 670, 114, 584, 584) > 10000, "World map did not zoom")
  require(switched.difference(zoomed, 20, 120, 590, 580) < 50, "Map wheel also moved the 3D camera")
  browser.drag(960, 410, 1050, 440)
  let panned = browser.picture()
  require(zoomed.difference(panned, 670, 114, 584, 584) > 10000, "World map did not pan")
  browser.click(1230, 90)
  browser.click(initialBox[0] + initialBox[2] div 2, initialBox[1] + initialBox[3] div 2)
  browser.drag(640, 400, 800, 400)
  let resized = browser.picture()
  require(resized.pixels(798, 350, 4, 100, 176, 185, 195) >= 140, "Pane divider did not resize")
  require(resized.pixels(816, 120, 440, 570, 87, 99, 117) > 10000, "Map terrain disappeared after pane resize")
  let path = getHomeDir() / ".local/share/screeps-pw/viewer-verified.png"
  var visible = 0
  for pixel in resized.data:
    if pixel.r > 30 or pixel.g > 30 or pixel.b > 40: inc visible
  require(visible > resized.width * resized.height div 20, "Replay canvas is blank")
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
