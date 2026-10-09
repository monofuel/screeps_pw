import
  std/[json, math]

const
  # Largest max_ticks a match config may request.
  MaxTicks* = 8000
  # Length of competition matches and local runs that do not choose one.
  DefaultTicks* = 1500
  PolicyBytes* = 5 * 1024 * 1024
  PackageBytes* = 16 * 1024 * 1024
  ArchiveBytes* = 17 * 1024 * 1024
  PackageFiles* = 256
  PolicySizeMessage* = "Policy must contain 1 to " & $PolicyBytes & " bytes (5 MiB maximum)"
  LogBytes* = 10 * 1024 * 1024
  WorldRooms* = ["W1N1", "W1N2", "W1N3", "W1N4",
    "W2N1", "W2N2", "W2N3", "W2N4",
    "W3N1", "W3N2", "W3N3", "W3N4",
    "W4N1", "W4N2", "W4N3", "W4N4"]
  StartRooms* = ["W3N3", "W2N2"]
  StartPositions* = [(32, 9), (17, 40)]

type PolicyError* = object of ValueError

proc require*(condition: bool, message: string) =
  ## Reject invalid contracts in release builds.
  if not condition: raise newException(ValueError, message)

proc validPolicySize*(bytes: int64): bool =
  bytes in 1..PolicyBytes

proc validateConfig*(config: JsonNode) =
  ## Require a finite two-seat episode.
  require(config.kind == JObject, "Config must be an object")
  require(config.hasKey("max_ticks") and config["max_ticks"].kind == JInt and
    config["max_ticks"].getInt in 1..MaxTicks, "max_ticks must be between 1 and " & $MaxTicks)
  require(config.hasKey("seed") and config["seed"].kind == JInt and
    config["seed"].getBiggestInt in low(int32).BiggestInt..high(int32).BiggestInt,
    "seed must be a signed 32-bit integer")
  for key in ["tokens", "players"]:
    require(config.hasKey(key) and config[key].kind == JArray and config[key].len == 2,
      key & " must contain two seats")
  for token in config["tokens"]:
    require(token.kind == JString and token.getStr.len > 0, "Empty seat token")
  for player in config["players"]:
    require(player.kind == JObject and player.hasKey("name") and
      player["name"].kind == JString and player["name"].getStr.len > 0, "Missing player name")

proc matchResult*(opening, closing: array[2, float], ticks, horizon, seed: int): JsonNode =
  ## Score only a completed horizon using cumulative account points.
  require(ticks == horizon and horizon in 1..MaxTicks, "Incomplete match")
  var scores: array[2, float]
  for slot in 0..1:
    require(classify(opening[slot]) notin {fcNan, fcInf, fcNegInf} and
      classify(closing[slot]) notin {fcNan, fcInf, fcNegInf} and
      closing[slot] >= opening[slot], "Invalid account GCL measurement")
    scores[slot] = closing[slot] - opening[slot]
  let outcome = if scores[0] == scores[1]: "draw"
    elif scores[0] > scores[1]: "seat-0-wins" else: "seat-1-wins"
  %*{"scores": scores, "ticks": ticks, "seed": seed, "outcome": outcome}
