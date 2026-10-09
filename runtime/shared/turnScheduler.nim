import
  std/jsffi

type TurnScheduler* = ref object
  immediateTransitions*: int

let nodeTimers* {.importc: "globalThis", nodecl.}: JsObject

proc resolveModule*(path: cstring): cstring {.importjs: "require.resolve(#)".} =
  ## Identify the official coordinator without loading its entrypoint.

proc invoke(callback, receiver, arguments: JsObject): JsObject {.importjs: "#.apply(#, #)".} =
  ## Preserve the timer receiver and every supplied callback argument.

proc argumentArray(arguments: JsObject): JsObject {.importjs: "Array.from(#)".} =
  ## Copy only the intercepted coordinator timer's arguments.

proc installTurnScheduler*(config, timers: JsObject, entrypoint: cstring): TurnScheduler =
  ## Remove sleeps only between committed turns of the official coordinator.
  if not config.hasOwnProperty("engine") or
      entrypoint != resolveModule("@screeps/engine/dist/main.js"):
    return nil
  result = TurnScheduler()
  let stats = result
  let timeout = timers.setTimeout
  let immediate = timers.setImmediate
  var finished = false
  config.engine.on("mainLoopStage", proc(stage: cstring) =
    ## Arm the scheduler only after the completed-turn check has resolved.
    finished = stage == "finish"
  )
  timers.setTimeout = proc(): JsObject =
    ## Forward unrelated timers unchanged and yield without a timed sleep.
    let arguments = jsArguments
    if finished and jsTypeOf(arguments[0]) == "function" and arguments[0].name.to(cstring) == "loop".cstring and
        arguments[1].to(float) <= config.engine.mainLoopMinDuration.to(float):
      finished = false
      inc stats.immediateTransitions
      let forwarded = argumentArray(arguments)
      discard forwarded.splice(1, 1)
      return invoke(immediate, timers, forwarded)
    invoke(timeout, timers, arguments)
