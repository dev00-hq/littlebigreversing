# Life Scripts

## Purpose

Own the offline life-program decoder boundary and original-runtime evidence lanes.

## Invariants

- Keep life decoding offline until real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the scene-model surface.
- Prefer `life-program`, `track-program`, or `object behavior` over generic `script` wording.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone.
- Keep the outer harness shared and lane policy explicit; do not force one inner proof seam across every scene.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is now the canonical zero-unsupported structural inventory, not a switch-family blocker report.
- `LM_DEFAULT` and `LM_END_SWITCH` are currently supported in the offline decoder as one-byte structural markers.
- `zig build tool -- inspect-life-catalog --json` is the machine-readable structural catalog for `LM_*`, `LF_*`, `LT_*`, and life return-type layout.
- Guarded `19/19` object `2` now has a stateful runtime-backed later reward loop with bounded magic bonus emission.
- `tools/life_trace/trace_life.py` is the shared original-runtime entrypoint, and `capture_sendell_ball.py` owns staged room-`36` runs.
- Run bundles live under `work/life_trace/runs/<run-id>/`; Scene11 and Sendell write `*_summary.json`.
- `tavern-trace` is the canonical Tavern proof lane.
- `scene11-pair` uses one-shot `cdb-agent --pid --wow64` reads.
- `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py` are the committed reusable debug-control helpers for original-runtime save-driven probing.
- `collision_observer.py` is diagnostic-only: it distinguishes persistent collision pins from transient pins but does not replace step outcome as the blocked/moved oracle.
- `work/saves/save_profiles.json` is the canonical save-generation manifest.

## Known Traps

- Do not reuse the old guarded-unsupported-life mental model for `2/2` or `11/10`; those pairs now decode and load through the guarded seam.
- Keep the Tavern hot path slim. Re-adding rich loop-time reads can bring back intermittent `Application Error` crashes.
- Tavern proves live behavior; Scene11 proves ownership through a debugger snapshot.
- On the debug-control lane, do not promote collision evidence into controller truth. `waypoint_step_probe.py` outcome stays canonical even when `collision_observer.py` reports a transient pin.
- The stable Scene11 result is a mismatch, not a startup failure.
- Scene11 runtime-owner discovery is state-sensitive; the useful discriminator is non-null `global_ptr_prg`.
- Do not ask for arbitrary "Scene11" or "Sendell" saves; use `work/saves/save_profiles.json`.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- On Sendell's Ball, behavior and inventory menus are hold surfaces; tap input can leave the screenshot in-room.
- On the current Sendell lane, `CurrentDial=513` is not a progression oracle.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/capture_sendell_ball.py`
- `tools/life_trace/debug_compass.py`
- `tools/life_trace/heading_inject.py`
- `tools/life_trace/waypoint_step_probe.py`
- `tools/life_trace/collision_observer.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`
- `py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120`
- `py -3 .\tools\life_trace\heading_inject.py --heading N`
- `py -3 .\tools\life_trace\waypoint_step_probe.py --launch-save .\work\tmp_probe_inputs\straight-line-walk-livecopy.LBA --heading W --move-key down`

## Open Unknowns

- Which classic pager state distinguishes visible room-36 page turns when `CurrentDial`, `TypeAnswer=4`, `Value=11`, and `PtrPrg` stay fixed.
- When guarded `19/19` object `2` should move beyond bounded bonus-event emission into live `cdb-agent` parity work for extra motion, pickup, UI, and save/load behavior.
