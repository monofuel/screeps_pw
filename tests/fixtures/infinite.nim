import
  std/jsffi

proc loop() =
  ## Exercise the official script execution guard.
  while true: discard

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
