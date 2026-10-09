import
  std/[asyncjs, jsffi, json, tables],
  nodeBridge, turnScheduler,
  rules,
  ./[recording, timing]

var
  initialized = false
  opening: array[2, float]
  configFile: JsonNode
  accounts: array[2, cstring]

proc number(value: JsObject): float {.importjs: "Number(#)".} =
  ## Read an upstream numeric value without a JSON round trip.

proc pair(first, second: float): JsObject {.importjs: "[#, #]".} =
  ## Build the per-tick score array natively.

proc points(users: JsObject): array[2, float] =
  ## Resolve authoritative accounts in roster order.
  for slot in 0..1:
    var found = false
    for index in 0 ..< users.length.to(int):
      let user = users[index]
      if user["_id"].to(cstring) == accounts[slot]:
        result[slot] = number(user.gcl)
        found = true
    rules.require(found, "Missing tournament account")

proc stop(error = "") : Future[void] {.async.} =
  ## Pause advancement before notifying the launcher.
  discard await envSet("mainLoopPaused", toJs(%"1"))
  process.send(toJs(%*{"finished": true, "error": error}))

proc completed(): Future[void] {.async.} =
  ## Observe committed turns and finalize the fixed match length.
  try:
    if not initialized:
      configFile = readJson("/episode/config.json")
      let roster = readJson("/episode/roster.json")
      for slot in 0..1: accounts[slot] = cstring(roster[slot]["user"].getStr)
      let initial = readJson("/episode/initial.json")
      opening = points(toJs(initial["users"]))
      beginRecording(readJson("/episode/metadata.json"), initial["terrain"])
      record(0, toJs(initial["objects"]), pair(0, 0))
      initialized = true
    let tick = int(number(await envGet("gameTime"))) - 1
    rules.require(tick >= 1 and tick <= MatchTicks, "Completed turn outside tournament horizon")
    let closing = points(await find("users", newJsObject()))
    let objects = await find("rooms.objects", newJsObject())
    record(tick, objects, pair(closing[0] - opening[0], closing[1] - opening[1]))
    if tick == 1 or tick mod 100 == 0:
      publishJson("/episode/progress.json", %*{"ticks": tick})
    if tick == MatchTicks:
      let verdict = matchResult(opening, closing, tick, configFile["seed"].getInt)
      finishRecording($envValue("PW_REPLAY"), verdict)
      publishJson("/episode/progress.json", %*{"ticks": tick})
      publishJson("/episode/completed.json", verdict)
      await stop()
  except:
    await stop(getCurrentExceptionMsg())

proc objectType(value: JsObject): bool {.importjs: "(typeof # === 'object')".} =
  ## Identify official run results that can carry their account.

proc rejected(error: JsObject): JsObject {.importjs: "Promise.reject(#)".} =
  ## Preserve an official run failure after tagging it.

proc callWith(function, argument: JsObject): JsObject {.importjs: "#(#)".} =
  ## Call the official runtime builder.

proc tagRuns() =
  ## Attribute each concurrent seat's run result to its account.
  ## The official accessibleRooms cache returns undefined to runs that start while its
  ## first fetch is pending, so later runs wait until the first run has settled.
  let driver = require("@screeps/driver")
  let original = driver.makeRuntime
  var first: JsObject
  driver.makeRuntime = proc(userId: JsObject): JsObject =
    let user = userId.to(cstring)
    var running: JsObject
    if first.isNil:
      running = callWith(original, userId)
      first = running.then(proc(value: JsObject) = discard, proc(error: JsObject) = discard)
    else:
      running = first.then(proc(): JsObject = callWith(original, userId))
    running.then(proc(value: JsObject): JsObject =
      if not value.isNil and objectType(value): value.pwUser = user
      value
    , proc(error: JsObject): JsObject =
      if not error.isNil and objectType(error): error.pwUser = user
      rejected(error)
    )

proc install(config: JsObject) =
  ## Install trusted tournament hooks through the official mod interface.
  if not config.hasOwnProperty("engine"): return
  installTiming(config)
  config.engine.mainLoopMinDuration = 1
  installLoopScheduler(config, nodeTimers)
  tagRuns()
  config.engine.mainLoopCustomStage = completed
  var logs = initTable[cstring, cstring]()
  config.engine.on("runnerLoopStage", proc(stage: cstring, value: JsObject) =
    ## Route submitted console output only to its private log.
    if stage != "saveResultStart": return
    if logs.len == 0:
      for account in readJson("/episode/roster.json"):
        logs[cstring(account["user"].getStr)] = cstring(account["log"].getStr)
    let user = value.pwUser.to(cstring)
    rules.require(logs.hasKey(user), "Run result has no tournament account")
    let path = logs[user]
    let length = fs.statSync(path).size.to(int)
    if length >= LogBytes: return
    if value.error.isNil and value.console.isNil: return
    if value.error.isNil and not value.console.isNil and
        value.console.log.length.to(int) == 0 and value.console.results.length.to(int) == 0: return
    let entry = newJsObject()
    entry.error = if value.error.isNil: jsNull else: value.error
    entry.console = if value.console.isNil: jsNull else: value.console
    let bytes = require("buffer").Buffer.from(stringify(entry) & "\n", "utf8")
    if length + bytes.length.to(int) > LogBytes:
      appendText(path, "[log truncated at 10 MiB]\n")
    else:
      discard fs.appendFileSync(path, bytes)
  )

var module {.importc, nodecl.}: JsObject
module.exports = install
