# Life Scripts

## Purpose

Own life-program decoding and original-runtime evidence lanes.

## Invariants

- Treat raw `life_bytes` as the scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence.
- Keep harness/lane policy explicit.

## Current Parity Status

- `life_audit.zig` / `audit-life-programs` is canonical.
- Guarded `19/19` object `2` has live-backed `Divers=5` multi-bonus semantics; do not generalize `LM_GIVE_BONUS`.
- `0013` key source is W/default action: zone `0`, beta bounds, `gameVar(0)==0`, `KILL_OBJ 7`, `FOUND_OBJECT 0`, `SET_VAR_GAME 0 1`.
- `0013` is closed: save load, key pickup, key door, cellar entry, and return.
- `inspect-room-transitions` is runtime-aware for `0013`: `2/1` no-key/key paths; `2/0` synthetic free return.
- Named saves set name/path/version, hero pose, `SceneStart`, `StartCube`, then `SaveGame(TRUE)`.
- Named loads use `LBA2.EXE SAVE\<name>.LBA` with autosave hidden.
- Room `36` keeps dialog id `3` across both visible Sendell pages and clears after the second ack.
- Guarded `3/3` zones `1`/`8`: cube `19 -> 21/19`, cube `20 -> 22/20`.

## Known Traps

- Do not reuse old unsupported-life semantics for `2/2` or `11/10`; Tavern proves live behavior, Scene11 proves ownership snapshots.
- Do not revive staged `Load Game`; direct save launch is canonical and must reject the EA logo.
- Mixed-mode CD startup uses Alcohol `E:`; Frida must not select canonical save loads.
- WinMM proxy is opt-in; `LBA2_RUNTIME_WATCH=1` records `life_loss_detected` from `FLAG_CLOVER`.
- Use `life_loss_cdb_watch.py` only when the exact clover write stack matters.
- `CurrentSaveGame()` is only `current.lba` and forces `0x24`/`SaveGame(FALSE)`.
- `0013-weapon.LBA` is the cellar-side source save, not Tralu.
- `3/3` zones `1`/`8` are live-negative: zone membership appeared, but no destination cube or nonzero `NewPos`; zone `8` ended in clover loss/reset.
- The `3/3` zone `1`/`8` packets are `live_negative`; do not widen gameplay from decoded candidates.
- Magic Ball canonical runtime: pickup, initial throw launch, narrow wall bounce/return repeat (`level1: x,y,y,x + sprite-12 return + clear`; `fire: y,y,z,x + clear`), and narrow Tralu level-1 enemy damage (`object 3: 72->63->54`).
- `0013` door source is scene-2 zone `0`; keyed `2/1 -> 2/0`, free return `2/0 -> 2/1`.
- In `inspect-room-transitions`, use runtime fields for `0013`; decoded rows alone are insufficient.
- Use `secret_room_door_watch.py`; it reads `NbLittleKeys` as a byte.
- `0013` pickup is `FUN_00415e48` / `0x0041737c`, not `LM_GIVE_BONUS`.
- W path is default action, not search action.
- For LBA2 screenshots, preserve RGB for game captures; alpha may be bogus.
- Room-36 page 2 is renderer pagination; do not reintroduce `514` without new classic proof.

## Canonical Entry Points

- `tools/life_trace/secret_room_door_watch.py`
- `tools/life_trace/runtime_watch_run.py`
- `tools/life_trace/phase5_magic_ball_drive_probe.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 tools/validate_promotion_packets.py`
- `py -3 tools/life_trace/phase5_magic_ball_probe.py --attach-pid <pid> --duration-sec 45`
- `py -3 tools/life_trace/phase5_magic_ball_drive_probe.py --mode normal --key period --durations 0.61,0.62,0.63,0.64,0.65`

## Open Unknowns

- Whether the classic shadow-readjusted landing should generalize beyond the guarded transition path.
- Hooked `LM_FOUND_OBJECT 0` remains unproved; static source plus live `SPRITE_CLE` proof covers the current seam.
- Exact scene-2 key-consume instructions before cube `1 -> 0` remain unproved; port covers the captured doorway band.
- Broader Magic Ball damage, switch activation, remote pickup, enemy vulnerability, fire trail rendering, and general collision geometry remain separate unproved seams.
