import
  std/[asyncjs, jsffi, json],
  ./nativeJson

let
  fs* = require("fs")
  common* = require("@screeps/common")
  process* {.importc, nodecl.}: JsObject

proc readText*(path: cstring): cstring {.importjs: "require('fs').readFileSync(#, 'utf8')".} =
  ## Read a file through Node without introducing project JavaScript.

proc writeText*(path, value: cstring) {.importjs: "require('fs').writeFileSync(#, #)".} =
  ## Write a UTF-8 artifact.

proc appendText*(path, value: cstring) {.importjs: "require('fs').appendFileSync(#, #)".} =
  ## Append a diagnostic record atomically through Node.

proc exists*(path: cstring): bool {.importjs: "require('fs').existsSync(#)".} =
  ## Check whether an artifact has been written.

proc renameFile*(source, destination: cstring) {.importjs: "require('fs').renameSync(#, #)".} =
  ## Publish a completed artifact through an atomic rename.

proc stringify*(value: JsObject): cstring {.importjs: "JSON.stringify(#)".} =
  ## Serialize an upstream value for Nim's JSON parser.

proc parseJs(value: cstring): JsObject {.importjs: "JSON.parse(#)".} =
  ## Decode JSON for an upstream interface.

proc toJs*(value: JsonNode): JsObject =
  ## Convert validated Nim JSON into an upstream object.
  parseJs(cstring($value))

proc toJson*(value: JsObject): JsonNode =
  ## Convert an upstream value into Nim JSON.
  parseRuntimeJson(stringify(value))

proc readJson*(path: cstring): JsonNode =
  ## Decode an artifact without converting the complete input text to Nim bytes.
  parseRuntimeJson(readText(path))

proc sha256*(value: cstring): cstring {.importjs: "require('crypto').createHash('sha256').update(#).digest('hex')".} =
  ## Hash exact input bytes using Node's standard crypto module.

proc envValue*(name: cstring): cstring {.importjs: "process.env[#]".} =
  ## Read a runtime setting passed to the official engine.

proc setEnv*(name, value: cstring) {.importjs: "process.env[#] = #".} =
  ## Set an environment variable inherited by child processes.

proc nowMs*(): float {.importjs: "Date.now()".} =
  ## Read wall-clock time for diagnostic durations.

proc envGet*(name: cstring): Future[JsObject] =
  ## Read an official storage environment value.
  common.storage.env.get(name).to(Future[JsObject])

proc envSet*(name: cstring, value: JsObject): Future[JsObject] =
  ## Write an official storage environment value.
  common.storage.env.set(name, value).to(Future[JsObject])

proc find*(collection: cstring, query: JsObject): Future[JsObject] =
  ## Query an official database collection.
  proc invoke(target, query: JsObject): Future[JsObject] {.importjs: "#.find(#)".} =
    ## Call the upstream method without Nim's sequence search overload.
  invoke(common.storage.db[collection], query)

proc update*(collection: cstring, query, changes: JsObject): Future[JsObject] =
  ## Update records through the official database interface.
  proc invoke(target, query, changes: JsObject): Future[JsObject] {.importjs: "#.update(#, #)".} =
    ## Call the upstream database method.
  invoke(common.storage.db[collection], query, changes)

proc removeWhere*(collection: cstring, query: JsObject): Future[JsObject] =
  ## Remove records only in the disposable benchmark database.
  proc invoke(target, query: JsObject): Future[JsObject] {.importjs: "#.removeWhere(#)".} =
    ## Call the upstream database method.
  invoke(common.storage.db[collection], query)

proc clear*(collection: cstring): Future[JsObject] =
  ## Clear a disposable collection through the official interface.
  proc invoke(target: JsObject): Future[JsObject] {.importjs: "#.clear()".} =
    ## Call the upstream database method.
  invoke(common.storage.db[collection])

proc insert*(collection: cstring, item: JsObject): Future[JsObject] =
  ## Insert one declared object in a disposable benchmark fixture.
  proc invoke(target, item: JsObject): Future[JsObject] {.importjs: "#.insert(#)".} =
    ## Call the upstream collection method.
  invoke(common.storage.db[collection], item)

proc connectImpl(storage: JsObject): Future[JsObject] {.importjs: "#._connect()".} =
  ## Call the upstream connection method through its storage object.

proc connectStorage*(): Future[JsObject] =
  ## Connect to the official storage process.
  connectImpl(common.storage)

proc publishJson*(path: cstring, value: JsonNode) =
  ## Publish JSON only after its full contents are written.
  let temporary = path & ".tmp"
  writeText(temporary, cstring($value & "\n"))
  renameFile(temporary, path)
