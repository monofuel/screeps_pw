# screeps_pw

## Purpose and current scope

Make Screeps a Polyworld/Coworld-shaped game that can be submitted to Softmax
and run as a league. This repository owns the game integration and league
package. It is separate from our playing bots and bot-research dashboard.

- Read this file before working here. If a parent workspace has additional
  instructions, read those too; a standalone clone needs no sibling projects.
- Read [README.md](README.md) for the current match contract, commands,
  references, and measured implementation status.
- The user has authorized implementing the first league MVP: 6,000 completed
  ticks, native JavaScript policies, unpaced official simulation, recorded-state
  3D Polyworld viewing, packaging, certification, and initial hosted operation.
- Keep the MVP simple: one fixed 4×4 world. Do not add configurable map generation
  or broader game modes unless requested.
- Start the players at zero-based viewer cells (1,1) and (2,2), the central
  diagonal rooms W3N3 and W2N2. Do not move the starts to an outer corner.
- Preserve existing user work. Commit, push, deploy, upload a Coworld release,
  or create/enable a hosted league only when requested.

## Repository boundaries and reuse

- `screeps_pw` owns the native Screeps policy loading and tournament adapter,
  finite match rules, replay capture/viewer, Coworld packaging, and integration
  tests. Use Screeps' existing JavaScript runtime; do not add Bassy or a new
  observation/action language.
- `players/colony` contains a public snapshot of the author's World bot,
  reusable `botlib` behaviors, and World bindings. Reuse those behaviors rather
  than copying new bespoke bots. Keep the league adapter separate from strategy.
- `runtime/shared` contains the small shared Node bridge, JSON decoder and
  completed-turn scheduler. The build must work without private sibling repos.
- The upstream workspace repositories `screeps_bot`, `screeps_lib`, and
  `screeps_autoresearch` own continued bot research, bindings, and benchmarks.
  Read their instructions before working there; this repository's tests and
  league rules do not change benchmark contracts or staging services.
- Read the target repository's instructions before changing any sibling.
  Leave tutorial repositories and older experiments outside the task.
- Use the pinned public Nimby dependencies. Heartleaf is a reference for
  shipping games with example players; Mindustry's Coworld demonstrates the
  original-engine adapter pattern. Inspect actual interfaces before reuse.
- Prefer an official Screeps engine integration. Do not reimplement Screeps
  simulation or port it into a 3D engine without an explicit design decision.
- Reuse small modules when they fit. Do not copy an entire research runner,
  fork shared policy infrastructure, or invent a universal game framework to
  avoid proving the first end-to-end match.

## Language and implementation

- Use **Nim, not Python**, for project code, tests, research tools, automation,
  engine glue, and viewer logic. Do not add handwritten JavaScript/TypeScript
  source or shell scripts. Existing upstream Screeps JavaScript is a dependency.
- Generate JavaScript with Nim's JS backend for Node/Screeps integration;
  generate browser code with the appropriate Nim backend. Edit Nim source,
  never generated outputs.
- Participants submit ordinary Screeps JavaScript modules exporting `loop`.
  Submitted JavaScript is a participant artifact, not permission to author
  project tooling in JavaScript. Our reference bots remain Nim compiled to JS.
- Run matches without inter-tick pacing, advancing as soon as the official
  engine commits the previous turn. End on declared game conditions or completed
  tick horizon, with no fixed whole-match wall-clock timeout. Do not confuse this
  with script CPU/memory limits. Each seat receives 20 CPU and an empty initial
  bucket; native replenishment, execution guards, and memory limits remain.
  Hosted episodes also have the platform's mandatory 100-minute watchdog.
- Use Nimby + Make, never Nimble commands. Keep compiler settings in
  `config.nims` and dependency paths in the chosen Nimby workspace. Inspect the
  workspace before syncing; do not move dirty sibling checkouts.
- Use one grouped import block, ordered standard library, dependencies, local
  modules. Group related declarations and keep modules small.
- Let low-level errors propagate. Handle failures at policy, engine, and match
  boundaries with explicit diagnostics. Never silently discard exceptions.

## Match integrity

- Define and version roster mapping, starting assets, terrain, visibility,
  actions, budgets, ending conditions, scoring, and ties before publishing.
  Distinguish game-engine rules from deliberate league-specific rules.
- Preserve native `Game`, `Memory`, visibility, and intent processing. Let the
  official runner execute account scripts and the engine resolve their intents.
  Inspect completed turns before advancing; do not create a second action loop.
- Retain the official per-account script sandbox and disposable match isolation.
  Administrative database access belongs to trusted tournament code. Do not run
  submitted modules directly in the coordinator's Node environment.
- Settle equal per-account CPU/bucket and memory rules independently of tick
  pacing. Preserve native execution guards unless the user explicitly chooses
  to change them. Bound uploads and logs; isolate policy failures and distinguish
  them from engine/coordinator failures. Existing benchmark isolation alone is
  not evidence that public untrusted-policy containment has been verified.
- Treat source/VM failure, illegal game actions, normal loss, and infrastructure
  error as different outcomes. Decide score treatment explicitly rather than
  disguising a failed or incomplete run as a completed match.
- Freeze engine, host, bindings, policy hashes, configuration, seed, and turn
  horizon for comparisons. A seed alone is not proof of repeatability.
- Keep league results, earned GCL diagnostics, funding, and physical capability
  evidence distinct. Existing World benchmark numbers do not establish PvP
  strength or hosted league standing.

## Verification and operations, once implemented

- Provide thin Make targets backed by Nim automation. Run `make test` in every
  affected repository; use `make integration` for real disposable-engine checks.
  Run `make build` for bot changes and compile consumers of binding changes.
- Check native modules with `nim check`; check game-facing modules with
  `nim js`. Unit tests, compilation, engine matches, and hosted certification
  are separate evidence. Do not report one as another.
- Use disposable worlds with no staging volume or public game/admin ports.
  Never reset, change speed, or deploy to the persistent private World as part
  of this project. Keep live research services and their queue settings intact.
- Keep replays, logs, databases, generated outputs, and bulk diagnostics outside
  Git, preferably under `~/.local/share/screeps-pw/`. Retain compact commands,
  versions, hashes, artifact references, and decisions in documentation.
- Finish replay and private outputs before publishing the results completion
  marker. Verify the current platform contract locally before requesting a
  release upload. Certification success is not authorization to publish.
- Preserve upstream license notices and verify rights for distributed assets.
  Do not copy proprietary client assets into the replay viewer.
