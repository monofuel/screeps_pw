import
  std/[atomics, json, os, osproc, streams, strutils, uri],
  mummy,
  rules

var phase: Atomic[int]

proc filePath*(value: string): string =
  ## Accept only local file artifacts from the episode runner.
  let parsed = parseUri(value)
  require(parsed.scheme == "file" and parsed.hostname.len == 0 and parsed.path.isAbsolute,
    "Episode artifacts must be absolute file URIs")
  decodeUrl(parsed.path)

proc publish(path: string, value: JsonNode) =
  ## Atomically publish a completed JSON artifact.
  writeFile(path & ".tmp", $value & "\n")
  moveFile(path & ".tmp", path)

proc prepareEpisode() =
  ## Stage verified policies and equal tournament inputs.
  let config = parseFile(filePath(getEnv("COGAME_CONFIG_URI")))
  validateConfig(config)
  let seats = parseFile(filePath(getEnv("COGAME_PLAYER_SEATS_URI")))
  require(seats["schema"].getStr in ["coworld-player-seats/1", "coworld-player-seats/2"] and
    seats["seats"].len == 2, "Expected two game-hosted seats")
  for directory in ["input", "private", "internal"]: createDir("/episode" / directory)
  for slot in 0..1:
    let seat = seats["seats"][slot]
    require(seat["slot"].getInt == slot, "Seat order mismatch")
    let log = filePath(seat["log_uri"].getStr)
    writeFile(log, "")
    writeFile("/episode/private/seat-" & $slot & ".log", "")
  for slot in 0..1:
    let seat = seats["seats"][slot]
    let policy = filePath(seat["file_uri"].getStr)
    if not fileExists(policy) or getFileSize(policy) notin 1..PolicyBytes:
      publish(filePath(getEnv("COGAME_PLAYER_FAILURE_URI")), %*{
        "failed_policy_index": slot, "message": "Policy must contain 1 to 2097152 bytes"})
      raise newException(ValueError, "Invalid player file")
    createDir("/episode/input/seat" & $slot)
    copyFile(policy, "/episode/input/seat" & $slot / "main.js")
  writeFile("/episode/config.json", $config)
  writeFile("/episode/seats.json", $seats)
  writeFile("/episode/mods.json", $(%*{"mods": ["/app/runtime/control.js"],
    "bots": {"seat0": "/episode/input/seat0", "seat1": "/episode/input/seat1"}}))
  var hashes = newJArray()
  for seat in seats["seats"]: hashes.add seat["content_hash"]
  writeFile("/episode/metadata.json", $(%*{"version": 1, "config": config,
    "policySha256": hashes, "cpu": 20, "initialBucket": 0,
    "release": parseFile("/app/release.json")}))
  putEnv("PW_REPLAY", filePath(getEnv("COGAME_SAVE_REPLAY_URI")))
  putEnv("PW_RESULTS", filePath(getEnv("COGAME_RESULTS_URI")))

proc runEpisode() {.thread.} =
  ## Supervise the engine without imposing an internal wall-clock cutoff.
  let child = startProcess("node", args = @["/app/runtime/launcher.js"],
    options = {poUsePath, poStdErrToStdOut})
  let output = child.outputStream.readAll()
  let code = child.waitForExit()
  child.close()
  writeFile("/episode/internal/launcher.log", output)
  if code != 0:
    phase.store(3)
    stderr.writeLine("Screeps episode failed; private diagnostics retained")
    quit(code)
  phase.store(2)

proc requestHandler(request: Request) {.gcsafe.} =
  ## Serve the Coworld lifecycle surface without exposing policy output.
  case request.uri.split('?')[0]
  of "/healthz": request.respond(200, body = "ready")
  of "/client/global":
    request.respond(200, @[ ("Content-Type", "text/html; charset=utf-8") ],
      "<!doctype html><title>Screeps PW</title><p>The match runs at full speed. Open its completed replay to watch.</p>")
  of "/global": discard request.upgradeToWebSocket()
  else: request.respond(501, body = "Use the static replay viewer")

proc websocketHandler(socket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
  ## Honor the platform status and WebSocket liveness contract.
  case event
  of OpenEvent: socket.send("{\"game\":\"screeps-pw\",\"phase\":" & $phase.load() & "}")
  of MessageEvent:
    if message.kind == Ping: socket.send(message.data, Pong)
  of ErrorEvent, CloseEvent: discard

proc main() =
  ## Start the game-hosted lifecycle server and one isolated engine episode.
  prepareEpisode()
  phase.store(1)
  var worker: Thread[void]
  createThread(worker, runEpisode)
  let server = newServer(requestHandler, websocketHandler, workerThreads = 2)
  server.serve(Port(parseInt(getEnv("COGAME_PORT", "8080"))), getEnv("COGAME_HOST", "0.0.0.0"))

when isMainModule: main()
