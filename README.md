# Screeps PW

Screeps World as a finite Coworld league, with native JavaScript policies and
recorded-state 3D Polyworld replays.

The local runner, 3D browser viewer, and Coworld package are implemented.
**Screeps PW 0.1.0 is published, canonical, and certified on Softmax.** Native
integration, headless browser checks, and all ten local and hosted certification
steps pass. The [Competition league](https://softmax.com/observatory/v2?detail=league:league_ac545b38-4caa-4873-a202-769697261f26)
is enabled with the colony baseline and idle control.

## Game rules

| Rule | Competition |
| --- | --- |
| World | Fresh official default 121-room private World |
| Players | Two independent accounts; starter bots and their colonies removed |
| Starts | Seat 0: W1N1 (37,31); seat 1: W9N9 (17,40) |
| Assets | One spawn containing 300 energy, RCL1, GCL1, empty Memory |
| Account CPU | 20 CPU; empty initial bucket; native replenishment and execution/memory guards |
| Duration | Exactly 6,000 completed ticks |
| Score | Closing cumulative account GCL points minus opening points |
| Winner | Higher earned GCL wins; equal scores draw |
| Colony loss | Previously earned points remain; the match continues |
| Script errors | Native runtime behavior; private diagnostics; the match continues |
| Gameplay | Native visibility, API, intents, economy and combat |
| NPCs | Optional NPC spawning jobs disabled for this fixture |

The map is asymmetric. League duels evaluate both starting assignments. Each
episode retains its own scores; there is no survival bonus, elimination win, or
research-benchmark qualification gate. GCL points are cumulative account points,
not integer GCL levels, controller levels, or current-level progress.
The seed is recorded as fixture metadata; v1 uses the fixed default terrain and
does not reseed native JavaScript randomness.

## Simulation and playback clocks

The engine advances immediately after a committed turn, without inter-tick
sleep or an internal whole-match wall-clock cutoff. Actual throughput depends
on scripts, engine work, and I/O. Script CPU and memory guards remain enabled.

Completed replays default to **10x playback: 10 ticks per second**. A full
competition replay takes ten minutes. Normal 1x playback is one tick per second.
Playback speed does not affect simulation or scores.

Hosted episodes have the platform's required watchdog, declared as 100 minutes.
A killed or incomplete episode does not produce a completed game result.

## Submit a policy

Supply one self-contained JavaScript file, at most 2 MiB, exporting `loop`:

```javascript
module.exports.loop = function () {
  // Ordinary Screeps World account code.
};
```

Participants may author JavaScript. Project tooling, fixtures, and our reference
bots are authored in Nim; generated JavaScript stays outside Git.

The official runner provides `Game`, `Memory`, `RawMemory`, and intent
processing. Submitted code is account code, not a server mod, npm package, or
native process. It runs in the official per-account sandbox. Private logs are
bounded to 10 MiB per seat and never included in the public replay.

Bundled players are the existing `screeps_bot` World colony strategy and a
Nim-generated idle control. Multi-module uploads and human gameplay controls
are outside v1.

With an authenticated Softmax account, upload and submit a compiled policy:

```sh
nim r tools/sdk.nim upload-policy --file /absolute/path/to/policy.js --name my-screeps-policy
nim r tools/sdk.nim submit my-screeps-policy:v1 --league league_ac545b38-4caa-4873-a202-769697261f26 --no-open-browser
```

Policy versions belong to the uploading player. For another owned player,
`nim r tools/playerUpload.nim PLAYER_ID POLICY_FILE POLICY_NAME` uses a private
temporary credential directory and leaves the shared active player unchanged.
Submit that version with `--player PLAYER_ID`, or use the Observatory. Each user
may field two players.

## Build and run locally

Use Linux, Docker, Nim 2+, Nimby 0.2.3+, Make, and sha256sum. The browser build
uses the pinned Nix toolchain when Emscripten is absent.

```sh
make deps
make build
build/match build/players/baseline.js build/players/idle.js
build/match build/players/idle.js build/players/baseline.js
make test
make integration
make viewer
make browser-test REPLAY=/absolute/path/to/match.replay
```

The runner accepts `--ticks:NUMBER`, `--seed:NUMBER`, `--output:DIRECTORY`,
and `--image:IMAGE`. Short horizons are for smoke checks; competition uses
6,000 ticks. Artifacts default to `~/.local/share/screeps-pw/matches/`.

The default engine image is the frozen official image used by autoresearch,
with Screeps revision `7ff972231c0a0a7aa91978297432ddb806976281`. It must already
be built locally from `screeps_autoresearch/Dockerfile.screeps`.
Matches use disposable storage, no network, and no staging volume or game/admin
ports. Cancellation cleans up the episode container.

`make deps` creates a separate Nimby workspace under
`~/.local/share/screeps-pw/deps/`. It does not move shared workspace checkouts.
`SCREEPS_PW_DEPS` overrides that location. Node glue imports the small
`nodeBridge`, `nativeJson`, and `turnScheduler` modules from
`SCREEPS_AUTORESEARCH` or the sibling checkout.

## 3D viewer

The Nim/WASM viewer uses Polyworld's RTS camera and shared HUD theme. Terrain
walls rise above a room board; buildings and creeps use procedural geometry and
ownership/body-part colors. The world minimap selects rooms. Click objects for
inspection, pan with arrow keys or the middle mouse button, and zoom with the
wheel. The bottom bar controls play, pause, stepping, seeking, looping and speed.

The replay records the shared authoritative world once, including tick 0 and
every completed tick. Static terrain is stored once. Independently compressed
100-tick chunks begin with full keyframes and continue with entity upserts and
removals. The decoder reconstructs recorded state without running a Screeps
server or resimulating intents. Policy source, Memory, tokens and console
messages are excluded from replay entity data.

The static bundle reads the replay URL from `#replay=`, with query fallback,
and reports readiness after displaying a valid frame. Browser viewing requires
serving the bundle over HTTP. There is no live 3D viewer in v1.

`make browser-test` starts disposable headless Chromium and a loopback HTTP
server on ports 8770 and 8769, checks a full 6,000-tick replay, then stops both.
It verifies visible geometry, normal/default playback clocks, pause, stepping,
timeline seeking, room switching, resizing, and visible missing-replay errors.
Screenshots and browser profiles stay under `~/.local/share/screeps-pw/`.

The league's episode page opens the hosted 3D viewer. The CLI can print its
viewer link without launching a desktop browser:

```sh
nim r tools/sdk.nim replay-open ereq_1cda007f-f4ed-455f-a132-efe2add8216f --hosted --no-open-browser
```

Set `SCREEPS_PW_VIEWER_URL` when running `make browser-test` to check a hosted
viewer session instead of the local bundle. This was verified against the
published 0.1.0 viewer and its hosted replay.

## Coworld package

```sh
make package
make certify
```

Set `VERSION` for later immutable releases, for example
`make package VERSION=0.1.1`.

Packaging uses the pinned Coworld SDK through an isolated uv tool environment.
Set `COWORLD_SOURCE` to the checked-out SDK package when its default workspace
location differs. Coworld and its `softmax-cli` auth dependency are both loaded
from the pinned source checkout; the auth override preserves support for
`SOFTMAX_CONFIG_DIR`. The tested SDK revision is
`d9d2a9a91131e7ef2f7c9ef6ac35c53775a5a386`.

The game image owns both policy VMs and all engine processes. No nested Docker
or separate player pods are required. The package declares the
`coworld-player-seats/2` file-player contract, a 6,000-tick competition variant,
a 600-tick certification fixture, private seat logs/status, a health endpoint,
global WebSocket Ping/Pong, and a static replay bundle.

The runtime image extracts the exact official Node binary, engine installation,
shared libraries and license documentation from the frozen autoresearch image.
It is about 487 MB instead of carrying the 4 GB build environment. Its full
6,000-tick control produced the same 32,416 points as the original image.

Replay and private outputs finish before the atomic results completion marker.
The lifecycle server stays available until the platform stops it. The generated
SDK viewer hook is a Nim executable at the required
`tools/build_replay_viewer.sh` path; no authored shell script is used.

The initial league configuration is one Competition division, paired duels,
Elo 1500/K32 without margin weighting, and a thirty-minute round cadence.
Rounds wait for two eligible entrants. The published Coworld name is the literal
`Screeps PW`, including spaces and capitalization.

## Verification evidence

Two full 6,000-tick baseline-versus-idle matches completed on the initial build:

| Baseline start | Earned GCL | Idle GCL | Engine wall time |
| --- | ---: | ---: | ---: |
| W1N1 | 32,416 | 0 | 165 seconds |
| W9N9 | 16,792 | 0 | 168 seconds |

These are integration controls, not hosted standings or claims of deterministic
timing. Exact policy/adapter/image hashes and fixtures are retained with each
match. Preserve both starting assignments when comparing policies.

The final runtime repeated the W1N1 control with exactly 32,416 earned points
over 6,000 ticks. Integration checks also cover exact starting assets, chunk
boundaries and backwards seeks, private script errors, infinite-loop and heap
guards, denied host modules/process access, cancellation cleanup, and engine
failure without completed results. The 600-tick Coworld fixture scored 290:0.
See [the verification record](coworld/VERIFICATION.md) for frozen hashes,
commands, and compact artifact references.

The first hosted Competition round completed both 6,000-tick starting
assignments, scoring the same 32,416:0 and 16,792:0 as the local controls.
Softmax published colony MMR 1516 and idle MMR 1484. The hosted replay also
passes the full browser checks. These two starter policies establish operation;
they do not measure strength against independent submissions.

## References and ownership

Mindustry's Coworld wrapper is the reference for original-engine lifecycle,
shared-world replay chunks, and output finalization. Its BASIC policy interface
and game rules are not used here.

Polyworld supplies camera and graphical UI modules. Screeps owns simulation.
`screeps_autoresearch` owns the official image and research benchmarks;
`screeps_bot` owns strategies and shared bot utilities; `screeps_lib` owns
game bindings. The league adapter does not change staging or research services.

See [THIRD_PARTY.md](THIRD_PARTY.md) for pinned code/assets and license notices.
Persistent worlds, custom balanced maps, additional players, richer models,
live visualization, and additional submission formats are later work.
