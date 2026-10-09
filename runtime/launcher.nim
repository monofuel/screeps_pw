import
  std/[asyncjs, jsffi, json],
  nodeBridge,
  policies, rules, worldFixture

const
  TemplatePath = "/opt/screeps/node_modules/@screeps/launcher/init_dist/db.json"
  EnginePath = "/opt/screeps/node_modules/@screeps/engine/dist/"

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

proc waitForStorage(child: JsObject): Future[void] =
  ## Await official storage readiness.
  newPromise(proc(resolve: proc()) =
    ## Resolve only the readiness event.
    child.on("message", proc(message: JsObject) =
      ## Handle the launcher's storage IPC message.
      if message.to(cstring) == "storageLaunched": resolve()
    )
  )

proc prepare(config: JsonNode): Future[void] {.async.} =
  ## Replace all starter colonies before the first turn.
  for user in toJson(await find("users", toJs(%*{}))):
    if not user.hasKey("bot"): continue
    let id = user["_id"]
    discard await removeWhere("rooms.objects", toJs(%*{"user": id, "type": {"$ne": "controller"}}))
    discard await update("rooms.objects", toJs(%*{"user": id, "type": "controller"}),
      toJs(%*{"$set": {"user": nil, "level": 0, "progress": 0,
        "safeMode": nil, "downgradeTime": nil, "reservation": nil}}))
    discard await removeWhere("users", toJs(%*{"_id": id}))
  discard await clear("users.code")
  discard await envSet("gameTime", toJs(%1))
  discard await envSet("tickRate", toJs(%1))
  discard await envSet("activeRooms", toJs(%*[]))
  var roster = newJArray()
  let bots = require("@screeps/backend/lib/cli/bots")
  for slot in 0..1:
    let username = "Seat" & $slot
    discard await bots.spawn(cstring("seat" & $slot), cstring(StartRooms[slot]),
      toJs(%*{"username": username, "cpu": 20, "gcl": 1,
        "x": StartPositions[slot][0], "y": StartPositions[slot][1]})).to(Future[JsObject])
    let account = toJson(await find("users", toJs(%*{"username": username})))[0]
    let stored = require("@screeps/backend/lib/utils").translateModulesToDb(toJs(modules[slot]))
    discard await update("users.code", toJs(%*{"user": account["_id"], "activeWorld": true}),
      toJs(%*{"$set": {"modules": toJson(stored)}}))
    discard await update("users", toJs(%*{"_id": account["_id"]}),
      toJs(%*{"$set": {"cpuAvailable": 0}, "$unset": {"bot": true}}))
    discard await update("rooms.objects", toJs(%*{"user": account["_id"], "type": "spawn"}),
      toJs(%*{"$set": {"store": {"energy": 300}}}))
    discard await update("rooms.objects", toJs(%*{"user": account["_id"], "type": "controller"}),
      toJs(%*{"$set": {"level": 1, "progress": 0}}))
    roster.add %*{"slot": slot, "user": account["_id"],
      "log": "/episode/private/seat-" & $slot & ".log"}
  publishJson("/episode/roster.json", roster)
  let driver = require("@screeps/driver")
  discard await driver.updateAccessibleRoomsList().to(Future[JsObject])
  discard await driver.updateRoomStatusData().to(Future[JsObject])
  discard await require("@screeps/backend/lib/cli/map").updateTerrainData().to(Future[JsObject])
  publishJson("/episode/initial.json", %*{
    "users": toJson(await find("users", toJs(%*{}))),
    "objects": toJson(await find("rooms.objects", toJs(%*{}))),
    "terrain": toJson(await find("rooms.terrain", toJs(%*{})))})

proc launch(): Future[void] {.async.} =
  ## Prepare storage and launch the official runner, processor, and coordinator.
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
    setEnv("STORAGE_PORT", "/world/storage.sock")
    setEnv("DB_PATH", "/world/db.json")
    setEnv("MODFILE", "/episode/mods.json")
    setEnv("DRIVER_MODULE", "@screeps/driver")
    setEnv("RUNNER_THREADS", "1")
    common.configManager.load()
    let storage = startChild("storage", "/opt/screeps/node_modules/@screeps/storage/bin/start.js")
    await waitForStorage(storage)
    discard await connectStorage()
    await prepare(config)
    let metadata = readJson("/episode/metadata.json")
    metadata["fixtureSha256"] = %($sha256(cstring($db)))
    metadata["engineVersion"] = %($require("@screeps/engine/package.json").version.to(cstring))
    metadata["driverVersion"] = %($require("@screeps/driver/package.json").version.to(cstring))
    metadata["accounts"] = readJson("/episode/roster.json")
    publishJson("/episode/metadata.json", metadata)
    discard startChild("runner", EnginePath & "runner.js")
    discard startChild("processor", EnginePath & "processor.js")
    discard await envSet("mainLoopPaused", toJs(%"0"))
    discard startChild("main", EnginePath & "main.js")
  except:
    shutdown(2, getCurrentExceptionMsg())

process.on("SIGTERM", proc() =
  ## Stop workers when the host cancels the match.
  shutdown(130, "Episode cancelled")
)
discard launch()
