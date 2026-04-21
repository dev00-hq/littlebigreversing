# Life Scripts

## Purpose

Own life-program decoding and original-runtime evidence lanes.

## Invariants

- Treat raw `life_bytes` as the scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone.
- Keep the outer harness shared and lane policy explicit.

## Current Parity Status

- `life_audit.zig` / `audit-life-programs` is canonical inventory.
- Guarded `19/19` object `2` has live-backed `Divers=5` multi-bonus semantics.
- `0013` key source is default action: W sets `ActionNormal`; `LF_ACTION`, zone `0`, beta bounds, `gameVar(0)==0` gate `KILL_OBJ 7`, `FOUND_OBJECT 0`, `SET_VAR_GAME 0 1`.
- `0013` key spawn/pickup is Frida poll-only proved: `SPRITE_CLE` at `(3072,3072,5120)`, `Divers=1`, then `NbLittleKeys 0 -> 1`; writer `0x0041737c` matches generic `SPRITE_CLE`.
- Room `36` keeps dialog id `3` across both visible Sendell pages and clears after the second ack.
- `waypoint_step_probe.py` owns debug-control outcomes; `collision_observer.py` is diagnostic-only.

## Known Traps

- Do not reuse the old unsupported-life model for `2/2` or `11/10`.
- Tavern proves live behavior; Scene11 proves ownership through debugger snapshots.
- On debug-control, `waypoint_step_probe.py` outcome is canonical.
- Do not treat the guarded `19/19` reward slice as generic pickup or save/load parity.
- Do not generalize `LM_GIVE_BONUS`; only guarded `19/19` is proved.
- Scene11 is a mismatch, not a startup failure.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- Do not revive the staged `Load Game` harness; direct save launch is canonical and must reject the EA logo.
- `0013-weapon.LBA` is the right cellar start; forced `3/3` zone `1` lands in a Tralu-looking scene.
- `0013` door source is scene-2 zone `0`; cube `1 -> 0` preserves offset before shadow readjustment.
- Reverse `0013` door is stateful and now port-backed: `NbLittleKeys 1 -> 0` precedes cube `0 -> 1`.
- Use `secret_room_door_watch.py`; it reads `NbLittleKeys` as a byte. `work/tmp_secret_room_door_watch.py` is scratch evidence.
- `0013` key pickup is `FUN_00415e48` / `0x0041737c`, not proved `LM_GIVE_BONUS`; the older no-hit CDB artifact had a malformed command.
- Do not call the W path `search action`; in the classic source it is the default action key (`I_ACTION_ALWAYS` sets `ActionNormal`, read by `LF_ACTION`).
- Use `secret_room_key_counter_cdb_watch.py` only for deliberate CDB watches; one valid run captured evidence but crashed the app.
- Use `secret_room_key_frida_probe.py --poll-only` for repeated `0013` key-source proof; the life-interpreter hook crashed before `LM_FOUND_OBJECT`.
- On Sendell, use `CurrentDial` global `0x004CCF10`; old `0x00475630` / `513` is a trap.
- Room-36 page 2 is renderer pagination inside one decoded text record; do not reintroduce `514` without new classic proof.
- Do not collapse fresh room-entry seeding and loaded-state reconstruction on `36/36`.

## Canonical Entry Points

- `tools/life_trace/secret_room_door_watch.py`
- `tools/life_trace/secret_room_key_counter_cdb_watch.py`
- `tools/life_trace/secret_room_key_frida_probe.py`
- `tools/life_trace/waypoint_step_probe.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 -m unittest tools.test_secret_room_key_frida_probe`

## Open Unknowns

- Whether guarded `19/19` pickup requires same connected admitted surface/floor band.
- Whether the classic shadow-readjusted landing should be generalized beyond the currently guarded transition path.
- Hooked `LM_FOUND_OBJECT 0` remains unproved because the broad Frida interpreter hook is crash-prone; static source plus poll-only `SPRITE_CLE` proof covers the current port seam.
- The exact scene-2 life/object instructions that consume the key before reverse cube `0 -> 1` remain unproved; the port covers only the captured doorway band.
