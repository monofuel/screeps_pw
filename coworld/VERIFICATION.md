# Initial MVP verification

Verified on 2026-10-08. This records integration controls separately from hosted
league standings.

## Frozen inputs

- Official Screeps source: `7ff972231c0a0a7aa91978297432ddb806976281`.
- Engine 4.3.0; driver 5.3.0; Node 22.23.2.
- Original image: `sha256:bce4a765cd4cc81b25b5c90b153c6bfb9b3a39650199dfd0b02f476f714cfa2d`.
- Runtime image: `sha256:608a09d38ee89f8ff282ce717f8b6181f80de3db563ff286bffd3cce0da024ff`.
- Default database fixture SHA256: `327d73d39efa91a09d64e6088e006a60f4d1ad5cef7105c35076a5dcd83efb54`.
- Colony policy SHA256: `3b53a1030e53edf2a1098628cc0c5e735c13e5974474d798b2f430921432ee4e`.
- Idle policy SHA256: `e6fe79fc88e5a13fd0a4ed92a94602ac9480be2bcb52ca80470da725f08240be`.
- Launcher SHA256: `5f6f5aa26e549f16c68e01db6dc84720df23925b1d8254a46228bdb88b9abcba`.
- Turn/recording adapter SHA256: `2f62111112bc2f759db0c87c8335baa39e57e2c18db235bfa6422c08f75126fe`.
- Polyworld: `d46a6266ef9164ced5bdafc724d9782ef8c80d8e`.
- Coworld SDK: `d9d2a9a91131e7ef2f7c9ef6ac35c53775a5a386`.

## Completed matches

Both accounts started with one 300-energy spawn, RCL1/GCL1, CPU20 and bucket0.
The horizon was 6,000 committed ticks; the fixed-map seed metadata was 2026.

| Build/start | Colony score | Idle score | Wall seconds | Artifact directory suffix |
| --- | ---: | ---: | ---: | --- |
| Original / W1N1 | 32,416 | 0 | 165.140 | `20261008T225234Z-3Ap4KgbS` |
| Original / W9N9 | 16,792 | 0 | 168.197 | `20261008T225843Z-0qBcVdlf` |
| Final adapter / W1N1 | 32,416 | 0 | 209.348 | `20261008T231434Z-eJ8hsOyN` |
| Runtime image / W1N1 | 32,416 | 0 | 169.242 | `20261008T233343Z-leHsqHsR` |

Artifacts are under `~/.local/share/screeps-pw/matches/`. The final replay has
61 chunks, 337 initial objects and 357 terminal objects. The earlier two
development replays predate metadata-token removal and remain local evidence;
use a final-adapter replay for viewing or distribution.

```sh
make test
make integration
make package
make certify
build/match build/players/baseline.js build/players/idle.js --image:screeps-pw:0.1.0
make browser-test REPLAY=/absolute/path/to/final/match.replay
```

Unit checks cover grants, cumulative GCL transitions, exact ties, loss-retained
points, incomplete matches and replay reconstruction. Seven engine checks cover
starts/turn boundaries, private errors, infinite loops, denied host access,
oversized heap allocation, cancellation cleanup and infrastructure failure.

All ten local Coworld certification steps pass on the runtime image. Its
600-tick fixture scored 290:0. Certification evidence is at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-cn3ycsxk/`.

Headless Chromium checks pass for visible 3D drawing, playback clocks, pause,
single-step, start/end and timeline seeks, room switching, resize and visible
missing-replay failure. Browser artifacts stay under
`~/.local/share/screeps-pw/browser/`; compilation alone is not this evidence.

## Hosted release

`Screeps PW:0.1.0` is public, canonical and certified. The hosted certifier
`main-05ed48aa1793` passed all ten checks, including five completed smoke episodes.

- Coworld: `cow_d7adf8df-331e-4ced-9def-8a0bd6af4574`.
- Manifest: `sha256:886199c34b6df207ae2400b373621e376b60ebd4cb8cd1a5f860d59e6939a0bd`.
- League: `league_ac545b38-4caa-4873-a202-769697261f26`.
- Seed: `lseed_5bf2d939-dd93-4816-8eac-b6d5e25c391b`.
- Competition division: `div_1f1a9024-6003-4f44-b06f-cb2efee35f31`.
- Colony version: `9a9522a1-b610-4e21-a630-bcca5edd9993`.
- Idle version: `c165e054-cffc-4ac8-ab16-7a2ecbc38715`.

The platform commissioner is enabled, with `team_pair` scheduling, both seat
assignments, 30-minute cadence, Elo 1500/K32 and two players per user. Settings
were read back and checked against `effective_ladder_config`. Both starter
memberships are active in Competition; their champion flags identify each
player's deployed policy, not a leaderboard rank.

The pinned source auth override passed an isolated-player selection check.
It changed only the temporary credential copy; shared credentials remained
byte-for-byte unchanged. Hosted certification, settings, submissions and round
evidence are under `~/.local/share/screeps-pw/`.

## First hosted Competition round

Round `round_01987592-6c5b-4617-8650-a303ab2498df` completed on
2026-10-08 at 23:55:02 UTC, with no round error and both episodes scored.

| Colony start | Episode request | Completed ticks | Colony GCL | Idle GCL | Recorded seed |
| --- | --- | ---: | ---: | ---: | ---: |
| W1N1 | `ereq_1cda007f-f4ed-455f-a132-efe2add8216f` | 6,000 | 32,416 | 0 | 1,835,562,822 |
| W9N9 | `ereq_e44770ee-b70a-459a-9ad5-e0c99708054c` | 6,000 | 16,792 | 0 | 1,835,562,821 |

The published MMR view reports colony 1516 and idle 1484, with two wins and
two losses respectively after one round. Colony mean earned GCL is 24,604.
This is a two-policy integration control, not evidence of strength against
independent submissions.

The downloaded hosted W1N1 replay is 1,509,694 bytes, with 61 chunks, 337 initial
objects and 357 terminal objects. Its terminal scores are exactly `[32416,0]`.
The full browser transport/drawing checks pass on this hosted replay.
They also pass against the actual hosted viewer session, including bundle
loading, replay retrieval, rendering and controls under the platform's headers.

## Split viewer and active opponent

Verified locally on 2026-10-09 UTC. The viewer starts with equal panes: a 3D
room and a detailed, cached 11x11 world terrain map. Ownership, resources,
creeps and buildings are overlaid on the terrain; room selection links the map
and 3D pane. Pan, pointer-centered zoom, Fit and a draggable divider preserve
the shared replay clock.

Native checks, `make test`, the WASM build and full-replay browser checks pass.
Browser checks inspect actual wall/swamp pixels, selection-outline movement,
3D room switching, map wheel isolation, map dragging, divider resizing and
window resizing, as well as the existing playback/error checks.

```sh
make viewer
make browser-test REPLAY=/home/monofuel/.local/share/screeps-pw/hosted-seat0.replay
make package VERSION=0.1.1 GAME_IMAGE=screeps-pw:0.1.0
make certify
```

The 0.1.1 package reuses runtime image `608a09d38ee8`; its native engine,
launcher, turn adapter and policy bytes retain the original frozen hashes.
All ten local certification checks pass; artifacts are at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-nmyuois2/`.

The second league player now runs `screeps-pw-colony-b:v1`, policy version
`09cfb2a8-7619-486b-8503-ef5caeadbdde`, using the same compiled colony baseline.
Submission `sub_36c2066b-0c6a-41e3-bab7-d18dd906b9ff` is active in Competition
with membership `lpm_dcd3bd54-c85b-4434-a0c4-78f2cb2911a0`. Its idle membership
is benched. Idle remains a bundled certification/test control.

The public, canonical 0.1.1 release is
`cow_ddc2b7be-b01f-4172-9cf4-741da540dbf2`, with manifest hash
`sha256:128e4d87cf5589d4c289e5aa341f8e9a454f478e348dc460bde0eff9bb0d89e1`.
All ten hosted certification checks and five smoke episodes passed. Runtime
image and rules are unchanged; previous episodes retain their immutable viewer
version, while new episodes use the canonical release.
The published split viewer also passes the full browser interaction checks
against hosted certification episode
`ereq_72001ac9-9d8a-4eb4-92e6-99a937843922` and its 600-tick replay. Evidence is
at `~/.local/share/screeps-pw/split-hosted-browser.log`.

The first colony-versus-colony round,
`round_b32fdb48-002d-4464-a509-402675d40103`, completed at
2026-10-09 00:15:36 UTC with no round error. Both episodes reached 6,000 ticks
and scored `[32416,16792]` in seat order. The players swap seats between
`ereq_501de8ce-a51a-4af4-b40f-a33016462507` and
`ereq_2cabe586-ec48-4c95-afe8-a57f6f4914c6`, so each won once and earned a mean
of 24,604 GCL points. The first replay is 2,343,211 bytes.

## Fixed 4×4 MVP map

The current fixture contains exactly 16 rooms, W1–W4 / N1–N4. It retains the
default room terrain, connects each adjacent pair with three-tile-wide entrances
and seals the outer edges. Starts are W1N1 (37,31) and W2N2 (17,40), two room
transitions apart; each starting room has two sources. Scoring, account budgets
and the 6,000-tick horizon are unchanged.

The cropped database rebuilds Loki indexes and native terrain/accessibility
caches. Its fixture SHA-256 is
`08fd55d69370e2fd4891e0e8a54145cacce4d03f29c43122137f3f3a105b6047`.
The runtime image is
`sha256:4001c06899e7aafeca9a6ec55808e37cb9d95858ae584034b19cab6f124c0f72`.

`make test`, native module checks, all eight disposable-engine integration
checks and the headless browser checks pass. The navigation check verifies
native routes to every room, blocked routes outside the map, sealed edge
terrain, and an actual creep crossing between the starting rooms within
300 ticks. Its artifacts are at
`~/.local/share/screeps-pw/matches/20261009T013829Z-h7Y95uXQ/`.
The browser checks verify terrain detail, linked selection, pan/zoom, divider
resizing and playback with this smaller map. All ten local certification steps
pass, with artifacts at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-netcyl7f/`.

The two compiled colony examples completed a full 6,000-tick local match with
seat-order earned GCL `[32416,10031]` in 157.559 seconds and no policy/runtime
errors. This proves operation, not PvP strength. Artifacts are at
`~/.local/share/screeps-pw/4x4-duels/20261009T013857Z-CaRg6ByO/`.

Softmax certified all ten hosted steps at 2026-10-09 01:42:58 UTC and passed
five upload smoke episodes. The published 0.1.2 package is
`cow_dede9385-2a54-495b-95ab-208c59a032e2`, manifest hash
`sha256:6e688710bdc5c788f5e5cd4a105f130cc410ec29387b2d6d66215f43e6c7b0e7`.
The existing league's game and canonical Coworld pointers both resolve to this
package. Its two existing players remain in Competition.
Hosted smoke replay `ereq_0a466984-b257-475f-baf9-cc0185d2cc98` decodes to
exactly 16 rooms and 600 completed ticks, scoring `[290,0]`. The downloaded
replay is `~/.local/share/screeps-pw/4x4-hosted.replay`; the upload transcript is
`~/.local/share/screeps-pw/4x4-upload.log`.
A fresh round was requested through the existing league's `trigger-round`
endpoint after confirming the new canonical package; the acknowledgement is
`~/.local/share/screeps-pw/4x4-trigger-round.json`.

```sh
make test
make integration
make package VERSION=0.1.2
make certify
make browser-test REPLAY=/home/monofuel/.local/share/screeps-pw/matches/20261009T013829Z-h7Y95uXQ/match.replay
build/match build/players/baseline.js build/players/baseline.js --output:/home/monofuel/.local/share/screeps-pw/4x4-duels
nim r tools/sdk.nim --elevated upload-coworld dist/coworld_manifest.json --visibility public --wait-certification
nim r tools/replay.nim /home/monofuel/.local/share/screeps-pw/4x4-hosted.replay
```

## Public source preparation — 2026-10-09 UTC

The public repository includes the full colony example, World bindings and
three runtime helpers as source snapshots (revisions in `THIRD_PARTY.md`).
Builds no longer read sibling repositories. Local matches and Docker packages
use the immutable public 0.1.2 engine runtime from ECR; the SDK wrapper defaults
to public `coworld[auth]==0.1.56`.

`make build`, `make test` (nine checks), and `make integration` (eight official
engine checks) pass. An independent source copy under `/var/tmp`, with no
ancestor workspace configuration, also compiles the bot, builds the native
adapter, passes unit checks and builds the WASM viewer using pinned dependencies.
A 600-tick colony-versus-idle match from the standalone `/tmp` source copy
scores `[290,0]`, matching the existing certification control. Its artifacts are
`~/.local/share/screeps-pw/matches/20261009T020216Z-t72aZ7nE/`.

`make package VERSION=0.1.2` builds using the public runtime and public SDK.
`make certify` passes all ten executable steps, with artifacts at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-n2a_wlkf/`.
The browser checks pass against the previous full 4×4 competition replay;
the resulting image is included at `docs/viewer.png`.
This preparation does not upload a new Coworld or change the hosted league.

## Centered starts correction — 0.1.3

The starts now occupy zero-based viewer cells `(1,1)` and `(2,2)`: W3N3
`(37,31)` and W2N2 `(17,40)`. The native terrain and 4×4 room set are retained.
W3N3 has one native source and W2N2 has two; paired starting assignments retain
both seat evaluations. The viewer opens the first seat's recorded starting
spawn, so older replays continue to open their original starting room.

All ten unit checks and eight disposable-engine checks pass. Native integration
checks actual account-owned spawns against the two central cells and verifies
travel between them. Both 300-tick and full 6,000-tick replays pass the browser
checks. The full colony-versus-colony match scores `[2978,10031]` in 155.724
seconds, with no policy/runtime errors. Artifacts are at
`~/.local/share/screeps-pw/centered-duels/20261009T022042Z-0jlmmsw8/`.
The current screenshot is `docs/viewer.png`.

The rebuilt game image is
`sha256:86729e7028aa18147cf2338ac9be8eea3737ce7847593019045711919af1dc04`.
Local executable certification passes all ten steps, with artifacts at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-cf96jvn5/`.

Softmax passes all ten hosted certification steps and five upload smoke
episodes. Public 0.1.3 is `cow_37c46e16-5caa-46df-8dd0-badceb64cf64`, manifest
hash `sha256:6861fb500fedc2d1fffa51de3d7e2fda8e2a21b4d464b9e5677513a7094543da`.
The existing league's game and canonical pointers both resolve to this package.
Hosted smoke `ereq_307d763f-cff1-44af-882a-66634e2b528d` decodes to 600 ticks,
16 rooms and starting rooms `[W3N3,W2N2]`. Its downloaded replay is
`~/.local/share/screeps-pw/centered-hosted.replay`; the upload transcript is
`~/.local/share/screeps-pw/centered-upload.log`. A new round was requested after
verifying the canonical pointer; its acknowledgement is
`~/.local/share/screeps-pw/centered-trigger-round.json`.
