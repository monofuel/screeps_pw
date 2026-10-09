import
  std/jsffi

let nodeTimers* {.importc: "globalThis", nodecl.}: JsObject

proc invoke(callback, receiver, arguments: JsObject): JsObject {.importjs: "#.apply(#, #)".} =
  ## Preserve the timer receiver and every supplied callback argument.

proc argumentArray(arguments: JsObject): JsObject {.importjs: "Array.from(#)".} =
  ## Copy only the intercepted engine timer's arguments.

proc installLoopScheduler*(config, timers: JsObject) =
  ## Start the official coordinator, runner, and processor loops again without timed sleeps.
  ## Node rounds setTimeout(loop, 0) up to about 1 ms, which otherwise dominates short turns.
  let timeout = timers.setTimeout
  let immediate = timers.setImmediate
  timers.setTimeout = proc(): JsObject =
    ## Forward unrelated timers unchanged.
    let arguments = jsArguments
    if jsTypeOf(arguments[0]) == "function" and arguments[0].name.to(cstring) == "loop".cstring and
        arguments[1].to(float) <= config.engine.mainLoopMinDuration.to(float):
      let forwarded = argumentArray(arguments)
      discard forwarded.splice(1, 1)
      return invoke(immediate, timers, forwarded)
    invoke(timeout, timers, arguments)
