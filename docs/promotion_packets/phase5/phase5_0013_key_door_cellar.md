# Phase 5 0013 Key Door Cellar

## Packet Identity

- `id`: `phase5_0013_key_door_cellar`
- `status`: `live_positive`
- `evidence_class`: `zone_transition`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: scene `2`, background `1` house to scene `2`, background `0` cellar, then return to scene `2`, background `1`
- source: scene `2`, background `1`, active cube `0`, keyed house doorway
- destination: scene `2`, background `0`, active cube `1`, cellar entry; return destination scene `2`, background `1`, active cube `0`
- trigger: collect the W-spawned key, walk through the keyed door, then use Down to return from the cellar

## Decode Evidence

`inspect-room-transitions 2 1 --json` and `inspect-room-transitions 2 0 --json` expose the scene-2 door paths. The canonical runtime-aware details are in `docs/PHASE5_0013_RUNTIME_PROOF.md` and `tools/fixtures/phase5_0013_runtime_proof.json`; use runtime fields over decoded rows for this seam.

## Original Runtime Live Evidence

`tools/fixtures/phase5_0013_runtime_proof.json` records a generated-save launch, W key spawn and pickup, key consumption on the house-to-cellar transition, active cube `0 -> 1`, `NewPos=(9723,1277,762)`, and the free cellar return with active cube `1 -> 0`.

## Runtime Invariant

The promoted invariant is the narrow scene `2/background 1 -> scene 2/background 0 -> scene 2/background 1` gameplay slice: key pickup mutates runtime state, the door consumes the key during cellar entry, and the return path is free.

## Positive Test

- `tools/test_phase5_0013_runtime_proof.py`
- `port/src/runtime/update_test.zig` fixture-backed 0013 runtime assertions
- `port/src/tools/cli_room_load_integration_test.zig` 0013 `inspect-room-transitions` assertions

## Negative Test

`port/src/tools/cli_room_load_integration_test.zig` keeps this seam distinct from rejected or decode-only room paths, including the older `3/3` cellar-source candidates and public exterior `2/2` paths.

## Reproduction Command

```powershell
py -3 -m unittest tools.test_phase5_0013_runtime_proof
```

## Failure Mode

If the fixture, proof doc, or runtime-aware transition assertions are absent, do not widen beyond this exact seam. Fail with a diagnostic that names the missing `phase5_0013_key_door_cellar` packet or fixture rather than falling back to decoded rows.

## Docs And Memory

- `docs/PHASE5_0013_RUNTIME_PROOF.md`
- `tools/fixtures/phase5_0013_runtime_proof.json`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`

## Old Hypothesis Handling

Older `3/3` Tralu/cellar handoff framing is not part of this promoted seam. The canonical `0013` path is scene `2/background 1 -> scene 2/background 0 -> scene 2/background 1`.

## Revision History

- 2026-04-29: Backfilled the closed 0013 runtime proof into the promotion-packet gate.
