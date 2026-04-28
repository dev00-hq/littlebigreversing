# Current Focus

## Current Priorities

- Phase 5 remains active; the `0013` key-door-cellar slice is closed.
- Keep `codex-memory-v2`, guarded loads, and additive validation canonical.
- Preserve life/room/debugger boundaries.

## Active Streams

- Guarded loads: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects.
- `0013` is the completed Phase 5 slice: `tools/fixtures/phase5_0013_runtime_proof.json` and `docs/PHASE5_0013_RUNTIME_PROOF.md` cover save load, key spawn/pickup, key-consume door, cellar entry, and Down-return.
- `inspect-room-transitions 2 1/2 0 --json` exposes no-key lock, key consumption, and synthetic free cellar return; for `0013`, read runtime fields over decoded rows.
- Original runtime CD startup uses Alcohol `E:` mounted from `work/runtime_media/lba2_mixed_mode/LBA2_TWINSEN_mixed.cue`; do not reinstall the narrow local WinMM proxy as the default launch path.
- The WinMM proxy is now opt-in instrumentation: `LBA2_RUNTIME_WATCH=1` records `life_loss_detected` rows from `ListVarGame[FLAG_CLOVER]` (`0x0049A08E`).
- Named saves use globals + pose + `SaveGame(TRUE)`; loads use `LBA2.EXE SAVE\<name>.LBA` with autosave guard.

## Blocked Items

- `2/2` is not solved interior handoff/locomotion semantics.
- `187/187` gameplay/transition beyond startup seed is unproved. The prior teleport probe snapped to `(28416,2304,21760)` with `zones=[]`, `new_cube=-1`, and clover/life-loss evidence; treat it as invalid teleport/death/safety reset, not a transition.
- `inside dark monk1.LBA` only proves a cube-`185` save with raw scene entry `187`; it does not prove decoded `187/187` coordinates are valid in the loaded runtime frame.
- Room `36/36` page 2 is renderer pagination; no save/load during active dialog.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails; fragment-zone CLI reports aligned-origin candidates.

## Next Actions

- For `0013`, maintain only: assert the proof doc, fixture, and runtime-aware `inspect-room-transitions`.
- Before reopening `187/187`, run a fresh proof with mixed-mode CD mounted and life-loss watcher enabled; require target-zone membership or `NewCube/NewPos`, not screenshots.
- Otherwise choose the next bounded Phase 5 seam from an existing guarded gameplay slice.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
