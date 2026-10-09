import
  std/[json, tables],
  replays

type
  RoomActivity = object
    active: bool
    combatUntil, eventUntil: float
    lastShown: float
  ReplayDirector* = object
    room*: string
    automatic*: bool
    elapsed, heldSince: float
    players: seq[string]
    activity: Table[string, RoomActivity]
    previous: ReplayState

const
  RoomHoldSeconds* = 30.0
  EventMemorySeconds* = 10.0
  Buildings = ["spawn", "extension", "road", "constructedWall", "rampart",
    "link", "storage", "tower", "observer", "powerSpawn", "extractor", "lab",
    "terminal", "container", "nuker", "factory"]
  CombatActions = ["attack", "attacked", "rangedAttack", "rangedMassAttack",
    "heal", "rangedHeal"]

proc initReplayDirector*(room: string, players: seq[string]): ReplayDirector =
  result = ReplayDirector(room: room, automatic: true, players: players)
  result.activity[room] = RoomActivity(lastShown: 0)

proc manual*(director: var ReplayDirector, room: string) =
  director.automatic = false
  director.room = room

proc resetHistory*(director: var ReplayDirector) =
  for activity in director.activity.mvalues:
    activity.active = false
    activity.combatUntil = 0
    activity.eventUntil = 0
  director.activity.mgetOrPut(director.room, RoomActivity()).lastShown = director.elapsed
  director.previous = ReplayState()
  director.heldSince = director.elapsed

proc resume*(director: var ReplayDirector) =
  director.automatic = true
  director.resetHistory()

proc advance*(director: var ReplayDirector, seconds: float, playing: bool, visible = true) =
  if playing and visible: director.elapsed += max(seconds, 0)

proc owned(director: ReplayDirector, entity: JsonNode): bool =
  entity.getOrDefault("user").getStr in director.players

proc activityFor(director: ReplayDirector, room: string): RoomActivity =
  director.activity.getOrDefault(room, RoomActivity(lastShown: -1))

proc remember(director: var ReplayDirector, room: string, combat: bool) =
  var activity = director.activityFor(room)
  if combat: activity.combatUntil = director.elapsed + EventMemorySeconds
  else: activity.eventUntil = director.elapsed + EventMemorySeconds
  director.activity[room] = activity

proc observe*(director: var ReplayDirector, state: ReplayState) =
  if not director.previous.scores.isNil and state.tick == director.previous.tick: return
  for activity in director.activity.mvalues: activity.active = false
  for id, entity in state.objects:
    let
      room = entity.getOrDefault("room").getStr
      kind = entity.getOrDefault("type").getStr
      owned = director.owned(entity)
    if owned and (kind == "creep" or
        (kind == "spawn" and not entity.getOrDefault("spawning").isNil and
          entity["spawning"].kind != JNull)):
      var activity = director.activityFor(room)
      activity.active = true
      director.activity[room] = activity
    if director.previous.scores.isNil: continue
    let log = entity.getOrDefault("actionLog")
    if owned and not log.isNil and log.kind == JObject:
      for action in CombatActions:
        if log.hasKey(action) and log[action].kind != JNull:
          director.remember(room, true)
    if director.previous.objects.hasKey(id):
      let before = director.previous.objects[id]
      if owned and kind in ["creep", "spawn"] and entity.hasKey("hits") and
          before.hasKey("hits") and entity["hits"].getInt < before["hits"].getInt:
        director.remember(room, true)
      if kind == "controller" and (owned or director.owned(before)) and
          (entity.getOrDefault("user") != before.getOrDefault("user") or
            entity.getOrDefault("level") != before.getOrDefault("level")):
        director.remember(room, false)
    elif owned and kind in Buildings:
      director.remember(room, false)
  if not director.previous.scores.isNil:
    for id, entity in director.previous.objects:
      if not state.objects.hasKey(id) and director.owned(entity) and
          entity.getOrDefault("type").getStr in Buildings:
        director.remember(entity["room"].getStr, false)
  director.previous = state

proc priority(director: ReplayDirector, activity: RoomActivity): int =
  if activity.combatUntil > director.elapsed: 3
  elif activity.eventUntil > director.elapsed: 2
  elif activity.active: 1
  else: 0

proc choose*(director: var ReplayDirector, playing: bool, visible = true): bool =
  if not director.automatic or not playing or not visible or
      director.elapsed - director.heldSince < RoomHoldSeconds: return false
  let currentPriority = director.priority(director.activityFor(director.room))
  var
    candidate = ""
    bestPriority = 0
    oldest = 0.0
  for room, activity in director.activity:
    if room == director.room: continue
    let priority = director.priority(activity)
    if priority == 0 or priority < currentPriority: continue
    if candidate.len == 0 or priority > bestPriority or
        (priority == bestPriority and (activity.lastShown < oldest or
          (activity.lastShown == oldest and room < candidate))):
      candidate = room
      bestPriority = priority
      oldest = activity.lastShown
  if candidate.len == 0: return false
  director.room = candidate
  director.heldSince = director.elapsed
  director.activity[candidate].lastShown = director.elapsed
  true
