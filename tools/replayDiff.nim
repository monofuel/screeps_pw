import
  std/[algorithm, json, os, tables],
  replays

## Compare two replays tick by tick, ignoring random object and account ids.

proc normalized(node: JsonNode, users: Table[string, string]): JsonNode =
  ## Compare numbers by value and replace random account ids with seats.
  if node.isNil: return newJNull()
  case node.kind
  of JInt: result = %(node.getInt.float)
  of JString: result = %users.getOrDefault(node.getStr, node.getStr)
  of JObject:
    result = newJObject()
    for key, value in node:
      if key != "_id": result[key] = normalized(value, users)
  of JArray:
    result = newJArray()
    for value in node: result.add normalized(value, users)
  else: result = node

proc signatures(replay: var Replay, tick: int, users: Table[string, string]): (string, seq[string]) =
  let state = replay.stateAt(tick)
  for entity in state.objects.values: result[1].add $normalized(entity, users)
  result[1].sort()
  result[0] = $normalized(state.scores, users)

proc accounts(replay: Replay): Table[string, string] =
  for slot, account in replay.header["metadata"]["accounts"].elems:
    result[account["user"].getStr] = "seat" & $slot

doAssert paramCount() == 2, "Usage: nim r tools/replayDiff.nim A.replay B.replay"

var
  left = openReplay(readFile(paramStr(1)))
  right = openReplay(readFile(paramStr(2)))
doAssert left.lastTick == right.lastTick, "horizon differs"
let leftUsers = accounts(left)
let rightUsers = accounts(right)
var differences = 0
for tick in 0..left.lastTick:
  let a = signatures(left, tick, leftUsers)
  let b = signatures(right, tick, rightUsers)
  if a != b:
    inc differences
    if differences <= 3:
      echo "tick ", tick, " scores ", a[0], " vs ", b[0], " objects ", a[1].len, " vs ", b[1].len
      for item in a[1]:
        if item notin b[1]: echo "  only left:  ", item
      for item in b[1]:
        if item notin a[1]: echo "  only right: ", item
echo if differences == 0: "IDENTICAL " & $(left.lastTick + 1) & " ticks"
  else: "DIFFERENT in " & $differences & " ticks"
