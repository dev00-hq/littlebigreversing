# Current Focus

## Current Priorities

- Phase 5 runtime/gameplay widening is current.
- Keep `codex-memory-v2`, guarded loads, and additive validation canonical.
- Preserve life/room/debugger boundaries.

## Active Streams

- Guarded loads: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects.
- Port `187/187` zone `1` cube `185` still rejects decoded landing `(13824,5120,14848)` as `unsupported_destination_height_mismatch`.
- `187/187` runtime probe is invalidated: teleporting to `(1536,256,4608)` immediately snapped to `(28416,2304,21760)` with `zones=[]`, `new_cube=-1`, and a clover/life-loss indicator. Treat this as invalid teleport/death/safety reset, not a transition.
- `inside dark monk1.LBA` is only proven as a cube-`185` save with raw scene entry `187`; it is not proof that decoded `187/187` coordinates are valid in the loaded runtime frame.
- Life loss must be detected by runtime evidence: the WinMM proxy's `LBA2_RUNTIME_WATCH=1` path records no-debugger `life_loss_detected` rows from `ListVarGame[FLAG_CLOVER]` (`0x0049A08E`); `tools/life_trace/life_loss_cdb_watch.py` is reserved for exact writer-stack proof.
- `2/2` public exit rejects as exterior; `3/3` zones `1`/`8` commit as Tralu; zone `15` rejects.
- Original runtime uses the checked-in WinMM MCI proxy shim.
- `tools/life_trace/runtime_watch_run.py --scenario phase5-0013-door` is the current no-CDB Phase 5 runtime watcher runner: it hides autosave, validates exact 0013 direct-save coordinates, enables `LBA2_RUNTIME_WATCH=1`, captures screenshots, and records cellar-door transition snapshots.
- `0013` fixture `tools/fixtures/phase5_0013_runtime_proof.json` covers CLI save load, key pickup, key-consume door, cellar entry, and Down-return.
- `0013` source is scene `2/1` default action; pickup is `SPRITE_CLE`, `Divers=1`, `NbLittleKeys 0 -> 1`.
- `inspect-room-transitions 2 1/2 0 --json` exposes no-key lock, key consumption, and synthetic free cellar return.
- Named saves use globals + pose + `SaveGame(TRUE)`; loads use `LBA2.EXE SAVE\<name>.LBA` with autosave guard.

## Blocked Items

- `2/2` is not solved interior handoff/locomotion semantics.
- `187/187` gameplay/transition beyond startup seed is unproved; before any new teleport proof, validate the loaded scene/background coordinate frame and require target-zone membership or `NewCube/NewPos` staging.
- Room `36/36` page 2 is renderer pagination; no save/load during active dialog.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails; fragment-zone CLI reports aligned-origin candidates.

## Next Actions

- For cellar work, stay on scene-2 zone `0`; `3/3` zones `1`/`8` are Tralu.
- Use `inspect-room-transitions <scene> <bg> --json`; for `0013`, read runtime fields.
- Save helpers: overwrite only, never `CurrentSaveGame()`, then CLI reload with memory coordinates.
- For `0013` changes, assert `docs/PHASE5_0013_RUNTIME_PROOF.md` and the fixture first.
- Otherwise choose the next bounded Phase 5 seam from an existing guarded gameplay slice.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
