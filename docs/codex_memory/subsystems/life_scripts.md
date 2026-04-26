# Life Scripts

## Purpose

Own life-program decoding and original-runtime evidence lanes.

## Invariants

- Treat raw `life_bytes` as the scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence.
- Keep harness/lane policy explicit.

## Current Parity Status

- `life_audit.zig` / `audit-life-programs` is canonical.
- Guarded `19/19` object `2` has live-backed `Divers=5` multi-bonus semantics.
- Guarded `19/19` reward pickups require same admitted landing cell plus existing proximity/cap checks.
- `0013` key source is W/default action: `LF_ACTION`, zone `0`, beta bounds, `gameVar(0)==0`, `KILL_OBJ 7`, `FOUND_OBJECT 0`, `SET_VAR_GAME 0 1`.
- `0013` key pickup is Frida poll-only proved: `SPRITE_CLE`, `Divers=1`, `NbLittleKeys 0 -> 1`; viewer covers W, pickup overlay, keyed cellar entry, and free return.
- `inspect-room-transitions` is runtime-aware for `0013`: `2/1` reports no-key/key paths; `2/0` includes synthetic free return.
- Named saves: direct globals + pose context + `SaveGame(TRUE)`: `PlayerName` `0x0049762c`, `GamePathname` `0x00497424`, `NumVersion=0xA4` at `0x00475620`, hero pose, `SceneStart` `0x0049a0a8..b0`, `StartCube` `0x0049a0e4..ec`.
- Named loads: `LBA2.EXE SAVE\<name>.LBA` with runtime `SAVE\` file and autosave hidden/restored so `PlayerGameList()` cannot clobber `GamePathname`.
- Room `36` keeps dialog id `3` across both visible Sendell pages and clears after the second ack.
- `waypoint_step_probe.py` owns debug-control outcomes; `collision_observer.py` is diagnostic-only.
- Guarded `3/3` zones `1`/`8` are Tralu handoffs: cube `19 -> 21/19`, cube `20 -> 22/20`.

## Known Traps

- Do not reuse old unsupported-life semantics for `2/2` or `11/10`.
- Tavern proves live behavior; Scene11 proves ownership snapshots.
- `waypoint_step_probe.py` owns debug-control outcomes.
- Do not generalize guarded `19/19` reward behavior or `LM_GIVE_BONUS`.
- Scene11 is a mismatch, not a startup failure.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- Do not revive staged `Load Game`; direct save launch is canonical and must reject the EA logo.
- `CurrentSaveGame()` is only `current.lba` and forces `0x24`/`SaveGame(FALSE)`.
- Frida must not select canonical save loads; it may only MCI-shim, observe, validate, and screenshot.
- Named-save helpers require explicit overwrite, `SaveGame(TRUE)`, then CLI-argv reload with autosave guard and memory proof.
- `0013-weapon.LBA` is the right cellar start; `3/3` zones `1` and `8` are Tralu handoffs, not cellar paths.
- `0013` door source is scene-2 zone `0`; keyed `2/1 -> 2/0`, free return `2/0 -> 2/1`.
- In `inspect-room-transitions`, use runtime fields for `0013`; decoded rows alone are insufficient.
- Use `secret_room_door_watch.py`; it reads `NbLittleKeys` as a byte.
- `0013` pickup is `FUN_00415e48` / `0x0041737c`, not `LM_GIVE_BONUS`.
- W path is default action, not search action.
- Use `secret_room_key_counter_cdb_watch.py` only for deliberate CDB watches.
- Internal `DoLifeLoop` hooks use function/probe form; callbacks-object form is only for real function entries.
- On Sendell, use `CurrentDial` global `0x004CCF10`; old `0x00475630` / `513` is a trap.
- Room-36 page 2 is renderer pagination; do not reintroduce `514` without new classic proof.

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

- Whether the classic shadow-readjusted landing should be generalized beyond the currently guarded transition path.
- Hooked `LM_FOUND_OBJECT 0` remains unproved; static source plus live `SPRITE_CLE` proof covers the current seam.
- Exact scene-2 key-consume instructions before cube `1 -> 0` remain unproved; port covers the captured doorway band.
