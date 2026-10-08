import
  std/[os, osproc, streams, strutils]

const Root* = currentSourcePath().parentDir.parentDir

proc command*(args: openArray[string], directory = Root): string =
  ## Capture a command without shell expansion.
  let child = startProcess(args[0], workingDir = directory,
    args = args[1..^1], options = {poUsePath, poStdErrToStdOut})
  defer: child.close()
  result = child.outputStream.readAll().strip()
  if child.waitForExit() != 0:
    raise newException(IOError, args[0] & " failed:\n" & result)

proc run*(args: openArray[string], directory = Root) =
  ## Run a build with inherited diagnostic output.
  let child = startProcess(args[0], workingDir = directory,
    args = args[1..^1], options = {poUsePath, poParentStreams})
  defer: child.close()
  if child.waitForExit() != 0: raise newException(IOError, args[0] & " failed")

proc hashFile*(path: string): string =
  ## Hash exact participant bytes.
  command(["sha256sum", path]).splitWhitespace()[0]
