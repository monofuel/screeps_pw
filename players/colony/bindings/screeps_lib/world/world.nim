
import
  ./[types, consts]

export types, consts

# API https://docs.screeps.com/api/

# Reference
# https://github.com/oderwat/nim-screeps

type
    Game* = ref GameType
    WorldMemory* = ref MemoryType
when not defined(screepsTest):
    var game* {.noDecl, importc: "Game".}: Game
    var memory* {.noDecl, importc: "Memory".}: WorldMemory
