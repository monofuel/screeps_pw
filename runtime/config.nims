import std/os

switch("backend", "js")
switch("define", "nodejs")
switch("stackTrace", "off")
switch("lineTrace", "off")
switch("path", getEnv("SCREEPS_AUTORESEARCH", thisDir() / "../../screeps_autoresearch") / "runtime")
switch("outDir", thisDir() / "../build/runtime")
