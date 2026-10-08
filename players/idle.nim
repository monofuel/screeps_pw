import
  std/jsffi

proc loop() =
  ## Provide the controlled idle opponent.
  discard

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
