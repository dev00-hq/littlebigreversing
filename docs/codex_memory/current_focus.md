# Current Focus

## Current Priorities

- Phase 5 remains active; the `0013` key-door-cellar slice is closed.
- Keep `codex-memory-v2`, guarded loads, and additive validation canonical.
- Preserve life/room/debugger boundaries.

## Active Streams

- Guarded loads: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects.
- `0013` is closed: proof doc, fixture, and promotion packet cover save load, key pickup, key-consume door, cellar entry, and Down-return.
- Runtime/gameplay seam widening requires `docs/promotion_packets/`; `tools/validate_promotion_packets.py` enforces the `canonical_runtime` status gate.
- `inspect-room-transitions 2 1/2 0 --json` exposes no-key lock, key consumption, and synthetic free cellar return; for `0013`, read runtime fields over decoded rows.
- Original runtime CD startup uses Alcohol `E:` mounted from `work/runtime_media/lba2_mixed_mode/LBA2_TWINSEN_mixed.cue`; do not reinstall the narrow local WinMM proxy as the default launch path.
- The WinMM proxy is now opt-in instrumentation: `LBA2_RUNTIME_WATCH=1` records `life_loss_detected` rows from `ListVarGame[FLAG_CLOVER]` (`0x0049A08E`).
- Named saves use globals + pose + `SaveGame(TRUE)`; loads use `LBA2.EXE SAVE\<name>.LBA` with autosave guard.

## Blocked Items

- `2/2` is not solved interior handoff/locomotion semantics.
- `187/187` gameplay/transition beyond startup seed is unproved. The prior teleport probe snapped to `(28416,2304,21760)` with `zones=[]`, `new_cube=-1`, and clover/life-loss evidence; treat it as invalid teleport/death/safety reset, not a transition.
- `inside dark monk1.LBA` proves only a cube-`185` save with raw scene entry `187`.
- Room `36/36` page 2 is renderer pagination; no save/load during active dialog.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails; fragment-zone CLI reports aligned-origin candidates.

## Next Actions

- For `0013`, maintain only: assert the proof doc, fixture, and runtime-aware `inspect-room-transitions`.
- Before reopening `187/187`, run a fresh proof with mixed-mode CD mounted and life-loss watcher enabled; require target-zone membership or `NewCube/NewPos`, not screenshots.
- `3/3` remains decode-only/live-negative for gameplay: zone `1` membership appeared briefly, but no `NewCube=19`/`active_cube=19`; Twinsen fell to `y=1024`.
- Keep promotion packets current when widening Phase 5 seams; decoded candidates can stay visible in tooling, but runtime commits require `live_positive` or `approved_exception`.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
