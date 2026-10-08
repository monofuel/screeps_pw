import
  std/jsffi

proc allocate(): JsObject {.importjs: "new ArrayBuffer(1073741824)".} =
  ## Request more memory than an account isolate permits.

proc loop() =
  ## Exercise the official memory guard independently of a busy loop.
  discard allocate()

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
