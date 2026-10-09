import
  std/jsffi

proc extra(): int =
  ## Provide an independently loaded JavaScript helper module.
  1

var module {.importc, nodecl.}: JsObject
module.exports.extra = extra
