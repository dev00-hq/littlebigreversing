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
- Guarded `19/19` object `2` still has a stateful reward loop, and the sewer chest seam is settled as seam-local multi-bonus emission with live-backed `Divers=5` semantics.
- The bounded room-`36` correction keeps dialog id `3` across both visible Sendell pages, uses the shared decoded-record next-page-cursor split instead of a fake `513 -> 514` step, and returns to room control after the second acknowledgment.
- `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py` are debug-control helpers.
- `collision_observer.py` is diagnostic-only: it distinguishes persistent from transient pins and does not replace step outcome.

## Known Traps

- Do not reuse the old guarded-unsupported-life model for `2/2` or `11/10`; both now decode and load through the guarded seam.
- Tavern proves live behavior; Scene11 proves ownership through debugger snapshots.
- On the debug-control lane, do not promote collision evidence into controller truth. `waypoint_step_probe.py` outcome is canonical.
- Do not treat the guarded `19/19` reward slice as generic pickup or save/load parity.
- Do not generalize `LM_GIVE_BONUS` from the sewer-chest evidence; only guarded `19/19` is proved.
- Do not reuse raw scene-object coordinates as final spawn/landing truth on `19/19`; the chest bonuses scatter and bounce instead of sharing one spot.
- Scene11 is a mismatch, not a startup failure.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe`.
- Do not revive the staged single-slot `Load Game` harness. Direct save launch is the canonical path.
- On the current Sendell lane, the old `0x00475630` / `CurrentDial=513` read is a trap. Use the pinned decoder `CurrentDial` global at `0x004CCF10`; live page-1/page-2 verification kept it at `3`.
- On the current room-36 Sendell lane, visible page 2 is renderer pagination inside one decoded text record, not a `513 -> 514` transition.
- Do not reintroduce `514` as the visible second Sendell page without new classic proof.
- Do not collapse fresh room-entry seeding and loaded-state reconstruction on room `36/36`.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/capture_sendell_ball.py`
- `tools/life_trace/dialog_text_dump.py`
- `tools/life_trace/debug_compass.py`
- `tools/life_trace/heading_inject.py`
- `tools/life_trace/waypoint_step_probe.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`
- `py -3 .\tools\life_trace\heading_inject.py --heading N`
- `py -3 .\tools\life_trace\waypoint_step_probe.py --launch-save .\work\tmp_probe_inputs\straight-line-walk-livecopy.LBA --heading W --move-key down`

## Open Unknowns

- Whether the proved next-page-cursor rule should be widened beyond the already-proved two-page seams before a full classic dialog renderer exists.
- Whether classic pickup on guarded `19/19` requires the same connected admitted surface/floor band, or whether the current gate is already sufficient.
