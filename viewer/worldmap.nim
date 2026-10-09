import
  std/[math, strutils, tables],
  chroma, pixie, vmath,
  polyworld/gameuis,
  rules

const RoomPitch = 52

type
  MapRoom* = object
    name*: string
    grid*: IVec2
  WorldMap* = object
    rooms*: seq[MapRoom]
    extent*: Vec2
    center*: Vec2
    zoom*: float32

proc roomCoordinates(name: string): IVec2 =
  var divider = name.find('N', 1)
  if divider < 0: divider = name.find('S', 1)
  require(name.len >= 4 and name[0] in {'W', 'E'} and divider > 1,
    "Invalid replay room name")
  let x = parseInt(name[1..<divider]).int32
  let y = parseInt(name[divider + 1..^1]).int32
  ivec2(if name[0] == 'W': -x - 1 else: x,
    if name[divider] == 'N': -y - 1 else: y)

proc initWorldMap*(terrain: Table[string, string]): WorldMap =
  var minimum = ivec2(int32.high)
  var maximum = ivec2(int32.low)
  for name, tiles in terrain:
    require(tiles.len == 2500, "Invalid room terrain")
    let grid = roomCoordinates(name)
    minimum = ivec2(min(minimum.x, grid.x), min(minimum.y, grid.y))
    maximum = ivec2(max(maximum.x, grid.x), max(maximum.y, grid.y))
    result.rooms.add MapRoom(name: name, grid: grid)
  require(result.rooms.len > 0, "Replay has no terrain")
  result.extent = (maximum - minimum + ivec2(1)).vec2 * RoomPitch.float32
  result.center = result.extent / 2
  result.zoom = 1
  for room in result.rooms.mitems: room.grid -= minimum

proc terrainImage*(map: WorldMap, terrain: Table[string, string]): Image =
  result = newImage(map.extent.x.int, map.extent.y.int)
  result.fill(rgbx(7, 10, 15, 255))
  for room in map.rooms:
    let tiles = terrain[room.name]
    for y in 0..<50:
      for x in 0..<50:
        let cell = tiles[y * 50 + x].ord - '0'.ord
        result[room.grid.x.int * RoomPitch + x + 1, room.grid.y.int * RoomPitch + y + 1] =
          if (cell and 1) != 0: rgbx(87, 99, 117, 255)
          elif (cell and 2) != 0: rgbx(42, 79, 58, 255)
          else: rgbx(24, 31, 40, 255)

proc scale*(map: WorldMap, panel: GameUiPanel): float32 =
  min(panel.size.x / map.extent.x, panel.size.y / map.extent.y) * map.zoom

proc imagePanel*(map: WorldMap, panel: GameUiPanel): GameUiPanel =
  let scale = map.scale(panel)
  GameUiPanel(origin: panel.origin + panel.size / 2 - map.center * scale,
    size: map.extent * scale)

proc roomPanel*(map: WorldMap, room: MapRoom, panel: GameUiPanel): GameUiPanel =
  let scale = map.scale(panel)
  GameUiPanel(origin: map.imagePanel(panel).origin + room.grid.vec2 * RoomPitch.float32 * scale,
    size: vec2(RoomPitch.float32 * scale))

proc tilePoint*(map: WorldMap, room: MapRoom, tile: Vec2, panel: GameUiPanel): Vec2 =
  map.roomPanel(room, panel).origin + (tile + vec2(1.5)) * map.scale(panel)

proc roomAt*(map: WorldMap, pointer: Vec2, panel: GameUiPanel): string =
  if not panel.contains(pointer): return
  let point = (pointer - map.imagePanel(panel).origin) / map.scale(panel)
  for room in map.rooms:
    let local = point - room.grid.vec2 * RoomPitch.float32
    if local.x >= 1 and local.y >= 1 and local.x < 51 and local.y < 51:
      return room.name

proc clampCenter(map: var WorldMap, panel: GameUiPanel) =
  let margin = min(panel.size / (map.scale(panel) * 2), map.extent / 2)
  map.center = clamp(map.center, margin, map.extent - margin)

proc zoomAt*(map: var WorldMap, pointer: Vec2, panel: GameUiPanel, delta: float32) =
  let point = (pointer - map.imagePanel(panel).origin) / map.scale(panel)
  map.zoom = clamp(map.zoom * pow(1.2'f32, delta), 1, 8)
  map.center = point - (pointer - panel.origin - panel.size / 2) / map.scale(panel)
  map.clampCenter(panel)

proc panBy*(map: var WorldMap, delta: Vec2, panel: GameUiPanel) =
  map.center -= delta / map.scale(panel)
  map.clampCenter(panel)

proc fit*(map: var WorldMap) =
  map.zoom = 1
  map.center = map.extent / 2
