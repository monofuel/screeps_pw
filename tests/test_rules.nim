import
  std/[json, unittest],
  rules

suite "GCL race contract":
  test "Upload limit accepts large policies and rejects empty or oversized files":
    check not validPolicySize(0)
    check validPolicySize(2 * 1024 * 1024 + 1)
    check validPolicySize(5 * 1024 * 1024)
    check not validPolicySize(5 * 1024 * 1024 + 1)
  test "Grants are excluded and cumulative points survive level transitions":
    let result = matchResult([1000.0, 0.0], [1050.0, 40.0], 6000, 6000, 2026)
    check result["scores"] == %*[50.0, 40.0]
    check result["outcome"].getStr == "seat-0-wins"
  test "Equal scores draw":
    check matchResult([0.0, 1000.0], [0.0, 1000.0], 6000, 6000, 0)["outcome"].getStr == "draw"
  test "Prefixes cannot be scored as completed episodes":
    expect ValueError: discard matchResult([0.0, 0.0], [10.0, 20.0], 5999, 6000, 0)
  test "Lost cumulative points are rejected":
    expect ValueError: discard matchResult([10.0, 0.0], [0.0, 20.0], 6000, 6000, 0)
  test "Two accounts and bounded tick horizons are required":
    let config = %*{"tokens": ["a", "b"], "players": [{"name": "A"}, {"name": "B"}],
      "seed": 2026, "max_ticks": 6000}
    validateConfig(config)
    config["max_ticks"] = %6001
    expect ValueError: validateConfig(config)
