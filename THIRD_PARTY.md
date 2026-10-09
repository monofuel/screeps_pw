# Third-party code and assets

`viewer/sceneShapes.nim` is Polyworld's `src/polyworld/shapes.nim` at
`d46a6266ef9164ced5bdafc724d9782ef8c80d8e`, with an optional opaque depth-writing
mode for the Screeps board. It is distributed under Polyworld's MIT license.
The source and copyright notice are in the pinned Polyworld dependency.

Other Polyworld modules are consumed directly from the pinned Nimby checkout.
The viewer distributes only shared HUD theme, icons and fonts from
`polyworld_art` at `f78d18d8eeb899ed3aa7a304944be448aec34dcf`, including their
license notices. Screeps client raster assets are not included.

The official Screeps server and dependencies retain their upstream licenses in
the game image. The runtime image copies the frozen official installation,
Node binary, resolved shared libraries, package documentation, and Gentoo
license texts while omitting the build environment. The immutable public
runtime is distributed at
`public.ecr.aws/q5f4m8t9/cogames@sha256:a99178510203da99bf58b48d545c3b3e025a33aeb78f51f0262d543516a9c5d6`.

## Included source snapshots

- `players/colony/main.nim`, `worldStrategy.nim`, and `botlib/`: World strategy
  modules from `screeps_bot` at `0a14451e8b72f7e24ee6c07b5106690d6490c146`.
  The original MIT notice is retained in `players/colony/LICENSE-bot`.
- `players/colony/bindings/`: World modules from `screeps_lib` at
  `1e4246a196dac2f1b1aa67de795a1923f1f4beca`. The original MIT notice is retained
  in `players/colony/LICENSE-bindings`.
- `runtime/shared/{nodeBridge,nativeJson,turnScheduler}.nim`: the author's
  runtime helpers from `screeps_autoresearch` at
  `94d09964554284ff675efb6251f7f79d2fc7b249`, released here under the project MIT
  license. No research dashboard, benchmark database, or private logs are included.

These snapshots allow standalone builds without publishing or requiring the
rest of the author's workspace. Generated JavaScript and binaries stay outside
Git. The public server runtime contains upstream JavaScript and native modules
under their respective package licenses.
