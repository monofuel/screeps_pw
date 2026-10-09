import
  std/[asyncjs, jsffi],
  nodeBridge

const
  CollectionMethods = [cstring"find", "findOne", "by", "clear", "count", "ensureIndex",
    "removeWhere", "insert"]
  QueueMethods = [(cstring"fetch", cstring"queueFetch"), ("add", "queueAdd"),
    ("addMulti", "queueAddMulti"), ("markDone", "queueMarkDone"),
    ("whenAllDone", "queueWhenAllDone"), ("reset", "queueReset")]
  EnvMethods = [(cstring"get", cstring"dbEnvGet"), ("mget", "dbEnvMget"), ("set", "dbEnvSet"),
    ("setex", "dbEnvSetex"), ("expire", "dbEnvExpire"), ("ttl", "dbEnvTtl"), ("del", "dbEnvDel"),
    ("hmget", "dbEnvHmget"), ("hmset", "dbEnvHmset"), ("hget", "dbEnvHget"), ("hset", "dbEnvHset"),
    ("sadd", "dbEnvSadd"), ("smembers", "dbEnvSmembers")]

var methods: JsObject

proc copied(value: JsObject): JsObject {.
  importjs: "((value) => value === undefined ? undefined : JSON.parse(JSON.stringify(value)))(#)".} =
  ## Give callers the same detached JSON copy the official RPC transport produced.

proc variadic(handler: proc(arguments: JsObject): JsObject): JsObject {.
  importjs: "(function(h) { return function() { return h(Array.from(arguments)); }; })(#)".} =
  ## Accept the official client's variable argument lists.

proc nextTick(callback: proc()) {.importjs: "process.nextTick(#)".} =
  ## Keep storage work and replies out of the caller's synchronous stack, as RPC did.

proc truthy(value: JsObject): bool {.importjs: "!!(#)".} =
  ## Match the RPC server's error check.

proc withCallback(arguments: JsObject, callback: proc(error, value: JsObject)): JsObject {.
  importjs: "#.concat([#])".} =
  ## Append the node-style reply callback used by the official storage methods.

proc applyMethod(function, arguments: JsObject) {.importjs: "#.apply(null, #)".} =
  ## Call an official storage method.

proc array(): JsObject {.importjs: "[@]".} =
  ## Build an empty argument list.

proc array(first, second: JsObject): JsObject {.importjs: "[#, #]".} =
  ## Build a two-item argument list.

proc array(first, second, third: JsObject): JsObject {.importjs: "[#, #, #]".} =
  ## Build a three-item argument list.

proc array(first, second, third, fourth: JsObject): JsObject {.importjs: "[#, #, #, #]".} =
  ## Build a four-item argument list.

proc request(name: cstring, arguments: JsObject): JsObject =
  ## Run one official storage method in-process with RPC copy and timing semantics.
  let deferred = require("q").`defer`()
  let input = copied(arguments)
  nextTick(proc() =
    applyMethod(methods[name], withCallback(input, proc(error, value: JsObject) =
      nextTick(proc() =
        if truthy(error): discard deferred.reject(copied(error))
        else: discard deferred.resolve(copied(value))
      )
    ))
  )
  deferred.promise

proc call(name: cstring, arguments: JsObject): JsObject =
  ## Dispatch through the storage object so diagnostics can observe each call.
  common.storage.localRequest(name, arguments)

proc forward(name: cstring): JsObject =
  ## Mirror an official client method that passes its arguments straight through.
  variadic(proc(arguments: JsObject): JsObject = call(name, arguments))

proc collectionMethod(name, operation: cstring): JsObject =
  ## Mirror one generic collection method of the official client.
  variadic(proc(arguments: JsObject): JsObject =
    call("dbRequest", array(toJs(name), toJs(operation), arguments)))

proc collection(name: cstring): JsObject =
  ## Mirror the official client's collection wrapper.
  result = newJsObject()
  for operation in CollectionMethods:
    result[operation] = collectionMethod(name, operation)
  result.update = proc(query, update, params: JsObject): JsObject =
    call("dbUpdate", array(toJs(name), query, update, params))
  result.bulk = proc(bulk: JsObject): JsObject =
    call("dbBulk", array(toJs(name), bulk))
  result.findEx = proc(query, options: JsObject): JsObject =
    call("dbFindEx", array(toJs(name), query, options))

proc installLocalStorage*(): Future[void] {.async.} =
  ## Load the official storage modules in this process and connect the official client to them.
  let storage = common.storage
  discard require("@screeps/storage/lib/index")
  let config = common.configManager.config
  config.storage.dbOptions = toJs(newJsObject())
  config.storage.dbOptions.autosave = false
  discard await config.storage.loadDb().to(Future[JsObject])
  let connection = require("@screeps/storage/lib/pubsub").create()
  proc assign(target, first, second, third: JsObject): JsObject {.importjs: "Object.assign(#, #, #, #)".}
  methods = assign(newJsObject(), require("@screeps/storage/lib/db"),
    require("@screeps/storage/lib/queue"), connection.methods)
  storage.localRequest = request
  for index in 0 ..< config.common.dbCollections.length.to(int):
    let name = config.common.dbCollections[index].to(cstring)
    storage.db[name] = collection(name)
  storage.resetAllData = proc(): JsObject = call("dbResetAllData", array())
  for (local, remote) in QueueMethods: storage.queue[local] = forward(remote)
  for (local, remote) in EnvMethods: storage.env[local] = forward(remote)
  storage.pubsub.publish = forward("publish")
  storage.pubsub.subscribe = proc(channel, callback: JsObject) =
    proc deliver(callback, channel, data: JsObject) {.importjs: "#.apply({channel: #}, [#])".}
    discard connection.methods.subscribe(channel, proc(message: JsObject) =
      let data = copied(message.data)
      let name = message.channel
      nextTick(proc() = deliver(callback, name, data))
    )
  storage["_connected"] = true
  storage["_connect"] = proc(): JsObject = require("q").`when`()
