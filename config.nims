import std/[os, strutils]

switch("path", thisDir() / "src")
switch("define", "release")
switch("outDir", thisDir() / "build")
let dependencyRoot = getEnv("SCREEPS_PW_DEPS", getHomeDir() / ".local/share/screeps-pw/deps")
for line in readFile(thisDir() / "nimby.lock").splitLines():
  let fields = line.splitWhitespace()
  if fields.len == 0: continue
  let directory = dependencyRoot / fields[0]
  if dirExists(directory):
    switch("path", directory)
    switch("path", directory / "src")
