# Scene Decode

## Purpose

Own the typed `SCENE.HQR` metadata model, parser, zone semantics, and track-program decoding that power `inspect-scene`.

## Invariants

- Keep `port/src/game_data/scene.zig` as the stable public facade.
- Preserve raw `track_bytes` and raw `life_bytes`; only track instructions are scene-surface derived data today.
- Keep raw HQR entry numbers distinct from classic loader scene numbers.

## Current Parity Status

- Typed scene metadata decoding is implemented and asset-backed.
- Zone semantics and track-program decoding are live.
- `inspect-scene --json` is the canonical scene inspection surface.

## Known Traps

- `SCENE.HQR[0]` is reserved loader state, so real scene numbering is offset.
- Scene tests are asset-backed; `zig build test` is not a stripped-down unit-only pass.
- `zig build test-fast` is the daily loop and omits the isolated all-scene life-audit inventory shard plus the slower asset-backed CLI room/load coverage; use `zig build test-cli-integration` for bounded room/load checks, and use `zig build tool -- triage-same-index-decoded-interior-candidates --json` only when you deliberately want the heavier same-index triage workload.

## Canonical Entry Points

- `port/src/game_data/scene.zig`
- `port/src/game_data/scene/parser.zig`
- `port/src/game_data/scene/model.zig`

## Important Files

- `port/src/game_data/scene/zones.zig`
- `port/src/game_data/scene/track_program.zig`
- `port/src/game_data/scene/tests/`

## Test / Probe Commands

- `cd port && zig build tool -- inspect-scene 2 --json`
- `cd port && zig build tool -- inspect-scene 44 --json`
- `cd port && zig build test-fast`
- `cd port && zig build test`

## Open Unknowns

- Which scene metadata should move from inspection-oriented ownership into the canonical `runtime` surface as room-state extraction continues.
- Which future scene-facing work should stay in this pack versus moving into runtime once viewer/runtime ownership is fully separated.
