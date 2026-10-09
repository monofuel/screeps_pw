import
  std/jsffi,
  botlib/worldMonitoring,
  ./worldStrategy

let strategy = newWorldStrategy()

proc worldLoop() =
  ## Run the colony strategy for one World tick.
  try:
    strategy.tick()
  except:
    recordFailure("World tick", getCurrentException().msg)
  try:
    updateWorldHealth()
  except:
    recordFailure("Health", getCurrentException().msg)

var module {.importc, nodecl.}: JsObject
module["exports"]["loop"] = worldLoop
