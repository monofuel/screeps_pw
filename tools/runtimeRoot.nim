import
  std/[os, osproc, sets, streams, strutils],
  rules

var copied: HashSet[string]

proc copyRuntime(path: string) =
  ## Preserve resolved runtime bytes at their original absolute location.
  if path in copied: return
  require(path.isAbsolute and fileExists(path), "Missing runtime file: " & path)
  let destination = "/runtime" & path
  createDir(destination.parentDir)
  copyFile(path, destination)
  setFilePermissions(destination, getFilePermissions(path))
  copied.incl path

proc dependencies(path: string) =
  ## Collect the exact shared-library closure reported by the original loader.
  let child = startProcess("ldd", args = @[path], options = {poUsePath, poStdErrToStdOut})
  defer: child.close()
  let output = child.outputStream.readAll()
  require(child.waitForExit() == 0 and "not found" notin output, "Unresolved runtime dependencies: " & path)
  for line in output.splitLines():
    var fields = line.strip().splitWhitespace()
    if fields.len == 0: continue
    if fields.len >= 3 and fields[1] == "=>": fields = fields[2..^1]
    if fields[0].isAbsolute: copyRuntime(fields[0])

proc main() =
  ## Assemble the existing official engine without its unrelated build tools.
  createDir("/runtime")
  copyRuntime("/usr/bin/node")
  dependencies("/usr/bin/node")
  for path in walkDirRec("/opt/screeps"):
    if path.endsWith(".node"): dependencies(path)
  copyDir("/opt/screeps", "/runtime/opt/screeps")
  for directory in ["/usr/share/doc", "/var/db/repos/gentoo/licenses"]:
    if dirExists(directory): copyDir(directory, "/runtime" & directory)
  for path in ["/etc/ld.so.cache", "/etc/passwd", "/etc/group", "/etc/nsswitch.conf"]:
    copyRuntime(path)
  for directory in ["/world", "/episode", "/tmp", "/root"]: createDir("/runtime" & directory)
  setFilePermissions("/runtime/tmp", {fpUserRead, fpUserWrite, fpUserExec,
    fpGroupRead, fpGroupWrite, fpGroupExec, fpOthersRead, fpOthersWrite, fpOthersExec})
  echo "Official runtime libraries: ", copied.len

main()
