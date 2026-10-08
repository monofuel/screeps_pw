import
  std/[json, os, strutils],
  curly,
  rules

const ApiRoot = "https://softmax.com/api/observatory"

proc credential(): string =
  ## Read the existing user credential without changing active-player state.
  let directory = getEnv("SOFTMAX_CONFIG_DIR", getHomeDir() / ".softmax")
  var tokens = false
  for line in readFile(directory / "credentials.yaml").splitLines():
    if line == "tokens:": tokens = true
    elif line.len > 0 and line[0] != ' ': tokens = false
    if tokens and line.strip().startsWith("https://softmax.com/api:"):
      result = line.strip()["https://softmax.com/api:".len..^1].strip().strip(chars = {'\'', '"'})
  require(result.len > 0, "No Softmax user credential found; use the official login command")

proc main() =
  ## Execute a scoped platform request without printing credentials.
  require(paramCount() in 2..4, "Usage: api METHOD /v2/PATH [JSON_FILE | --output FILE]")
  let methodName = paramStr(1)
  let path = paramStr(2)
  require(methodName in ["GET", "POST", "PUT"] and path.startsWith("/v2/"), "Unsupported API request")
  let download = paramCount() == 4
  require(not download or (methodName == "GET" and paramStr(3) == "--output"),
    "Downloads require GET /v2/PATH --output FILE")
  let body = if paramCount() == 3: readFile(paramStr(3)) else: ""
  let curl = newCurly()
  defer: curl.close()
  let response = curl.makeRequest(methodName, ApiRoot & path, @[
    ("Authorization", "Bearer " & credential()),
    ("X-Use-Elevated-Privileges", "true"),
    ("Content-Type", "application/json")], body, timeout = 120)
  if response.code notin 200..299:
    raise newException(IOError, "Platform HTTP " & $response.code & ": " & response.body)
  if download:
    writeFile(paramStr(4), response.body)
    echo "Downloaded " & $response.body.len & " bytes."
  elif response.body.len > 0:
    echo pretty(parseJson(response.body))

main()
