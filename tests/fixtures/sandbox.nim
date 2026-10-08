import
  std/jsffi

proc processKind(): cstring {.importjs: "String(typeof process)".} =
  ## Inspect process visibility inside the submitted script VM.

proc loop() =
  ## Check that submitted code cannot load host process or filesystem modules.
  if processKind() != "undefined".cstring:
    raise newException(ValueError, "HOST_PROCESS_EXPOSED")
  for name in ["fs", "process", "child_process", "net", "http"]:
    var blocked = false
    try: discard require(cstring(name))
    except: blocked = true
    if not blocked: raise newException(ValueError, "HOST_MODULE_EXPOSED")
  echo "SANDBOX_GUARDS_OK"

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
