import
  screeps_lib

type
  Strategy* = ref object of RootObj

method tick*(self: Strategy) {.base.} =
  ## Execute the strategy for the current tick.
  discard

method addCreep*(self: Strategy, creep: Creep) {.base.} =
  ## Assign a creep to the strategy.
  discard

method removeCreep*(self: Strategy, creep: Creep) {.base.} =
  ## Remove a creep from the strategy.
  discard

method suggestSpawn*(self: Strategy): seq[cstring] {.base.} =
  ## Choose a body to spawn, or return an empty sequence.
  @[]
