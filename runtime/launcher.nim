import
  std/[asyncjs, jsffi, json],
  nodeBridge,
  policies, rules, worldFixture

const TemplatePath = "/opt/screeps/node_modules/@screeps/launcher/init_dist/db.json"

var
  children: seq[JsObject]
  modules: array[2, JsonNode]
  stopping = false

proc exitProcess(code: int) {.importjs: "process.exit(#)".} =
  ## Exit the trusted launcher.

proc shutdown(code: int, message = "") =
  ## Clean up only this episode's children.
  if stopping: return
  stopping = true
  if message.len > 0:
    publishJson("/episode/failure.json", %*{"message": message})
  for child in children: discard child.kill("SIGTERM")
  exitProcess(code)

proc startChild(name, path: string): JsObject =
  ## Keep official process output separate from public game logs.
  let fd = fs.openSync(cstring("/episode/internal/" & name & ".log"), "a")
  let options = newJsObject()
  options.stdio = toJs(%*["ignore", fd.to(int), fd.to(int), "ipc"])
  result = require("child_process").spawn(process.execPath,
    toJs(%*["--no-node-snapshot", path]), options)
  fs.closeSync(fd)
  children.add result
  result.on("error", proc(error: JsObject) =
    ## Fail explicitly on worker startup errors.
    shutdown(2, name & " startup failed")
  )
  result.on("exit", proc(code, signal: JsObject) =
    ## Reject unexpected engine exits.
    if not stopping: shutdown(2, name & " exited unexpectedly")
  )
  result.on("message", proc(message: JsObject) =
    ## Finish outputs before publishing normal results.
    if jsTypeOf(message) != "object".cstring or message.finished.isNil: return
    if message.error.to(cstring).len > 0:
      shutdown(2, $message.error.to(cstring))
    else:
      let seats = readJson("/episode/seats.json")
      if seats.hasKey("seats"):
        for seat in seats["seats"]:
          let path = seat["log_uri"].getStr
          discard fs.copyFileSync(cstring("/episode/private/seat-" & $seat["slot"].getInt & ".log"),
            cstring(path[7..^1]))
      if seats.hasKey("player_status_uri"):
        let path = seats["player_status_uri"].getStr
        var status = %*{"schema_version": "1", "players": []}
        for slot in 0..1:
          status["players"].add %*{"slot": slot, "state": "exited", "exit_code": 0,
            "reason": "EpisodeCompleted"}
        publishJson(cstring(path[7..^1]), status)
      publishJson(envValue("PW_RESULTS"), readJson("/episode/completed.json"))
      shutdown(0)
  )

proc launch(): Future[void] {.async.} =
  ## Stage the world and policies, then start the single official engine process.
  try:
    let config = readJson("/episode/config.json")
    validateConfig(config)
    for slot in 0..1:
      try:
        modules[slot] = loadPolicy(cstring("/episode/input/seat" & $slot & "/policy"))
      except PolicyError as error:
        let failure = %*{"failed_policy_index": slot, "message": error.msg}
        publishJson("/episode/player_failure.json", failure)
        let failureUri = envValue("COGAME_PLAYER_FAILURE_URI")
        if not failureUri.isNil and failureUri.len > 0:
          proc filePath(value: cstring): cstring {.importjs: "require('url').fileURLToPath(#)".} =
            ## Resolve the trusted platform's failure artifact URI.
          publishJson(filePath(failureUri), failure)
        raise
    let db = smallWorld(readJson(TemplatePath))
    for collection in db["collections"]:
      if collection["name"].getStr == "env":
        collection["data"][0]["data"]["mainLoopPaused"] = %"1"
    writeText("/world/db.json", cstring($db))
    setEnv("DB_PATH", "/world/db.json")
    setEnv("MODFILE", "/episode/mods.json")
    setEnv("DRIVER_MODULE", "@screeps/driver")
    # Matches have two players, so run both seats concurrently. Control tags each run
    # result with its account and lets the first run settle before others start,
    # because the official accessibleRooms cache returns undefined to a run that starts
    # during its first fetch. Keep both in place if this changes.
    setEnv("RUNNER_THREADS", "2")
    publishJson("/world/modules.json", %modules)
    discard startChild("engine", $require("path").join(jsDirname, "engine.js").to(cstring))
  except:
    shutdown(2, getCurrentExceptionMsg())

process.on("SIGTERM", proc() =
  ## Stop workers when the host cancels the match.
  shutdown(130, "Episode cancelled")
)
discard launch()
