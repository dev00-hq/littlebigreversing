# Life Scripts

## Purpose

Own life-program decoding and original-runtime evidence lanes.

## Invariants

- Treat raw `life_bytes` as the scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence.
- Keep harness/lane policy explicit.

## Current Parity Status

- `life_audit.zig` / `audit-life-programs` is canonical.
- Guarded `19/19` object `2` has live-backed `Divers=5` multi-bonus semantics; do not generalize this to all `LM_GIVE_BONUS`.
- `0013` key source is W/default action: `LF_ACTION`, zone `0`, beta bounds, `gameVar(0)==0`, `KILL_OBJ 7`, `FOUND_OBJECT 0`, `SET_VAR_GAME 0 1`.
- `0013` is closed: `tools/fixtures/phase5_0013_runtime_proof.json` and `docs/PHASE5_0013_RUNTIME_PROOF.md` prove generated-save load, W key spawn, pickup, key-consume door, cellar transition, and Down-return.
- `inspect-room-transitions` is runtime-aware for `0013`: `2/1` reports no-key/key paths; `2/0` includes synthetic free return.
- Named saves set `PlayerName`, `GamePathname`, `NumVersion=0xA4`, hero pose, `SceneStart`, `StartCube`, then call `SaveGame(TRUE)`.
- Named loads use `LBA2.EXE SAVE\<name>.LBA` with autosave hidden/restored.
- Room `36` keeps dialog id `3` across both visible Sendell pages and clears after the second ack.
- Guarded `3/3` zones `1`/`8` are Tralu handoffs: cube `19 -> 21/19`, cube `20 -> 22/20`.

## Known Traps

- Do not reuse old unsupported-life semantics for `2/2` or `11/10`.
- Tavern proves live behavior; Scene11 proves ownership snapshots.
- Do not revive staged `Load Game`; direct save launch is canonical and must reject the EA logo.
- Normal original-runtime CD startup uses the mixed-mode CUE mounted on Alcohol `E:`; Frida must not select canonical save loads.
- The WinMM proxy is an opt-in instrumentation path, not the default launch path. With `LBA2_RUNTIME_WATCH=1`, it writes `life_loss_detected` rows when `ListVarGame[FLAG_CLOVER]` at `0x0049A08E` decreases.
- Use `life_loss_cdb_watch.py` only when the exact write stack matters; it watches the same counter and captures the CDB stack.
- `CurrentSaveGame()` is only `current.lba` and forces `0x24`/`SaveGame(FALSE)`.
- `0013-weapon.LBA` is the right cellar start; `3/3` zones `1` and `8` are Tralu handoffs, not cellar paths.
- `0013` door source is scene-2 zone `0`; keyed `2/1 -> 2/0`, free return `2/0 -> 2/1`.
- In `inspect-room-transitions`, use runtime fields for `0013`; decoded rows alone are insufficient.
- Use `secret_room_door_watch.py`; it reads `NbLittleKeys` as a byte.
- Use `runtime_watch_run.py --scenario phase5-0013-door` for the guarded no-CDB 0013 cellar-door proof lane.
- `0013` pickup is `FUN_00415e48` / `0x0041737c`, not `LM_GIVE_BONUS`.
- W path is default action, not search action.
- For LBA2 screenshots, preserve RGB for game captures; alpha may be bogus.
- Room-36 page 2 is renderer pagination; do not reintroduce `514` without new classic proof.

## Canonical Entry Points

- `tools/life_trace/secret_room_door_watch.py`
- `tools/life_trace/runtime_watch_run.py`
- `tools/runtime_shims/lba2_winmm_proxy`
- `tools/life_trace/life_loss_cdb_watch.py`
- `tools/life_trace/secret_room_key_frida_probe.py`
- `tools/life_trace/waypoint_step_probe.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 -m unittest tools.test_secret_room_key_frida_probe`
- `py -3 -m unittest tools.test_runtime_shim_life_watch`

## Open Unknowns

- Whether the classic shadow-readjusted landing should generalize beyond the guarded transition path.
- Hooked `LM_FOUND_OBJECT 0` remains unproved; static source plus live `SPRITE_CLE` proof covers the current seam.
- Exact scene-2 key-consume instructions before cube `1 -> 0` remain unproved; port covers the captured doorway band.
