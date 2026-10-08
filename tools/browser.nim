import
  std/[asyncdispatch, base64, json, os],
  curly, ws

type Browser* = object
  socket: WebSocket
  sequence: int

proc connectBrowser*(): Browser =
  ## Connect to an existing headless Chromium page on loopback.
  let curl = newCurly()
  defer: curl.close()
  let response = curl.get("http://127.0.0.1:8770/json/list", timeout = 10)
  if response.code != 200: raise newException(IOError, "Chromium debugging endpoint is unavailable")
  let pages = parseJson(response.body)
  var address: string
  for page in pages:
    if page["type"].getStr == "page": address = page["webSocketDebuggerUrl"].getStr
  if address.len == 0: raise newException(ValueError, "No headless Chromium page found on port 8770")
  result.socket = waitFor newWebSocket(address)

proc close*(browser: Browser) =
  ## Close the debugging connection without stopping Chromium.
  browser.socket.close()

proc call*(browser: var Browser, methodName: string, params: JsonNode): JsonNode =
  ## Wait for a matching response while discarding unsolicited events.
  inc browser.sequence
  waitFor browser.socket.send($(%*{"id": browser.sequence, "method": methodName, "params": params}))
  while true:
    let packet = browser.socket.receiveStrPacket()
    if not waitFor packet.withTimeout(30000): raise newException(IOError, "Chromium response timed out")
    let response = parseJson(packet.read())
    if response.getOrDefault("id").getInt == browser.sequence:
      if response.hasKey("error"): raise newException(ValueError, $response)
      return response["result"]

proc evaluate*(browser: var Browser, expression: string): JsonNode =
  ## Evaluate a diagnostic expression and retain JavaScript failures.
  let response = browser.call("Runtime.evaluate", %*{"expression": expression, "returnByValue": true})
  if response.hasKey("exceptionDetails"): raise newException(ValueError, $response)
  response["result"].getOrDefault("value")

proc main() =
  ## Inspect a headless Chromium tab over its local debugging protocol.
  var browser = connectBrowser()
  defer: browser.close()
  if paramCount() > 0:
    echo browser.evaluate(paramStr(1))
  else:
    let image = browser.call("Page.captureScreenshot", %*{"format": "png"})
    let path = getHomeDir() / ".local/share/screeps-pw/viewer-real.png"
    writeFile(path, decode(image["data"].getStr))
    echo path

when isMainModule: main()
