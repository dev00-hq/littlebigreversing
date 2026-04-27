# Current Focus

## Current Priorities

- Phase 5 runtime/gameplay widening is current.
- Keep `codex-memory-v2`, guarded loads, and additive validation canonical.
- Preserve life/room/debugger boundaries.

## Active Streams

- Guarded loads: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects.
- Port `187/187` zone `1` cube `185` still rejects decoded landing `(13824,5120,14848)` as `unsupported_destination_height_mismatch`.
- Live `187/187` run4 proves source `(1536,256,4608)` lands at `(28416,2304,21760)` without syncing `SceneStart`; saved `StartCube=(55,11,44)` appears to drive this same-cube landing.
- `2/2` public exit rejects as exterior; `3/3` zones `1`/`8` commit as Tralu; zone `15` rejects.
- Original runtime uses the checked-in WinMM MCI proxy shim.
- `0013` fixture `tools/fixtures/phase5_0013_runtime_proof.json` covers CLI save load, key pickup, key-consume door, cellar entry, and Down-return.
- `0013` source is scene `2/1` default action; pickup is `SPRITE_CLE`, `Divers=1`, `NbLittleKeys 0 -> 1`.
- `inspect-room-transitions 2 1/2 0 --json` exposes no-key lock, key consumption, and synthetic free cellar return.
- Named saves use globals + pose + `SaveGame(TRUE)`; loads use `LBA2.EXE SAVE\<name>.LBA` with autosave guard.

## Blocked Items

- `2/2` is not solved interior handoff/locomotion semantics.
- `187/187` gameplay beyond startup seed/zone-1 is unproved.
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
