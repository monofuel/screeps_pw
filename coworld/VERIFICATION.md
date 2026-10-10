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

## Automatic room viewing — 0.1.4

Auto uses visible playing time, with a strict 30-second room hold and instant
cuts to the fixed whole-room framing. Recent combat outranks controller and
building changes; quiet rooms with player creeps or spawning are toured in
least-recently-shown order. Manual room selection and 3D interaction disable
Auto until resumed. Seeks and loops clear event history and restart the hold;
pause, hidden tabs, map pan/zoom, and divider controls retain their documented
behavior. Replay data and simulation rules are unchanged.

All 19 unit checks pass, including nine director scenarios. Native checks and
the WASM build pass. Headless Chromium checks the full centered 6,000-tick
colony-versus-colony replay: the hold also applies at 20x playback, Auto cuts
update the map outline and framing, Manual remains active beyond 30 seconds,
and resuming Auto starts a fresh hold. Room clicks, scene clicks, 3D pan/zoom,
map controls, divider resize, transport, canvas resize and missing-file errors
are also checked.

```sh
make test
nim check src/replayDirector.nim
nix develop . --command nim check viewer/viewer.nim
make package VERSION=0.1.4 GAME_IMAGE=screeps-pw:0.1.3
make director-browser-test REPLAY=~/.local/share/screeps-pw/centered-duels/20261009T022042Z-0jlmmsw8/match.replay
make certify
```

The package reuses game image
`sha256:86729e7028aa18147cf2338ac9be8eea3737ce7847593019045711919af1dc04`.
The baseline and both adapter module hashes match 0.1.3. Local executable
certification passes all ten steps; artifacts are at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-asc5teut/`.

The final local browser run is at
`~/.local/share/screeps-pw/browser/check-uVEr8aDf/`.
Public 0.1.4 is `cow_5716632f-dfaf-4019-ac24-eb1485b039e0`, manifest hash
`sha256:2f4386a4385f89ad81883dd6c1b099f5c1b213588b9e14b8eb4f0b0bd3efd43c`.
Softmax passes all ten hosted certification steps and five upload smoke episodes.
Both the existing game's current and canonical pointers resolve to 0.1.4;
league settings are unchanged. Both 0.1.3 and 0.1.4 use the same hosted game
image, `public.ecr.aws/q5f4m8t9/cogames@sha256:f09d989a0e4cf33ce548db817208f15ad2d4ae19bf7fc11874c59960ba7c5247`.

The actual hosted viewer passes the browser interaction checks against smoke
`ereq_5e0e8061-c040-4fdb-9411-351d1824dc6e`. Its replay decodes to 600 ticks,
16 rooms, starting rooms `[W3N3,W2N2]` and scores `[16,0]`; the file is
`~/.local/share/screeps-pw/auto-view-hosted.replay`.
The upload transcript is `~/.local/share/screeps-pw/auto-view-upload.log`, and
the requested fresh round's acknowledgement is
`~/.local/share/screeps-pw/auto-view-trigger-round.json`.

## Matched home rooms and 5 MiB policies — 0.1.5

W3N3 now copies W2N2's terrain, two sources, controller and mineral under a
180-degree rotation. Spawn positions are `(32,9)` and `(17,40)` in the same
central rooms. Home-room entrances occupy border tiles 23–26, with matching
neighbor entrances. Other rooms retain their resources and layouts apart from
exit connections; the surrounding world remains asymmetric. Account budgets,
starting assets, score rules and match horizon are unchanged.

The upload limit is 5,242,880 file bytes, inclusive. Local and game-hosted
staging use the same size predicate and error message. Empty files are rejected.
The limit is a single-file artifact contract; Screeps' ordinary code-upload HTTP
endpoint separately measures serialized module length.

All 22 unit checks and nine disposable-engine checks pass. They verify rotated
terrain and entities, matching source state, unique IDs, database indexes,
accessible harvesting tiles, sealed outer borders, both directions of native
travel and native execution of an exact-5-MiB policy. `make upload-integration`
passes two packaged-game checks: both seats load files above the former limit,
including exactly 5 MiB; empty and oversized policies report the correct failed
seat and do not publish normal results. Native checks, `make check`, the WASM
build, and full-replay browser interactions pass.

Two concurrent full 6,000-tick baseline self-play matches both score
`[9667,10012]`. Each colony finishes with its original spawn, RCL2 and 13 creeps;
neither has a policy/runtime error. These are growth diagnostics, not proof of
equal outcomes or a fully symmetric world. The runs take 195.584 and 195.932
seconds; artifacts are respectively:

- `~/.local/share/screeps-pw/fair-selfplay-1/20261009T192352Z-yXyg6Vf5/`
- `~/.local/share/screeps-pw/fair-selfplay-2/20261009T192352Z-rdSN8nFF/`

The baseline remains
`e802d48f0277ca04d47f744e6fe099ec708afbdccbe0684f4bc76e679295f54f`.
The frozen fixture hash is
`69a868ac4da24617fe6b0587ec442fc305761c855b02422b16189f653be03e3a`;
launcher and control hashes are
`86d15a7dbe5411eb6db6159eaad100eef9f9cbf67433f1085b40ca6fa601dba8`
and `d2142a476efd19d14b5aba96cbcd6aa6227fa0409916fd3b4863374669ffa3b4`.

The rebuilt game image is
`sha256:5b531eab8739acac586e6e5e754d9d6560d0d6177c90609d04bb25b8b765f372`.
Local certification passes all ten steps; artifacts are at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-kza90r38/`.
Browser artifacts are at `~/.local/share/screeps-pw/browser/check-InyJv8Rj/`,
and the verified new layout is pictured in `docs/viewer.png`.

```sh
make test
make check
nim check src/worldFixture.nim
make integration
make upload-integration VERSION=0.1.5
make certify
build/match build/players/baseline.js build/players/baseline.js --output:/home/monofuel/.local/share/screeps-pw/fair-selfplay-1
build/match build/players/baseline.js build/players/baseline.js --output:/home/monofuel/.local/share/screeps-pw/fair-selfplay-2
make browser-test REPLAY=~/.local/share/screeps-pw/fair-selfplay-1/20261009T192352Z-yXyg6Vf5/match.replay
```

Source commit `90f113d154eb676cf3fe2af4373817a7c87e2bb1` is pushed to the public
GitHub repository. Public 0.1.5 is `cow_98df377c-dcd7-4a79-b4d9-8618704acffe`,
manifest hash
`sha256:74f7bf3a4f5352b3de5584251529be804e49ec95e5c4e8e73ba18610b6b8cbf3`.
Its rebuilt hosted image is
`public.ecr.aws/q5f4m8t9/cogames@sha256:63d3ea87a29f11413dc6cc1561e95ff15b8f65daef2632a53b3e5d95774634ea`.
All ten hosted certification steps and five upload smoke episodes pass.
The existing game's current and canonical pointers both resolve to 0.1.5;
the league response is otherwise identical before and after publication.
Existing entrants, settings and historical results are preserved.

The actual hosted viewer passes the browser interaction checks against smoke
`ereq_18c7e502-b528-46db-82ba-f6dd265b9ba0`. Its 600-tick replay confirms both
home rooms have two sources and spawns at `(32,9)` and `(17,40)`; artifacts are
`~/.local/share/screeps-pw/fair-hosted.replay` and
`~/.local/share/screeps-pw/browser/check-06IWpKx6/`.
The upload transcript is `~/.local/share/screeps-pw/fair-upload.log`.
Publication uses an isolated copy of the existing user credential, preserving
the shared active-player selection. A fresh round is requested on the existing
league; the platform acknowledgement is
`~/.local/share/screeps-pw/fair-trigger-round.json`.

## ZIP/WASM submissions — 0.1.6

Single-file JavaScript retains its inclusive 5 MiB limit. ZIP32 packages accept
up to 256 flat files, 16 MiB total expanded contents and 17 MiB archive bytes.
Both runners retain the original artifact and hash, then use the same trusted
Nim-generated runtime to validate and normalize modules before the first turn.
Deflate allocation is bounded by the declared entry size, with actual lengths,
checksums and consumed input verified. Unsafe names, module collisions,
unsupported formats and overlapping records are participant failures; hosted
failures preserve the correct seat and do not publish normal results.

The independent WASM example combines an addition function, a separate
JavaScript helper and exact binary bytes into the game action spawning Zip13.
No newer private bot code is copied. The existing public colony source is
unchanged and its compiled hash remains
`e802d48f0277ca04d47f744e6fe099ec708afbdccbe0684f4bc76e679295f54f`.
The example ZIP hash is
`56de0a211646cc53285a6ea00a19ec0b7aa29c0dd1b31fae0d150a721e5a4ba6`.

All 28 unit checks, ten disposable-engine checks and five packaged staging
checks pass. Coverage includes stored/Deflate/data-descriptor packages,
extensionless staging, exact JavaScript and expanded package limits, dishonest
expansion metadata, CRC corruption, invalid paths and seat attribution. Actual
WASM-driven creeps appear in either seat separately and both seats together;
existing runtime guards, private errors and cancellation checks still pass.
Native checks, generated JS and the WASM viewer build pass.

Local certification passes all ten steps, exercising the frozen colony and
the new WASM package for 600 ticks. Certification requires every declared
example to run in its two-seat fixture, so this release declares those two
examples; idle remains a local example and prior league submissions are retained.
Artifacts are at
`~/.local/share/screeps-pw/certification/tmp/coworld-cert-mli66uib/`.
The rebuilt local image is
`sha256:ea0dda4633029c8609df22f2683602bf986e879829a6651dbb38007cfff298b7`.
Launcher and control hashes are
`9ac1d8fa3473a20987d78389b9bf739f8ce7a121d22899a1da6fec9695aee7a6`
and `be42ed1e25a2e2de493f3c2ea5f7e508348b5aa3a66a19740834f933b65724a0`.

```sh
make test
make check
make integration
make upload-integration VERSION=0.1.6
make package VERSION=0.1.6
nim r tests/test_uploadStaging.nim
make certify
```

Source commit `c629c08aa5efaef747fe534f176aa9e9a47ed249` is pushed to GitHub.
Public 0.1.6 is `cow_9af43600-fbb5-4394-9a72-506b12f39f1e`, manifest hash
`sha256:ddc44ce1a343a73bd3738eea266ac2f7da736bb51ba60df641e2bf420aab0310`.
The rebuilt hosted image is
`public.ecr.aws/q5f4m8t9/cogames@sha256:2974512cc1bb7f6bc6722145905db4d535ea0e69fe6e5c16560d071cba68ab52`.
All ten hosted certification steps and five upload smoke episodes pass. These
hosted upload smokes use the first bundled policy in both seats, so separate
WASM evidence is required. Both existing game pointers resolve to 0.1.6; the
league response is otherwise unchanged. The upload transcript is
`~/.local/share/screeps-pw/zip-upload.log`.

The public purpose-built package is uploaded as `screeps-pw-wasm-example:v1`
for isolated integration, without submitting it to the league. Experience
request `xreq_25a22faa-5cc6-4e76-9134-98d492e2fd4f` creates one 600-tick episode
on the immutable 0.1.6 release, with that package in both seats. Episode
`ereq_bfa1a662-a494-4b53-be86-12dc06e5db8e` completes without an infrastructure
error. Its recorded policy hashes match the example ZIP and both accounts own
a Zip13 creep by tick 6, proving remote execution of WASM, the JS helper and
the exact binary data. The replay is
`~/.local/share/screeps-pw/zip-hosted.replay`; the compact decoded evidence is
`~/.local/share/screeps-pw/zip-hosted-check.json`.

The actual hosted viewer passes browser interactions against this WASM replay;
artifacts are at `~/.local/share/screeps-pw/browser/check-Yz6z9FYx/`.
A fresh round is requested on the existing league; its acknowledgement is
`~/.local/share/screeps-pw/zip-trigger-round.json`. Existing entrants, standings
and historical replays are retained. Shared active-player credentials are not
changed by uploads, which use an isolated credential copy.

## 1,500-tick horizon — 0.1.7

The competition variant runs 1,500 ticks; nothing else changed. `make test`,
`make check`, `make integration` (10/10), five packaged staging checks and
local certification (10/10) pass. Public 0.1.7 is
`cow_6696737b-78a9-49d1-917c-fb988f09b7db`, manifest hash
`sha256:21235361b3ec7f021ab537d1ea2f3d5f87efc0206cde12126e1add65b8ea811c`;
hosted certification passes all ten steps. Hosted rounds 45 and 46 complete all
twelve episodes; the median episode runs 43 s and a round takes about 2 m 15 s,
against 5–9 minutes for 6,000-tick rounds. Transcripts are
`~/.local/share/screeps-pw/horizon1500-*.log`.

## Faster engine turns and fixed tick count — 0.1.8

Opt-in `PW_TIMING=1` stage timing located the per-tick cost. Replay recording
moved from Nim JSON conversions to native objects (about 6 ms to 0.55 ms per
baseline tick), the official processor no longer waits on Node's 1 ms
`setTimeout(loop, 0)` floor between rooms, and both seats run on two runner
threads. Run results are tagged with their account so private logs stay with
their seat, and runs after the first wait for it because the official
`accessibleRooms` cache returns undefined to a run that starts during its first
fetch. The privacy integration check now throws from each seat in turn.
`max_ticks` is removed from the config schema, variants, certification and the
local runner; every match runs `MatchTicks` (1,500) ticks.

Equivalence uses `nim r tools/replayDiff.nim A.replay B.replay`, which compares every tick's public
objects after replacing random object and account ids. The previous runtime
reproduces itself exactly, and the new runtime is identical to it over all
1,501 states for baseline self-play, the navigation fixture against idle, and
WASM self-play. Locally, 3-run means for 1,500 ticks move from 13.4 s to 6.9 s
idle and 35.1 s to 22.7 s baseline when three matches share the host. The
viewer passes standard and director browser checks on new 1,500-tick replays
and still opens 600- and 6,000-tick replays.

Public 0.1.8 is `cow_b493daae-4596-4642-8b0d-9f36192a4306`, manifest hash
`sha256:69d5a4d07bdb73ba82b4ec92bde0ad9447bb8bd677187a21d594b75be89a9910`,
source commit `06230e6`. Hosted certification passes all ten steps. Hosted
round 47 completes all twelve episodes without errors; the median episode
runs 22 s (max 25 s) and the round takes 1 m 34 s. Episode configs carry no
`max_ticks`. Transcripts are `~/.local/share/screeps-pw/speed-*.log`.

## Single engine process — 0.1.9

The launcher starts one engine process that loads the official storage,
runner, processor and main modules. Storage calls invoke the official storage
methods directly with the JSON copies and asynchronous replies of the RPC
client. Normalized replays remain identical to 0.1.8 for the same three
matches; only bucket values in bot console output differ. Run one at a time on
the local host, 1,500-tick means move from 5.03 s to 4.96 s idle and 19.1 s to
17.4 s baseline, and peak match memory falls from 486 MiB to 327 MiB with three
container processes instead of six.

`make test`, `make check`, `make integration` (10/10), the director browser
check, five packaged staging checks and local certification (10/10) pass.
Public 0.1.9 is `cow_752982d2-d3bd-47d1-8dd3-f4be5bc11bc3`, manifest hash
`sha256:5262a136773c2579d12d97abc37289ba6d56a498b9b871ba266c6ce862ac672e`,
source commit `6dc9bf5`. Hosted certification passes all ten steps.
Transcripts are `~/.local/share/screeps-pw/single-*.log`.
Hosted round 48 (`round_5a822cc2-0275-41a7-9e97-cdad1f1ea5b7`) runs on 0.1.9 and
completes all twelve episodes without errors in 1 m 45 s; the median episode
runs 22 s (max 26 s). Unchanged entrants score exactly as in round 47 on 0.1.8.

## Polyworld-style match length — 0.1.10

Configs again follow the Polyworld coworlds: `max_ticks` is required and accepts
1 through `MaxTicks` (8,000); the competition variant and local runner default
to `DefaultTicks` (1,500); certification runs 600 ticks. This replaces the
fixed tick count of 0.1.8 and 0.1.9. A default 1,500-tick baseline match replays
identically to 0.1.9, and a local `--ticks:8001` request is rejected.

`make test`, `make check`, `make integration` (10/10, 31 s), five packaged
staging checks and local certification (10/10) pass. Public 0.1.10 is
`cow_d9435755-061d-4997-91fc-494517d1d976`, manifest hash
`sha256:6e479f6570d79400b7fa9a45318181702e17a1e6b199214f2428a58537b04176`,
source commit `5648571`. Hosted certification passes and the league reports
this Coworld. Transcripts are `~/.local/share/screeps-pw/ticks-*.log`.
Hosted rounds 50 and 51 run on 0.1.10. Round 51 completes all twelve episodes
without errors, each with `max_ticks` 1,500, and a median episode run of 18 s.
`make round` posts the league's `trigger-round` request through `tools/api.nim`.

## Per-match folders — 0.1.11

The game server creates a private temporary folder per match under `TMPDIR`
and passes its `episode` and `world` folders to the runtime as `PW_EPISODE` and
`PW_WORLD`; without them the runtime keeps `/episode` and `/world`. This lets
one container, such as a fast-XP runner, host several matches at once.

The new packaged check starts one game container as an unprivileged user, adds
a second `/app/server` with `docker exec` while the first 600-tick match is
running, and gives the two matches opposite WASM seats. Each keeps its own
results, private logs and replay, with only its own WASM seat owning a creep.
The same check fails against the 0.1.10 image, whose server cannot create
`/episode` as that user. A default 1,500-tick baseline match replays
identically to 0.1.10.

`make test`, `make check`, `make integration` (10/10), six packaged staging
checks and local certification (10/10) pass. Public 0.1.11 is
`cow_ddcec01a-afbf-49ae-8ea1-fa0edafe2635`, manifest hash
`sha256:b168bc4a7a26a0952adf335085713278e1d26dbca852228c7b74938b6bf389ba`,
image `screeps-pw:coworld-9ae5da27c4fa`, source commit `206b8f5`. Hosted
certification passes; its five 600-tick hosted smoke episodes complete on
0.1.11 without errors, and the league reports this Coworld. The league's
platform scheduler has not started a round since 23:04 UTC on 2026-10-09, so no
league round has run on 0.1.11 yet. Transcripts are
`~/.local/share/screeps-pw/shared-*.log`.
