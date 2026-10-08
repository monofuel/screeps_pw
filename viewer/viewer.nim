import
  std/[json, math, os, strformat, strutils, tables],
  chroma, opengl, silky, vmath, windy,
  polyworld/[chrome, gameuis, inputs, rtscameras, viewers],
  replays, rules,
  ./sceneShapes

const
  Blue = rgbx(86, 163, 255, 255)
  Red = rgbx(245, 96, 99, 255)
  Neutral = rgbx(176, 185, 195, 255)
  Speeds = [1.0, 2.0, 10.0, 20.0, 40.0, 160.0]

var
  replay: Replay
  state, nextState: ReplayState
  window: Window
  sk: Silky
  renderer: ShapeRenderer
  room = "W1N1"
  selected = ""
  terrain: Table[string, string]
  position = 0.0
  playing = true
  repeating = true
  speedIndex = 2
  cameraTarget = vec3(0, 0, 0)
  cameraDistance = 90.0'f32
  viewProjection: Mat4

proc seatColor(user: string): ColorRGBX =
  ## Map official ownership to spectator colors.
  for slot in 0..1:
    if replay.header["metadata"]["accounts"][slot]["user"].getStr == user:
      return if slot == 0: Blue else: Red
  Neutral

proc box(point, size: Vec3, color: ColorRGBX) =
  ## Extrude one colored board object with shaded side faces.
  let a = point - vec3(size.x / 2, 0, size.z / 2)
  let b = a + vec3(size.x, 0, 0)
  let c = a + vec3(size.x, 0, size.z)
  let d = a + vec3(0, 0, size.z)
  let lift = vec3(0, size.y, 0)
  let shade = rgbx((color.r.float32 * 0.65).uint8, (color.g.float32 * 0.65).uint8,
    (color.b.float32 * 0.65).uint8, color.a)
  renderer.addQuad(a + lift, b + lift, c + lift, d + lift, color)
  renderer.addQuad(a, b, b + lift, a + lift, shade)
  renderer.addQuad(b, c, c + lift, b + lift, shade)
  renderer.addQuad(c, d, d + lift, c + lift, shade)
  renderer.addQuad(d, a, a + lift, d + lift, shade)

proc point(entity: JsonNode): Vec3 =
  ## Convert native tile coordinates to room-centered XZ coordinates.
  vec3(entity["x"].getFloat.float32 - 24.5, 0.04,
    entity["y"].getFloat.float32 - 24.5)

proc drawRoom() =
  ## Render recorded terrain and entities using cosmetic heights.
  renderer.clear()
  let tiles = terrain[room]
  for y in 0..<50:
    for x in 0..<50:
      let cell = tiles[y * 50 + x].ord - '0'.ord
      let wall = (cell and 1) != 0
      let color = if wall: rgbx(77, 89, 103, 255)
        elif (cell and 2) != 0: rgbx(45, 72, 60, 255)
        else: rgbx(31, 38, 46, 255)
      box(vec3(x.float32 - 24.5, -0.05, y.float32 - 24.5),
        vec3(0.98, if wall: 0.8 else: 0.05, 0.98), color)
  for id, entity in state.objects:
    if entity.getOrDefault("room").getStr != room or not entity.hasKey("x"): continue
    var at = point(entity)
    let tile = tiles[entity["y"].getInt * 50 + entity["x"].getInt].ord - '0'.ord
    if (tile and 1) != 0: at.y = 0.82
    let kind = entity["type"].getStr
    let color = seatColor(entity.getOrDefault("user").getStr)
    if kind == "creep" and nextState.objects.hasKey(id):
      let later = nextState.objects[id]
      if later.getOrDefault("room").getStr == room and
          abs(later["x"].getFloat - entity["x"].getFloat) <= 1 and
          abs(later["y"].getFloat - entity["y"].getFloat) <= 1:
        at = mix(at, point(later), (position - floor(position)).float32)
    case kind
    of "road": box(at, vec3(0.9, 0.03, 0.9), rgbx(105, 101, 93, 255))
    of "rampart": box(at, vec3(0.9, 0.16, 0.9), color)
    of "creep":
      box(at, vec3(0.48, 0.32, 0.48), color)
      var partIndex = 0
      for part in entity.getOrDefault("body"):
        let accent = case part["type"].getStr
          of "work": rgbx(255, 213, 81, 255)
          of "carry": rgbx(225, 225, 225, 255)
          of "attack", "ranged_attack": rgbx(255, 109, 67, 255)
          of "heal": rgbx(105, 226, 141, 255)
          else: rgbx(125, 134, 151, 255)
        let angle = partIndex.float32 * 2 * PI.float32 / max(entity["body"].len, 1).float32
        box(at + vec3(cos(angle) * 0.29, 0.1, sin(angle) * 0.29), vec3(0.11, 0.15, 0.11), accent)
        inc partIndex
    of "source": box(at, vec3(0.7, 0.4, 0.7), rgbx(239, 203, 80, 255))
    of "mineral": box(at, vec3(0.6, 0.25, 0.6), rgbx(149, 127, 202, 255))
    of "controller":
      box(at, vec3(0.8, 0.25, 0.8), color)
      box(at + vec3(0, 0.25, 0), vec3(0.2, 0.8, 0.2), color)
    of "spawn":
      box(at, vec3(0.9, 0.5, 0.9), color)
      box(at + vec3(0, 0.5, 0), vec3(0.6, 0.25, 0.6), Neutral)
    of "extension": box(at, vec3(0.55, 0.4, 0.55), color)
    of "tower": box(at, vec3(0.65, 1.0, 0.65), color)
    of "constructedWall": box(at, vec3(0.95, 0.85, 0.95), color)
    of "constructionSite": box(at, vec3(0.8, 0.12, 0.8), color)
    else: box(at, vec3(0.65, 0.3, 0.65), color)
    if id == selected:
      renderer.addSquare(at + vec3(0, 1.1, 0), 0.6, rgbx(255, 237, 139, 120))
  glClearColor(0.025, 0.03, 0.04, 1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glViewport(0, 0, window.size.x, window.size.y)
  viewProjection = perspective(RtsFieldOfView, window.size.x.float32 / max(window.size.y, 1).float32,
    0.1, 200) * lookAt(rtsCameraEye(cameraTarget, cameraDistance), cameraTarget, vec3(0, 1, 0))
  renderer.draw(viewProjection, opaque = true)

proc label(text: string, at: Vec2, color = Neutral, width = 600.0'f32) =
  ## Draw a compact HUD label.
  discard sk.drawText("Hud", text, at, color, maxWidth = width, maxHeight = 28)

proc button(text: string, at: Vec2, width = 64.0'f32): bool =
  ## Draw a button using the shared Polyworld frame style.
  let panel = GameUiPanel(origin: at, size: vec2(width, 30))
  sk.drawFrame(panel)
  label(text, at + vec2(7, 5), width = width - 12)
  window.clicked(sk, panel)

proc transportHeight(): float32 =
  ## Keep every transport control accessible in narrower browser frames.
  if window.size.x < 1120: 114 else: 84

proc drawHud() =
  ## Draw scores, room navigation, inspection, and replay transport.
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_BLEND)
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, sk.atlasTextureId())
  sk.beginUi(window, window.size)
  let w = window.size.x.float32
  let h = window.size.y.float32
  sk.drawRibbon(GameUiPanel(origin: vec2(0), size: vec2(w, 68)))
  label("Screeps PW  /  " & room, vec2(14, 10))
  for slot in 0..1:
    let name = replay.header["metadata"]["config"]["players"][slot]["name"].getStr
    label(name & "  " & formatFloat(state.scores[slot].getFloat, ffDecimal, 0).strip(chars = {'.'}) & " GCL points",
      vec2(14 + slot.float32 * 350, 36), if slot == 0: Blue else: Red, 340)
  let minimap = vec2(w - 196, 82)
  sk.drawRibbon(GameUiPanel(origin: minimap - vec2(6), size: vec2(188, 212)))
  for name in terrain.keys:
    let halves = name[1..^1].split('N')
    if halves.len != 2: continue
    let x = 10 - parseInt(halves[0])
    let y = 10 - parseInt(halves[1])
    let panel = GameUiPanel(origin: minimap + vec2(x.float32 * 16, y.float32 * 16), size: vec2(15))
    var color = rgbx(62, 70, 80, 255)
    for entity in state.objects.values:
      if entity.getOrDefault("room").getStr == name and entity["type"].getStr == "controller":
        color = seatColor(entity.getOrDefault("user").getStr)
    sk.drawRect(panel.origin, panel.size, color)
    if name == room: sk.drawRect(panel.origin + vec2(5), vec2(5), rgbx(255, 237, 139, 255))
    if window.clicked(sk, panel):
      room = name
      selected = ""
      cameraTarget = vec3(0)
  label(room, minimap + vec2(0, 180), width = 170)
  if state.objects.hasKey(selected):
    let entity = state.objects[selected]
    let at = vec2(14, 82)
    sk.drawRibbon(GameUiPanel(origin: at - vec2(6), size: vec2(260, 170)))
    label(entity["type"].getStr & " " & entity.getOrDefault("name").getStr, at, width = 250)
    label(&"({entity[\"x\"].getInt}, {entity[\"y\"].getInt})", at + vec2(0, 25))
    var row = 2
    for key in ["hits", "store", "level", "progress", "energy", "structureType"]:
      if entity.hasKey(key):
        label(key & ": " & $entity[key], at + vec2(0, row.float32 * 22), width = 250)
        inc row
  let bar = vec2(0, h - transportHeight())
  sk.drawRibbon(GameUiPanel(origin: bar, size: vec2(w, transportHeight())))
  var x = 12.0'f32
  for index, text in ["|<", "<", (if playing: "Pause" else: "Play"), ">", ">|", (if repeating: "Loop" else: "Once")]:
    if button(text, bar + vec2(x, 8)):
      case index
      of 0: position = 0
      of 1: playing = false; position = max(floor(position) - 1, 0)
      of 2: playing = not playing
      of 3: playing = false; position = min(floor(position) + 1, replay.lastTick.float)
      of 4: position = replay.lastTick.float; playing = false
      else: repeating = not repeating
    x += 70
  let compact = w < 1120
  if compact: x = 12
  for index, speed in Speeds:
    if button($speed.int & "x", bar + vec2(x, if compact: 40 else: 8), 52): speedIndex = index
    x += 58
  label(&"Tick {state.tick} / {replay.lastTick}  {Speeds[speedIndex].int}x", bar + vec2(w - 260, 10), width = 250)
  let track = GameUiPanel(origin: bar + vec2(14, transportHeight() - 32), size: vec2(w - 28, 20))
  sk.drawRect(track.origin, track.size, rgbx(53, 63, 79, 255))
  sk.drawRect(track.origin, vec2(track.size.x * position.float32 / replay.lastTick.float32, 20), Blue)
  if window.mouseDown(MouseLeft) and track.contains(sk.mousePos):
    position = clamp((sk.mousePos.x - track.origin.x) / track.size.x, 0, 1).float * replay.lastTick.float
  sk.endUi()

proc main() =
  ## Play an authoritative replay in the Polyworld graphical client.
  var path = ""
  for index in 1..paramCount():
    if paramStr(index) == "--replay" and index < paramCount(): path = paramStr(index + 1)
  require(path.len > 0, "Expected --replay FILE")
  replay = openReplay(readFile(path))
  for entry in replay.header["terrain"]: terrain[entry["room"].getStr] = entry["terrain"].getStr
  let builder = newHudAtlas(2048)
  builder.addDefaultFonts()
  builder.write("/tmp/screeps-atlas.png")
  (window, sk) = initGameWindow("Screeps PW", "/tmp/screeps-atlas.png", ivec2(1280, 800))
  renderer = initShapeRenderer()
  var clock: ViewingClock
  window.onFrame = proc() =
    let dt = clock.viewingDelta(window)
    if window.buttonPressed[KeySpace]: playing = not playing
    if playing:
      position += dt.float * Speeds[speedIndex]
      if position > replay.lastTick.float:
        if repeating: position = position mod replay.lastTick.float
        else: position = replay.lastTick.float; playing = false
    let tick = floor(position).int
    if state.scores.isNil or state.tick != tick:
      state = replay.stateAt(tick)
      nextState = replay.stateAt(min(tick + 1, replay.lastTick))
    cameraDistance = clamp(cameraDistance - window.scrollDelta.y * 3, 12, 120)
    discard applyRtsPan(cameraTarget, rtsPanDir(window), dt, cameraDistance, 25)
    if window.mouseDown(MouseMiddle):
      cameraTarget.x -= window.mouseDelta.x.float32 * cameraDistance / 800
      cameraTarget.z -= window.mouseDelta.y.float32 * cameraDistance / 800
    drawRoom()
    if window.mousePressed(MouseLeft) and window.mousePos.y > 68 and
        window.mousePos.y.float32 < window.size.y.float32 - transportHeight() and window.mousePos.x < window.size.x - 210:
      let (x, y) = groundTile(pickGroundPoint(window.mousePos.vec2, window.size.vec2, viewProjection), 25, 50)
      selected = ""
      for id, entity in state.objects:
        if entity.getOrDefault("room").getStr == room and
            entity.getOrDefault("x").getInt(-1) == x.int and entity.getOrDefault("y").getInt(-1) == y.int:
          selected = id
    drawHud()
    window.swapBuffers()
    reportReplayFrame(state.tick.int32, 0)
  while not window.closeRequested:
    pollEvents()
    waitForDisplay()

main()
