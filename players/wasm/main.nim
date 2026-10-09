import
  std/jsffi

proc createBrain(): JsObject {.importjs: "new WebAssembly.Instance(new WebAssembly.Module(require('brain')))".} =
  ## Instantiate the package's binary module once per VM lifetime.

proc weights(): JsObject {.importjs: "new Uint8Array(require('weights'))".} =
  ## Access package data through Screeps' binary-module loader.

proc extra(): int {.importjs: "require('helper').extra()".} =
  ## Resolve another JavaScript module from the package.

proc spawn(value: int) {.importjs: "Game.spawns.Spawn1.spawnCreep(['move'], 'Zip' + #)".} =
  ## Demonstrate a game action driven by the WASM result and resource bytes.

proc report(value: int) {.importjs: "console.log('ZIP_WASM_OK', #)".} =
  ## Expose a compact private diagnostic for the example.

let brain = createBrain()

proc loop() =
  ## Combine WASM, JavaScript and binary resources into one tiny action.
  let data = weights()
  doAssert data.length.to(int) == 3 and data[0].to(int) == 0 and data[1].to(int) == 255
  let value = brain.exports.add(2, 3).to(int) + extra() + data[2].to(int)
  spawn(value)
  report(value)

var module {.importc, nodecl.}: JsObject
module.exports.loop = loop
