# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep guarded load set stable: `19/19`, `2/2`, `11/10`, `187/187`; `44/2` rejects as exterior.
- Preserve `LM_DEFAULT`, `LM_END_SWITCH`, `life_audit`, `room_state`, and debugger ownership boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, tool-only same-index triage.

## Active Streams

- Phase 5 runtime/gameplay widening is current.
- Viewer/load widening stays on guarded `19/19`, `2/2`, `11/10`, and `187/187`; `187/187` still starts `raw_invalid_start`.
- Guarded `2/2` public exit is exterior-facing `ChangeCube` and remains `unsupported_exterior_destination_cube`.
- `3/3` zones `1`/`8` now commit as Tralu: cube `19 -> 21/19`, `20 -> 22/20`; zone `15` remains unsupported.
- Original-runtime CD gate uses the run3 MCI shim until mixed-mode media is proved.
- `0013` door is scene-2 zone `0`: `2/1 -> 2/0` consumes one key and lands `(2562,2048,3322)` after shadow; `2/0 -> 2/1` is free and lands `(9725,1024,1098)`.
- `0013` key source is scene `2/1` default action gated by `gameVar(0)==0`; it kills obj `7`, grants obj `0`, and sets `gameVar(0)=1`.
- `0013` key pickup is poll-only proved on house side: `SPRITE_CLE`, `Divers=1`, `NbLittleKeys 0 -> 1`.
- `inspect-room-transitions 2 1/2 0 --json` exposes no-key lock, key consumption, and the synthetic free cellar return.
- Original-runtime named saves: direct globals + pose context + `SaveGame(TRUE)`; `CurrentSaveGame()` is `current.lba` only. Load with `LBA2.EXE SAVE\<name>.LBA` while autosave is hidden/restored; Frida observes/shims only.

## Blocked Items

- Guarded `19/19` pickup gating is still admitted footing plus same-`top_y`/proximity, not proved same-surface/floor-band.
- Guarded `2/2` and `187/187` are not solved interior handoff or locomotion semantics.
- Room `36/36` page 2 is renderer pagination; save/load is unsupported while dialog is active.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails `InvalidFragmentZoneBounds`.

## Next Actions

- Reopen wall mapping only if a bounded navigation slice proves it is the bottleneck.
- For cellar work, stay on scene-2 zone `0`; `3/3` zones `1`/`8` are Tralu, not cellar evidence.
- Use `inspect-room-transitions <scene> <bg> --json`; for `0013`, read runtime no-key/with-key/synthetic-return fields.
- Use `secret_room_door_watch.py`; prefer Frida/read-only over CDB for manual key-source loops.
- Internal `DoLifeLoop` instruction hooks use function/probe form; live `SPRITE_CLE` proof is enough for `0013`.
- Save helpers: overwrite only, never `CurrentSaveGame()`, then CLI-argv reload with autosave guard and memory coordinates.
- Otherwise choose the next bounded Phase 5 seam from an existing guarded gameplay slice.
- Use `dialog_text_dump.py` only if room-36 needs more original-runtime proof; do not model save/load during active dialog.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
