import
  std/[json, math]

const
  CompetitionTicks* = 6000
  PolicyBytes* = 2 * 1024 * 1024
  LogBytes* = 10 * 1024 * 1024
  WorldRooms* = ["W1N1", "W1N2", "W1N3", "W1N4",
    "W2N1", "W2N2", "W2N3", "W2N4",
    "W3N1", "W3N2", "W3N3", "W3N4",
    "W4N1", "W4N2", "W4N3", "W4N4"]
  StartRooms* = ["W3N3", "W2N2"]
  StartPositions* = [(37, 31), (17, 40)]

proc require*(condition: bool, message: string) =
  ## Reject invalid contracts in release builds.
  if not condition: raise newException(ValueError, message)

proc validateConfig*(config: JsonNode) =
  ## Require a finite two-seat episode.
  require(config.kind == JObject, "Config must be an object")
  require(config.hasKey("max_ticks") and config["max_ticks"].kind == JInt and
    config["max_ticks"].getInt in 1..CompetitionTicks, "max_ticks must be between 1 and 6000")
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
  require(ticks == horizon and horizon in 1..CompetitionTicks, "Incomplete match")
  var scores: array[2, float]
  for slot in 0..1:
    require(classify(opening[slot]) notin {fcNan, fcInf, fcNegInf} and
      classify(closing[slot]) notin {fcNan, fcInf, fcNegInf} and
      closing[slot] >= opening[slot], "Invalid account GCL measurement")
    scores[slot] = closing[slot] - opening[slot]
  let outcome = if scores[0] == scores[1]: "draw"
    elif scores[0] > scores[1]: "seat-0-wins" else: "seat-1-wins"
  %*{"scores": scores, "ticks": ticks, "seed": seed, "outcome": outcome}
