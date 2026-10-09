import
  std/jsffi,
  screeps_lib

proc boostedSmallInvader*(enemy: Creep): bool =
  ## Select armored response for a validated NPC with any admitted boost.
  for part in enemy.body:
    if not part.boost.isNil: return true

proc smallInvader*(room: Room): Creep =
  ## Identify one small mixed melee NPC with at most declared first-tier boosts.
  let enemies = room.findCreeps(FIND_HOSTILE_CREEPS)
  if enemies.len != 1:
    return
  let enemy = enemies[0]
  if enemy.owner.isNil or enemy.owner.username != "Invader".cstring or
      enemy.toJs["body"].isNil or enemy.body.len notin 1..10:
    return
  var attacks, ranged: int
  for part in enemy.body:
    if part.`type` notin ["move".cstring,
        "tough".cstring, "work".cstring, "attack".cstring, "ranged_attack".cstring]:
      return
    if not part.boost.isNil:
      let allowed = case $part.`type`
        of "tough": "GO".cstring
        of "attack": "UH".cstring
        of "ranged_attack": "KO".cstring
        of "work": "ZH".cstring
        else: "".cstring
      if allowed.len == 0 or part.boost != allowed: return
    if part.`type` == "attack".cstring: inc attacks
    elif part.`type` == "ranged_attack".cstring: inc ranged
  if attacks == 1 and ranged <= 1:
    result = enemy
