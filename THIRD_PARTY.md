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
license texts while omitting the build environment. Native execution glue imports small modules from
`screeps_autoresearch`; compiled releases record their input hashes.
