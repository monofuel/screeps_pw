import
  std/[os, strutils, uri],
  mummy,
  rules

var root: string

proc handler(request: Request) {.gcsafe.} =
  ## Serve local replay assets on loopback for browser verification.
  {.cast(gcsafe).}:
    let relative = decodeUrl(request.uri.split('?')[0]).strip(chars = {'/'})
    let path = root / (if relative.len == 0: "index.html" else: relative)
    if ".." in relative or not fileExists(path):
      request.respond(404, body = "Not found")
      return
    let contentType = case path.splitFile.ext
      of ".html": "text/html"
      of ".js": "text/javascript"
      of ".wasm": "application/wasm"
      of ".png": "image/png"
      else: "application/octet-stream"
    request.respond(200, @[("Content-Type", contentType), ("Cache-Control", "no-store")], readFile(path))

proc main() =
  ## Run an opt-in local static replay server without launching a browser.
  require(paramCount() in 1..2, "Usage: serve DIRECTORY [PORT]")
  root = absolutePath(paramStr(1))
  let port = if paramCount() == 2: parseInt(paramStr(2)) else: 8769
  echo "Replay viewer: http://127.0.0.1:", port
  newServer(handler, workerThreads = 2).serve(Port(port), "127.0.0.1")

main()
