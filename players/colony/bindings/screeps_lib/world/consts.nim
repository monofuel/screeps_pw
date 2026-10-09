
const
  RESOURCE_ENERGY* = "energy".cstring
  SpawnStructureType* = "spawn".cstring
  ExtensionStructureType* = "extension".cstring
  TowerStructureType* = "tower".cstring
  ContainerStructureType* = "container".cstring
  RoadStructureType* = "road".cstring
  RampartStructureType* = "rampart".cstring
  StorageStructureType* = "storage".cstring
  LinkStructureType* = "link".cstring
  TerrainWall* = 1
  TerrainSwamp* = 2

type BodyPart* = enum
  WORK = "work"
  CARRY = "carry"
  MOVE = "move"
  ATTACK = "attack"
  RANGED_ATTACK = "ranged_attack"
  HEAL = "heal"
  CLAIM = "claim"
  TOUGH = "tough"


type FindTargetsType* = enum
  FIND_EXIT_TOP = 1
  FIND_EXIT_RIGHT = 3
  FIND_EXIT_BOTTOM = 5
  FIND_EXIT_LEFT = 7
  FIND_EXIT = 10
  FIND_CREEPS = 101
  FIND_MY_CREEPS = 102
  FIND_HOSTILE_CREEPS = 103
  FIND_SOURCES_ACTIVE = 104
  FIND_SOURCES = 105
  FIND_DROPPED_RESOURCES = 106
  FIND_STRUCTURES = 107
  FIND_MY_STRUCTURES = 108
  FIND_HOSTILE_STRUCTURES = 109
  FIND_FLAGS = 110
  FIND_CONSTRUCTION_SITES = 111
  FIND_MY_SPAWNS = 112
  FIND_HOSTILE_SPAWNS = 113
  FIND_MY_CONSTRUCTION_SITES = 114
  FIND_HOSTILE_CONSTRUCTION_SITES = 115
  FIND_MINERALS = 116
  FIND_NUKES = 117

const FIND_DROPPED_ENERGY* = FIND_DROPPED_RESOURCES

type ReturnCode* = enum
  ERR_ACCESS_DENIED = -16
  ERR_GCL_NOT_ENOUGH = -15
  ERR_RCL_NOT_ENOUGH = -14
  ERR_NO_BODYPART = -12
  ERR_TIRED = -11
  ERR_INVALID_ARGS = -10
  ERR_NOT_IN_RANGE = -9
  ERR_FULL = -8
  ERR_INVALID_TARGET = -7
  ERR_NOT_ENOUGH_ENERGY = -6
  ERR_NOT_FOUND = -5
  ERR_BUSY = -4
  ERR_NAME_EXISTS = -3
  ERR_NO_PATH = -2
  ERR_NOT_OWNER = -1
  OK = 0
