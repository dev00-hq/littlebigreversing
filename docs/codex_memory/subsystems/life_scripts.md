# Life Scripts

## Purpose

Own the offline life-program decoder boundary and original-runtime evidence lanes.

## Invariants

- Keep life decoding offline until real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the scene-model surface.
- Prefer `life-program`, `track-program`, or `object behavior` over generic `script`.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone.
- Keep the outer harness shared and lane policy explicit.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is the canonical structural inventory.
- `LM_DEFAULT` and `LM_END_SWITCH` are currently supported in the offline decoder as one-byte structural markers.
- `zig build tool -- inspect-life-catalog --json` is the machine-readable structural catalog for `LM_*`, `LF_*`, and `LT_*`.
- Guarded `19/19` object `2` still has a stateful reward loop and diagnostics, and the sewer chest seam is now settled as seam-local multi-bonus emission: `10` magic extras, per-extra `Divers=5`, internal gain `Divers * 2`, and denied full-magic pickups rebound.
- `tools/life_trace/trace_life.py` is the shared original-runtime entrypoint, and `capture_sendell_ball.py` owns staged room-`36` runs.
- `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py` are debug-control helpers.
- `collision_observer.py` is diagnostic-only: it distinguishes persistent from transient pins and does not replace step outcome.

## Known Traps

- Do not reuse the old guarded-unsupported-life mental model for `2/2` or `11/10`; those pairs now decode and load through the guarded seam.
- Keep the Tavern hot path slim. Rich loop-time reads can bring back intermittent `Application Error` crashes.
- Tavern proves live behavior; Scene11 proves ownership through debugger snapshots.
- On the debug-control lane, do not promote collision evidence into controller truth. `waypoint_step_probe.py` outcome stays canonical.
- Do not treat the guarded `19/19` reward slice as generic pickup or save/load parity.
- Do not generalize `LM_GIVE_BONUS` from the sewer-chest evidence; only the guarded `19/19` seam is proved.
- Do not reuse raw scene-object coordinates as final spawn/landing truth on `19/19`; the chest bonuses scatter and bounce instead of sharing one spot.
- The remaining `19/19` pickup-surface question is narrower than the reward-model work. Current port gating still uses admitted footing plus same `top_y` and proximity.
- Scene11 is a mismatch, not a startup failure.
- Scene11 runtime-owner discovery is state-sensitive; the useful discriminator is non-null `global_ptr_prg`.
- Do not ask for arbitrary "Scene11" or "Sendell" saves; use `work/saves/save_profiles.json`.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- On Sendell's Ball, behavior and inventory menus are hold surfaces.
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
- Whether classic pickup on guarded `19/19` requires the same connected admitted surface/floor band, or whether the current gate is already sufficient.
