# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Keep guarded load set stable: `19/19`, `2/2`, `11/10`; `44/2` rejects as exterior.
- Keep `LM_DEFAULT`, `LM_END_SWITCH`, `life_audit`, `room_state`, `cdb-agent`, and `ghb` on current owner boundaries.
- Keep validation additive: `zig build test-fast`, `zig build test-cli-integration`, and tool-only same-index triage.
- Keep debug control on `debug_compass` + `heading_inject` + `waypoint_step_probe`.

## Active Streams

- Phase 5 runtime/gameplay widening is current, with Phase 4 Branch A already settled.
- Viewer/load widening stays on `19/19`, `2/2`, and `11/10`.
- Original-runtime launch uses direct save launch (`LBA2.EXE <save>.LBA`) plus `Enter`; the EA-logo gate is skipped.
- Guarded `2/2` public exit is Frida + `cdb` backed as exterior-facing `ChangeCube`; the port rejects it as `unsupported_exterior_destination_cube`.
- `3/3` blockers stay rejected; live zone-`1` cube-`19` handoff lands in a Tralu's-dungeon-looking scene, not the intended cellar target.
- `0013-weapon.LBA` secret-room door is scene-2 zone `0`; cube `1` resolves to scene `2` / background `1`, cube `0` resolves to scene `2` / background `0`, and the live-backed landing commits at `(2562,2048,3322)` after classic-style shadow readjustment.
- Guarded `19/19` object-`2` is stateful; sewer chest is bounded multi-bonus with live-backed `Divers=5`.

## Blocked Items

- Guarded `19/19` pickup gating is still admitted footing plus same-`top_y` and proximity, not proved same-surface/floor-band.
- Guarded `2/2` `change_cube` is exterior-facing, not an interior handoff proof.
- `3/3` is not a solved cellar handoff; zone `1` live-proves globals but lands in the wrong scene, and zone `8` remains unproved.
- Room `36/36` page 2 is renderer pagination inside one decoded record; only mid-dialog save/load proof remains open.
- Wall mapping is deferred.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.

## Next Actions

- Use `waypoint_step_probe.py` as the step primitive for debug-control work.
- Reopen wall mapping only if a bounded navigation slice proves it is the bottleneck.
- For cellar work, stay on the scene-2 zone-`0` secret-room seam; do not promote the `3/3` zone-`1` dungeon handoff.
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
