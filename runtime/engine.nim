import
  std/[asyncjs, jsffi, json],
  nodeBridge,
  rules,
  ./localStorage

const EnginePath = "/opt/screeps/node_modules/@screeps/engine/dist/"

proc prepare(modules: JsonNode): Future[void] {.async.} =
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

proc host(): Future[void] {.async.} =
  ## Run official storage, runner, processor, and coordinator in one process.
  try:
    let fixture = readText("/world/db.json")
    await installLocalStorage()
    discard require("@screeps/driver")
    common.configManager.load()
    common.configManager.load = proc() = discard
    await prepare(readJson("/world/modules.json"))
    let metadata = readJson("/episode/metadata.json")
    metadata["fixtureSha256"] = %($sha256(fixture))
    metadata["engineVersion"] = %($require("@screeps/engine/package.json").version.to(cstring))
    metadata["driverVersion"] = %($require("@screeps/driver/package.json").version.to(cstring))
    metadata["accounts"] = readJson("/episode/roster.json")
    publishJson("/episode/metadata.json", metadata)
    discard require(EnginePath & "runner.js")
    discard require(EnginePath & "processor.js")
    discard await envSet("mainLoopPaused", toJs(%"0"))
    discard require(EnginePath & "main.js")
  except:
    process.send(toJs(%*{"finished": true, "error": getCurrentExceptionMsg()}))

discard host()
