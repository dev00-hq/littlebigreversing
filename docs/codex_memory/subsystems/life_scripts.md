# Life Scripts

## Purpose

Own the offline life-program decoder boundary and original-runtime evidence lanes.

## Invariants

- Keep life decoding offline until real assets are supported or deliberately rejected.
- Treat raw `life_bytes` as the scene-model surface.
- Prefer `life-program`, `track-program`, or `object behavior` over generic `script`.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone.
- Keep the outer harness shared and lane policy explicit.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is canonical inventory.
- `LM_DEFAULT` and `LM_END_SWITCH` are supported one-byte markers.
- `inspect-life-catalog --json` is the structural catalog for `LM_*`, `LF_*`, and `LT_*`.
- Guarded `19/19` object `2` has live-backed `Divers=5` multi-bonus semantics.
- Room `36` keeps dialog id `3` across both visible Sendell pages and clears after the second ack.
- `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py` are debug-control helpers; `collision_observer.py` is diagnostic-only.

## Known Traps

- Do not reuse the old guarded-unsupported-life model for `2/2` or `11/10`; both now decode and load through the guarded seam.
- Tavern proves live behavior; Scene11 proves ownership through debugger snapshots.
- On debug-control, `waypoint_step_probe.py` outcome is canonical.
- Do not treat the guarded `19/19` reward slice as generic pickup or save/load parity.
- Do not generalize `LM_GIVE_BONUS`; only guarded `19/19` is proved.
- Do not reuse raw scene-object coordinates as final spawn/landing truth on `19/19`.
- Scene11 is a mismatch, not a startup failure.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- Do not revive the staged single-slot `Load Game` harness. Direct save launch is the canonical path.
- Direct-save startup must reject the black EA logo to avoid zero hero fields.
- `0013-weapon.LBA` is the right cellar start; forced `3/3` zone `1` lands in a Tralu-looking scene.
- Proved `0013` secret-room door source is scene-2 zone `0`; cube `1 -> 0` preserves source offset into `NewPos=(2562,2049,3322)` / `(2563,2049,3749)` before shadow readjustment.
- Reverse `0013` door proof is stateful: `NbLittleKeys` decrements `1 -> 0` around `t=11.916`; transition follows around `t=14.064` as cube `0 -> 1`, `NewPos=(9725,1278,1098)`, final hero `(9725,1024,1098)`.
- Use `tools/life_trace/secret_room_door_watch.py`; it reads `NbLittleKeys` as a byte. `work/tmp_secret_room_door_watch.py` is scratch evidence.
- On Sendell, use `CurrentDial` global `0x004CCF10`; old `0x00475630` / `CurrentDial=513` is a trap.
- Room-36 visible page 2 is renderer pagination inside one decoded text record.
- Do not reintroduce `514` as the visible second Sendell page without new classic proof.
- Do not collapse fresh room-entry seeding and loaded-state reconstruction on room `36/36`.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/capture_sendell_ball.py`
- `tools/life_trace/dialog_text_dump.py`
- `tools/life_trace/secret_room_door_watch.py`
- `tools/life_trace/debug_compass.py`
- `tools/life_trace/heading_inject.py`
- `tools/life_trace/waypoint_step_probe.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`
- `py -3 .\tools\life_trace\heading_inject.py --heading N`
- `py -3 .\tools\life_trace\secret_room_door_watch.py --attach-pid <pid> --out .\work\life_trace\secret-room-door-watch.jsonl --once`
- `py -3 .\tools\life_trace\waypoint_step_probe.py --launch-save .\work\saves\0013-weapon.LBA --keep-current-heading`

## Open Unknowns

- Whether guarded `19/19` pickup requires same connected admitted surface/floor band.
- Whether the classic shadow-readjusted landing should be generalized beyond the currently guarded transition path.
- Which scene-2 life/object path consumes the key before reverse cube `0 -> 1`.
