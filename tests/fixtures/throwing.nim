import
  std/jsffi

proc loop() =
  ## Exercise private runtime diagnostics without terminating an episode.
  raise newException(ValueError, "PRIVATE_POLICY_SENTINEL")

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
