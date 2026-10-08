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
