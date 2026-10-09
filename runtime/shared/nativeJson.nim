import std/[jsffi, json]

proc parseNative(value: cstring): JsObject {.importjs: "JSON.parse(#)".} =
  ## Parse JSON without converting the complete input into a Nim byte string.

proc ownKeys(value: JsObject): seq[cstring] {.importjs: "Object.keys(#)".} =
  ## Enumerate the decoded object's own fields.

proc isArray(value: JsObject): bool {.importjs: "Array.isArray(#)".} =
  ## Distinguish native JSON arrays from objects.

proc safeInteger(value: JsObject): bool {.importjs: "Number.isSafeInteger(#)".} =
  ## Preserve the standard parser's representation of ordinary integers.

proc integer(value: JsObject): bool {.importjs: "Number.isInteger(#)".} =
  ## Identify integer tokens requiring Nim's raw-number representation.

proc negativeZero(value: JsObject): bool {.importjs: "Object.is(#, -0)".} =
  ## Preserve a negative zero parsed from artifact text.

proc convert(value: JsObject, requiresText: var bool): JsonNode =
  ## Copy the native parser's validated JSON tree directly into Nim.
  let kind = jsTypeOf(value)
  if value.isNil: result = newJNull()
  elif kind == "boolean".cstring: result = newJBool(value.to(bool))
  elif kind == "string".cstring: result = newJString($value.to(cstring))
  elif kind == "number".cstring:
    if negativeZero(value): result = newJFloat(-0.0)
    elif safeInteger(value): result = newJInt(value.to(int))
    elif integer(value):
      requiresText = true
      result = newJNull()
    else: result = newJFloat(value.to(float))
  elif isArray(value):
    result = newJArray()
    result.elems.setLen(value.length.to(int))
    for index in 0 ..< result.elems.len: result.elems[index] = convert(value[index], requiresText)
  else:
    result = newJObject()
    for key in ownKeys(value): result[$key] = convert(value[key], requiresText)

proc parseRuntimeJson*(value: cstring): JsonNode =
  ## Decode runtime values quickly and preserve exact text for unsafe integers.
  var decoded: JsObject
  try: decoded = parseNative(value)
  except: raise newException(JsonParsingError, getCurrentExceptionMsg())
  var requiresText = false
  result = convert(decoded, requiresText)
  if requiresText: result = parseJson($value)
