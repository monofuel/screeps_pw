import
  std/[asyncjs, jsffi, json],
  nodeBridge, turnScheduler,
  rules,
  ./[recording, timing]

var
  scheduling: TurnScheduler
  initialized = false
  opening: array[2, float]
  configFile, roster: JsonNode
  currentUser: cstring

proc points(users: JsonNode): array[2, float] =
  ## Resolve authoritative accounts in roster order.
  for slot in 0..1:
    var found = false
    for user in users:
      if user["_id"] == roster[slot]["user"]:
        result[slot] = user["gcl"].getFloat
        found = true
    rules.require(found, "Missing tournament account")

proc stop(error = "") : Future[void] {.async.} =
  ## Pause advancement before notifying the launcher.
  discard await envSet("mainLoopPaused", toJs(%"1"))
  process.send(toJs(%*{"finished": true, "error": error}))

proc completed(): Future[void] {.async.} =
  ## Observe committed turns and finalize the exact declared horizon.
  try:
    if not initialized:
      configFile = readJson("/episode/config.json")
      roster = readJson("/episode/roster.json")
      let initial = readJson("/episode/initial.json")
      opening = points(initial["users"])
      beginRecording(readJson("/episode/metadata.json"), initial["terrain"])
      record(0, initial["objects"], %*[0, 0])
      initialized = true
    let tick = toJson(await envGet("gameTime")).getInt - 1
    rules.require(tick >= 1 and tick <= configFile["max_ticks"].getInt,
      "Completed turn outside tournament horizon")
    let closing = points(toJson(await find("users", toJs(%*{}))))
    let objects = toJson(await find("rooms.objects", toJs(%*{})))
    record(tick, objects, %*[closing[0] - opening[0], closing[1] - opening[1]])
    publishJson("/episode/progress.json", %*{"ticks": tick})
    if tick == configFile["max_ticks"].getInt:
      let verdict = matchResult(opening, closing, tick, configFile["max_ticks"].getInt,
        configFile["seed"].getInt)
      finishRecording($envValue("PW_REPLAY"), verdict)
      publishJson("/episode/completed.json", verdict)
      await stop()
  except:
    await stop(getCurrentExceptionMsg())

proc install(config: JsObject) =
  ## Install trusted tournament hooks through the official mod interface.
  if not config.hasOwnProperty("engine"): return
  installTiming(config)
  config.engine.mainLoopMinDuration = 1
  scheduling = installTurnScheduler(config, nodeTimers, process.argv[1].to(cstring))
  config.engine.mainLoopCustomStage = completed
  config.engine.on("runnerLoopStage", proc(stage: cstring, value: JsObject) =
    ## Route submitted console output only to its private log.
    if stage == "runUser":
      currentUser = value.to(cstring)
      return
    if stage != "saveResultStart": return
    let accounts = readJson("/episode/roster.json")
    for account in accounts:
      if currentUser != cstring(account["user"].getStr): continue
      let path = cstring(account["log"].getStr)
      let length = fs.statSync(path).size.to(int)
      if length >= LogBytes: return
      if value.error.isNil and value.console.isNil: return
      if value.error.isNil and not value.console.isNil and
          value.console.log.length.to(int) == 0 and value.console.results.length.to(int) == 0: return
      let line = cstring($(%*{"error": (if value.error.isNil: newJNull() else: toJson(value.error)),
        "console": (if value.console.isNil: newJNull() else: toJson(value.console))}) & "\n")
      let bytes = require("buffer").Buffer.from(line, "utf8")
      if length + bytes.length.to(int) > LogBytes:
        appendText(path, "[log truncated at 10 MiB]\n")
      else:
        discard fs.appendFileSync(path, bytes)
  )

var module {.importc, nodecl.}: JsObject
module.exports = install
