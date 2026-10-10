import
  std/[jsffi, json, tables],
  nodeBridge

type Totals = object
  count: int
  ms: float

var
  stages: Table[string, Totals]
  requests: Table[string, Totals]
  current: Table[string, (string, float)]
  finishes = 0
  path: cstring

proc now(): float {.importjs: "performance.now()".} =
  ## Read a monotonic clock for diagnostic durations.

proc add(table: var Table[string, Totals], key: string, ms: float) =
  let entry = addr table.mgetOrPut(key, Totals())
  inc entry.count
  entry.ms += ms

proc flush() =
  ## Publish cumulative totals for the current process.
  var report = %*{"finishes": finishes, "stages": {}, "requests": {}}
  for key, value in stages: report["stages"][key] = %*{"count": value.count, "ms": value.ms}
  for key, value in requests: report["requests"][key] = %*{"count": value.count, "ms": value.ms}
  publishJson(path, report)

proc track(config: JsObject, event: string) =
  ## Attribute time between consecutive stage events to the earlier stage.
  config.engine.on(cstring(event), proc(stage: cstring) =
    let at = now()
    if current.hasKey(event):
      let (previous, started) = current[event]
      stages.add(event & ":" & previous, at - started)
    current[event] = ($stage, at)
    if stage == "finish":
      inc finishes
      if finishes mod 100 == 0: flush()
  )

proc requestKey(name: cstring, arguments: JsObject): string =
  ## Group storage calls by method and, for collection calls, by collection.
  result = $name
  if result in ["dbRequest", "dbUpdate", "dbBulk", "dbFindEx"]:
    result &= ":" & $arguments[0].to(cstring)
  if result.len > 9 and result[0..8] == "dbRequest":
    result &= ":" & $arguments[1].to(cstring)

proc wrapRequests() =
  ## Measure storage calls at the in-process storage dispatcher.
  let storage = common.storage
  let original = storage.localRequest
  proc callWith(function: JsObject, name: cstring, arguments: JsObject): JsObject {.importjs: "#(#, #)".}
  proc settle(promise: JsObject, done: proc()): JsObject {.importjs: "#.finally(#)".}
  storage.localRequest = proc(name: cstring, arguments: JsObject): JsObject =
    let key = requestKey(name, arguments)
    let started = now()
    settle(callWith(original, name, arguments), proc() =
      requests.add(key, now() - started)
    )

proc installTiming*(config: JsObject) =
  ## Record per-process stage and storage timing when PW_TIMING is set.
  let enabled = envValue("PW_TIMING")
  if enabled.isNil or enabled != "1": return
  path = episodePath("internal/timing.json")
  wrapRequests()
  for event in ["mainLoopStage", "runnerLoopStage", "processorLoopStage"]:
    track(config, event)
  process.on("exit", proc() = flush())
