type
  WorkTask* = enum
    Refill, Repair, Build, Upgrade
  WorkFeatures* = array[12, float32]
  WorkMask* = array[4, bool]
  WorkObservation* = object
    features*: WorkFeatures
    eligible*: WorkMask
  WorkCandidate* = object
    task*: WorkTask
    targetId*: string
    features*: array[15, float32]
  WorkJobObservation* = object
    creepId*, roomName*: string
    candidates*: seq[WorkCandidate]
    teacherIndex*: int
  WorkerTaskPolicy* = object
    choose*: proc(observation: WorkObservation): WorkTask
    chooseJob*: proc(observation: WorkJobObservation): int
    prepared*: proc(cpu: float)
    selectedJob*: proc(candidate: WorkCandidate)
    executed*: proc(task: WorkTask, code: int)
    overridden*: proc(reason: string)

const
  FeatureCount* = 12
  ActionCount* = 4
  WorkSchemaVersion* = 1
  DistanceScale* = 50.0'f32
  ControllerLevelScale* = 8.0'f32
  DowngradeScale* = 20000.0'f32
  JobSchemaVersion* = 2
  JobFeatureCount* = 15
  MaximumJobCandidates* = 10
  CandidatesPerTask* = 3

proc eligibleCount*(observation: WorkObservation): int =
  ## Count the tasks available in an observation.
  for available in observation.eligible:
    if available:
      inc result

proc teacherTask*(observation: WorkObservation): WorkTask =
  ## Select the first available task in the ordinary worker priority order.
  if observation.eligibleCount == 0:
    raise newException(ValueError, "No eligible worker task")
  var found = false
  for task in WorkTask:
    if observation.eligible[ord(task)] and not found:
      result = task
      found = true

proc normalized*(value, scale: float32): float32 =
  ## Scale a nonnegative feature into the unit interval.
  if scale <= 0:
    raise newException(ValueError, "Feature scale must be positive")
  min(1.0'f32, max(0.0'f32, value / scale))
