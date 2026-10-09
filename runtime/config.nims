import std/os

switch("backend", "js")
switch("define", "nodejs")
switch("stackTrace", "off")
switch("lineTrace", "off")
switch("path", thisDir() / "shared")
switch("outDir", thisDir() / "../build/runtime")
