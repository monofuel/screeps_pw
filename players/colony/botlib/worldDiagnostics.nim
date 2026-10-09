import
  std/jsffi,
  screeps_lib

const
  HealthVersion = 1
  MaxErrorMessage = 512
  MaxErrorContext = 96

proc worldHealthState*(): JsObject =
  ## Initialize bounded health state without retaining game objects or history.
  let root = memory.toJs
  if root["worldHealth"].isNil:
    root["worldHealth"] = newJsObject()
  result = root["worldHealth"]
  result["version"] = HealthVersion
  if result["errors"].isNil:
    result["errors"] = 0
  if result["rooms"].isNil:
    result["rooms"] = newJsObject()

proc recordFailure*(context, message: string) =
  ## Log a caught failure and retain its bounded details and lifetime count.
  echo context, " failed: ", message
  let
    health = worldHealthState()
    failure = newJsObject()
  health["errors"] = health["errors"].to(int) + 1
  failure["tick"] = game.time
  failure["context"] = cstring(context[0 ..< min(context.len, MaxErrorContext)])
  failure["message"] = cstring(message[0 ..< min(message.len, MaxErrorMessage)])
  health["lastError"] = failure
