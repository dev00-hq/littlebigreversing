# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep guarded load set stable: `19/19`, `2/2`, `11/10`; `44/2` rejects as exterior.
- Keep `LM_DEFAULT`, `LM_END_SWITCH`, `life_audit`, `room_state`, and debugger owner boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, tool-only same-index triage.

## Active Streams

- Phase 5 runtime/gameplay widening is current, with Phase 4 Branch A already settled.
- Viewer/load widening stays on `19/19`, `2/2`, and `11/10`.
- Original runtime uses direct save launch (`LBA2.EXE <save>.LBA`) plus `Enter`.
- Guarded `2/2` public exit is backed as exterior-facing `ChangeCube`; the port rejects it as `unsupported_exterior_destination_cube`.
- `3/3` blockers stay rejected; live zone-`1` cube-`19` handoff lands in a Tralu's-dungeon-looking scene, not the intended cellar target.
- `0013` door is scene-2 zone `0`: house/key side `2/1 -> 2/0` consumes one key and lands `(2562,2048,3322)` after shadow; cellar return `2/0 -> 2/1` is free and lands `(9725,1024,1098)`.
- `0013` key source is scene `2/1` default action: `LF_ACTION`, zone `0`, beta bounds, `gameVar(0)==0`, then `KILL_OBJ 7`, `FOUND_OBJECT 0`, `SET_VAR_GAME 0 1`.
- `0013` key pickup is poll-only proved on house side: `SPRITE_CLE`, `Divers=1`, `NbLittleKeys 0 -> 1`; viewer drives W, pickup overlay, keyed entry, and free return.
- Viewer HUD uses the tabbed right sidebar; `C` switches info/controls.
- Guarded `19/19` object-`2` is stateful; sewer chest is bounded multi-bonus with live-backed `Divers=5`.

## Blocked Items

- Guarded `19/19` pickup gating is still admitted footing plus same-`top_y` and proximity, not proved same-surface/floor-band.
- Guarded `2/2` `change_cube` is exterior-facing, not an interior handoff proof.
- `3/3` is not a solved cellar handoff; zone `1` live-proves globals but lands in the wrong scene, and zone `8` remains unproved.
- Room `36/36` page 2 is renderer pagination inside one decoded record; only mid-dialog save/load proof remains open.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.

## Next Actions

- Reopen wall mapping only if a bounded navigation slice proves it is the bottleneck.
- For cellar work, stay on the scene-2 zone-`0` secret-room seam; do not promote the `3/3` zone-`1` dungeon handoff.
- Use `secret_room_door_watch.py` for door snapshots; prefer Frida/read-only over CDB for manual key-source loops.
- Frida rule: internal `DoLifeLoop` instruction sites use function/probe form; live `SPRITE_CLE` proof is enough for `0013`.
- Otherwise choose the next bounded Phase 5 seam from an existing guarded gameplay slice.
- Treat guarded `19/19` reward-model work as settled unless a pickup-surface bug or contradiction appears.
- Use `dialog_text_dump.py` for further room-36 live proof.

## Relevant Subsystem Packs

- architecture
- backgrounds
- intelligence
- life_scripts
- platform_windows
- scene_decode
