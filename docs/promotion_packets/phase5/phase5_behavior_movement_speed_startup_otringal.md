# Phase 5 Behavior Movement Speed Startup Otringal

## Packet Identity

- `id`: `phase5_behavior_movement_speed_startup_otringal`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: operator-prepared `otringal-open.LBA`
- source: Twinsen's existing save pose in an open outdoor Otringal gameplay area
- trigger: select one behavior mode with direct `F5`-`F8`, then hold Up for `2.00s`
- destination: runtime-owned `hero_x/hero_z/beta` time series after a live-window visual gate

## Decode Evidence

Classic behavior modes are selected by direct function keys in the original
runtime profile: `F5` Normal, `F6` Sporty, `F7` Aggressive, and `F8` Discreet.
The current packet does not depend on decoded scene geometry or object scripts;
it promotes an original-runtime movement timing observation from a prepared
open-area save.

Supplemental animation-root-motion comparison now supports, but does not yet
prove, an animation-derived implementation path. `tools/behavior_animation_root_motion_compare.py`
uses the adjacent LM2 viewer decoder to compare the promoted live Otringal
`2.00s` movement distances with decoded Twinsen walk-family ANIM root motion:

- Normal: `ANIM.HQR:1`, File3D object `0`, decoded `+2040` vs live `+2008`
- Sporty: `ANIM.HQR:67`, File3D object `1`, decoded `+5149` vs live `+5066`
- Aggressive: `ANIM.HQR:83`, File3D object `2`, decoded `+3018` vs live `+2974`
- Discreet: `ANIM.HQR:94`, File3D object `3`, decoded `+782` vs live `+772`

The maximum final-distance error is about `1.64%`. Treat this as strong
correlation evidence for behavior walk animations carrying the movement
profile, not as proof that the original runtime commits ANIM root deltas
directly to `hero_x/hero_z`.

## Original Runtime Live Evidence

`tools/game_drive_capability_ladder.py` hid active autosave state, launched
`otringal-open.LBA`, captured a live-window screenshot, passed the Codex visual
gate for an open outdoor Otringal gameplay area, selected the requested behavior
mode, held Up for `2.00s`, and recorded roughly `50ms` runtime memory samples.

Observed mostly z-axis movement from the same prepared pose:

- Normal: first movement around `371ms`, final `hero_z +2008`
- Sporty: first movement around `211ms`, final `hero_z +5066`
- Aggressive: first movement around `105ms`, final `hero_z +2974`
- Discreet: first movement around `478ms`, final `hero_z +772`

All four visual gates reported `matches=true`, `confidence=high`, with Twinsen
visible in gameplay and open walking space ahead.

## Runtime Invariant

Behavior mode changes both forward-movement startup latency and forward distance
over a fixed `2.00s` hold. The promoted contract is intentionally narrow: it
pins the Otringal `2.00s` forward-hold profile and exposes it as a time-based
movement profile. It does not promote analog turning, collision sliding,
animation selection, stamina, camera-dependent motion, or Aggressive/Discreet
action behavior outside movement.

The port also exposes a query-only decoded walk-root-motion layer for the same
four behavior families. That layer answers distance at elapsed held-Up time
from declared ANIM root-motion keyframes and classic-style interpolation, but it
is not wired into collision or viewer gameplay yet. A narrow held-forward
gameplay delta seam now computes per-frame root-motion deltas from held elapsed
time. The existing grid-step movement is explicitly diagnostic and remains
separate for viewer/debug topology probes.

## Positive Test

- `port/src/runtime/locomotion_test.zig` pins the promoted Otringal startup
  delays and `2.00s` forward distances for Normal, Sporty, Aggressive, and
  Discreet.
- `port/src/runtime/locomotion_test.zig` also pins the decoded walk-root-motion
  query at `500ms`, `1000ms`, `1500ms`, and `2000ms`, then checks the `2000ms`
  decoded distance against the live Otringal profile within a bounded tolerance.
- `port/src/runtime/locomotion_test.zig` verifies that held-forward gameplay
  deltas sum to the root-motion query while diagnostic grid stepping remains a
  separate viewer/debug path.
- `tools/test_game_drive_capability_ladder.py` covers the live proof harness
  cases and movement time-series reporting.
- `tools/test_behavior_animation_root_motion_compare.py` covers the looped
  root-motion accumulation used by the supplemental animation comparison.

## Negative Test

The port keeps the legacy grid-step `applyStep` path separate from the promoted
timed-hold profile. Tests assert the profile reports zero distance before each
mode's live-observed startup threshold, preventing a hidden immediate-speed
regression.

## Reproduction Command

```powershell
py -3 tools\game_drive_capability_ladder.py --case behavior_accel_otringal_normal --case behavior_accel_otringal_sporty --case behavior_accel_otringal_aggressive --case behavior_accel_otringal_discreet --save-root work\saves --archive --archive-event-id behavior-mode-accel-otringal-20260503 --json

py -3 tools\behavior_animation_root_motion_compare.py --out docs\evidence_archive\animation_root_motion\behavior_movement_root_motion_compare_20260503.json
```

## Failure Mode

If the visual gate does not confirm live gameplay in an open Otringal area, or
if `Comportement` does not match the selected direct key, reject the run. Do not
fall back to save previews, autosave state, Emerald Moon movement data, or
decoded-only movement assumptions.

## Docs And Memory

- `docs/codex_memory/lessons.md`
- `ISSUES.md`
- `SAVES.md`
- `docs/evidence_archive/animation_root_motion/behavior_movement_root_motion_compare_20260503.json`
- `tools/fixtures/game_drive_checkpoints/pose_ready_otringal_open.json`
- `tools/fixtures/promotion_packets/phase5_behavior_movement_speed_startup_otringal_live_positive.json`

## Old Hypothesis Handling

This packet replaces the earlier weaker "movement probably differs by behavior"
hypothesis with a live-positive Otringal proof. It also downgrades any plan to
scale the existing grid-cell step as insufficient: the promoted behavior has a
startup threshold and a time-based distance profile.

## Revision History

- 2026-05-03: Initial live-positive packet from `otringal-open.LBA` behavior
  movement probes.
- 2026-05-03: Added supplemental LM2 decoded ANIM root-motion comparison for
  the four behavior walk-family candidates.
- 2026-05-03: Added query-only port representation of the four decoded behavior
  walk root-motion curves without wiring them into continuous locomotion.
- 2026-05-03: Added a narrow held-forward gameplay delta seam and explicitly
  kept grid-cell stepping as diagnostic locomotion.
