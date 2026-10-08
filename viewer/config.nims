import std/[os, strutils]

switch("define", "flatty64")
switch("define", "noAutoGLerrorCheck")
when defined(emscripten):
  let root = thisDir() / ".."
  let output = root / "build/viewer"
  mkDir(output)
  switch("threads", "off")
  switch("os", "linux")
  switch("cpu", "wasm32")
  switch("cc", "clang")
  switch("clang.exe", "emcc")
  switch("clang.linkerexe", "emcc")
  switch("mm", "arc")
  switch("exceptions", "goto")
  switch("define", "noSignalHandler")
  switch("undef", "ssl")
  switch("passL", "-O3 -o " & quoteShell(output / "viewer.html") &
    " --preload-file " & quoteShell(root / "build/ui-assets@/polyworld_art") &
    " --shell-file " & quoteShell(output / "shell.html") &
    " -s ASYNCIFY -s FETCH -s EXIT_RUNTIME=1 -s USE_WEBGL2=1 -s FULL_ES3=1" &
    " -s GL_ENABLE_GET_PROC_ADDRESS=1 -s ALLOW_MEMORY_GROWTH --profiling")
