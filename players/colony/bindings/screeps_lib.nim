## Public interface to screeps library.

when defined(screepsArena):
  import screeps_lib/arena/arena
  export arena
elif defined(screepsWorld):
  import screeps_lib/world/world
  export world
else:
  # Default to screepsArena if not specified
  import screeps_lib/arena/arena
  export arena
