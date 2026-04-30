# Phase 5 Magic Ball Bounce Return Wall Repeat

## Packet Identity

- `id`: `phase5_magic_ball_bounce_return_wall_repeat`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: direct-launched wall-proof saves
- source saves: `throw-ball-fire-1-wall.LBA` and `throw-ball-fire-wall.LBA`
- trigger: Normal behavior mode, Magic Ball selected, weapon key `.` held for `0.75s` then released
- destination: active Magic Ball `ListExtra` projectile emits repeated bounce signatures and eventually clears

`throw-ball-fire-1-wall.LBA` is the level-1 wall save observed on disk during the proof run. The requested `throw-ball-1-wall.LBA` name was not present in `SAVE\`; the observed save had `magic_level=1`.

## Decode Evidence

Classic `EXTRA.CPP` handles Magic Ball as a `ListExtra` projectile. `BounceExtra` flips `Vx`, `Vy`, or `Vz`, resets `U.Org` to the old collision position, and resets `TimerRefHR`. In `GereExtras`, `EXTRA_END_COL` calls `PtrWorldColBrickVisible`; when the type is `EXTRA_MAGIC_BALL` and `MagicBallType == 1`, the engine decrements the bounce count, calls `BounceExtra`, and records `NewMagicBallRebond = 3`. Non-bouncing or exhausted cases call `InitBackMagicBall`, which creates the return projectile.

## Original Runtime Live Evidence

`tools/life_trace/phase5_magic_ball_drive_probe.py` was extended to snapshot `ListExtra` timer/body/beta/poids/hit-force/owner fields and infer projectile events from the tracked Magic Ball row. A bounce is inferred only when the same row and sprite continue while velocity flips sign and origin/timer reset. Row or sprite changes are classified separately as return/retarget.

Each wall save was run twice to avoid repeating the earlier fire 10s outlier mistake.

- Level 1 run 1: `magic_point 18 -> 17`, four bounces with flips `vx, vy, vy, vx`, return sprite sampled at `1.775s`, clear at `1.906s`.
- Level 1 run 2: `magic_point 18 -> 17`, four bounces with flips `vx, vy, vy, vx`, return sprite sampled at `1.788s`, clear at `1.893s`.
- Fire run 1: `magic_point 76 -> 75`, four bounces with flips `vy, vy, vz, vx`, clear at `1.614s`.
- Fire run 2: `magic_point 76 -> 75`, four bounces with flips `vy, vy, vz, vx`, clear at `1.615s`.

## Runtime Invariant

For the proved wall-save seam only, a Magic Ball projectile may advance through a deterministic event sequence matching the observed `ListExtra` signatures:

- `level1_wall_normal`: four bounce events with axes `x, y, y, x`, then a return-start event using sprite `12`, then clear.
- `fire_wall_normal`: four bounce events with axes `y, y, z, x`, then clear.

The runtime event is a bounce only when the projectile remains the same row/sprite and a velocity component flips. This packet does not promote general collision geometry, damage, switch activation, remote key pickup, enemy vulnerability, fire-ball trail rendering, or all behavior-mode trajectories.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in wall-bounce fixture.
- `port/src/runtime/update_test.zig` asserts the level-1 and fire wall event sequences.
- `port/src/runtime/object_behavior_test.zig` asserts Magic Ball throw consumes one magic point when magic is available.

## Negative Test

The runtime event model does not classify row/sprite transitions as bounces; level-1 return is represented as `return_started` rather than an extra bounce. Fire-wall proof does not require a sampled return sprite because both repeated runs cleared after the fourth bounce without a return row sampled by the probe.

## Reproduction Command

Run sequentially; each probe owns `LBA2.EXE` and hides autosave during launch.

```powershell
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\throw-ball-fire-1-wall.LBA --out-dir work\live_proofs\phase5_magic_ball_wall_lvl1_run1_20260429 --mode normal --durations 0.75 --monitor-sec 5.0 --poll-sec 0.02
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\throw-ball-fire-1-wall.LBA --out-dir work\live_proofs\phase5_magic_ball_wall_lvl1_run2_20260429 --mode normal --durations 0.75 --monitor-sec 5.0 --poll-sec 0.02
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\throw-ball-fire-wall.LBA --out-dir work\live_proofs\phase5_magic_ball_wall_fire_run1_20260429 --mode normal --durations 0.75 --monitor-sec 5.0 --poll-sec 0.02
py -3 tools\life_trace\phase5_magic_ball_drive_probe.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\throw-ball-fire-wall.LBA --out-dir work\live_proofs\phase5_magic_ball_wall_fire_run2_20260429 --mode normal --durations 0.75 --monitor-sec 5.0 --poll-sec 0.02
```

## Failure Mode

If a run does not consume one magic point, does not emit four bounce signatures, or does not clear before monitor end, do not use it as canonical bounce evidence. If a row/sprite transition is counted as a bounce, the probe classifier is wrong for this seam and must be fixed before promotion.

## Docs And Memory

- `work/live_proofs/phase5_magic_ball_wall_bounce_repeat_20260429.json`
- `tools/life_trace/phase5_magic_ball_drive_probe.py`
- `tools/life_trace/phase5_magic_ball_throw_probe.py`
- `tools/fixtures/promotion_packets/phase5_magic_ball_bounce_return_wall_repeat_live_positive.json`
- `docs/codex_memory/task_events.jsonl`

## Old Hypothesis Handling

This packet replaces the earlier lifecycle-only bounce hypothesis with direct `ListExtra` state-change evidence. It does not prove the complete Magic Ball physics subsystem.

## Revision History

- 2026-04-29: Initial live-positive packet from repeated level-1 and fire wall-save bounce probes.
