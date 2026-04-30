# Phase 5 Magic Ball Switch Activation Emerald Moon

## Packet Identity

- `id`: `phase5_magic_ball_switch_activation_emerald_moon`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: direct-launched `moon-switches-room.LBA`
- source state: scene `31`, magic level `3`, Magic Ball owned, Normal behavior mode
- trigger: select Magic Ball with `1`, hold weapon key `.` for `0.75s`, release
- clean target: Emerald Moon switch object `3`, at `(2304, 1536, 8448)`, hit at save beta `2995`
- corrected target: Emerald Moon switch object `4`, at `(2304, 1536, 6912)`, hit after forcing beta `2760`
- destination: target switch script track advances by `label_track` transition and the Magic Ball returns instead of continuing a bounce path

This packet promotes only this Emerald Moon switch-room activation seam. It does
not promote generic switch or lever support, object `2`, Radar room levers, lever
families outside scene `31`, Magic Ball enemy damage, remote pickup,
destructible-object hits, or general collision geometry.

## Decode Evidence

The save loads scene `31` with three front switch objects in the live object
table:

- object `2`: `(2304, 1536, 9984)`
- object `3`: `(2304, 1536, 8448)`
- object `4`: `(2304, 1536, 6912)`

Object-field churn alone is not treated as hit proof. The promoted signal is a
target switch object's `label_track` transition during the Magic Ball throw,
combined with beta/trajectory setup and screenshots from the run.

## Original Runtime Live Evidence

`tools/life_trace/phase5_magic_ball_switch_probe.py` was run from
`moon-switches-room.LBA` with autosave guarded, Normal mode selected with `F5`,
Magic Ball selected with `1`, and `.` held for `0.75s`.

- Middle switch run:
  `work/live_proofs/phase5_magic_ball_switch_probe_middle_wide_20260429/timeline.jsonl`
  loaded Twinsen at beta `2995`; object `3` advanced `label_track 4 -> 1` at
  `2.762s` and `1 -> 2` at `2.961s`.
- Corrected lower/right switch run:
  `work/live_proofs/phase5_magic_ball_switch_probe_obj4_corrected_20260429/timeline.jsonl`
  forced beta `2760`; object `4` advanced `label_track 2 -> 3` at `2.807s` and
  `3 -> 4` at `3.012s`.

The earlier all-in-one beta `2542` attempt is excluded from promotion because
operator visual review showed it missed the third switch despite object-table
noise.

## Runtime Invariant

For this proof seam only, a Magic Ball hit on the promoted Emerald Moon switch
objects advances the target switch's script track and ends the ball interaction
as a switch hit rather than a wall/floor bounce.

The canonical contract id is `magic_ball_switch_activation_emerald_moon`.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in Emerald Moon
  switch fixture.
- `tools/validate_promotion_packets.py` validates this packet identity,
  manifest entry, fixture presence, and runtime contract coverage.

## Negative Test

This packet intentionally does not assert that every switch/lever uses
`label_track`, that all Magic Ball switch hits suppress bouncing in every scene,
or that object `2` in this room is promoted. A future implementation must not
use this packet as broad switch-family evidence.

## Reproduction Command

Run from a clean named-save launch with no active `autosave.lba`:

```powershell
py -3 tools\life_trace\phase5_magic_ball_switch_probe.py --out-dir work\live_proofs\phase5_magic_ball_switch_probe_middle_wide_20260429 --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\moon-switches-room.LBA --set-normal-mode --select-magic-ball --splash-timeout-sec 30 --poll-sec 0.005 --per-throw-observe-sec 2.2
py -3 tools\life_trace\phase5_magic_ball_switch_probe.py --out-dir work\live_proofs\phase5_magic_ball_switch_probe_obj4_corrected_20260429 --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\moon-switches-room.LBA --betas 2760 --set-normal-mode --select-magic-ball --splash-timeout-sec 30 --poll-sec 0.005 --per-throw-observe-sec 2.2
```

## Failure Mode

If an active `autosave.lba` changes the loaded state, if the target switch object
does not show the expected `label_track` transition, or if visual review shows
the aimed switch was not hit, do not use the run as canonical switch activation
evidence. Startup splash timeout failures are orchestration misses, not gameplay
negatives.

## Docs And Memory

- `tools/fixtures/promotion_packets/phase5_magic_ball_switch_activation_emerald_moon_live_positive.json`
- `work/live_proofs/phase5_magic_ball_switch_probe_middle_wide_20260429/summary.json`
- `work/live_proofs/phase5_magic_ball_switch_probe_middle_wide_20260429/timeline.jsonl`
- `work/live_proofs/phase5_magic_ball_switch_probe_obj4_corrected_20260429/summary.json`
- `work/live_proofs/phase5_magic_ball_switch_probe_obj4_corrected_20260429/timeline.jsonl`
- `docs/codex_memory/lessons.md`
- `docs/codex_memory/task_events.jsonl`

## Old Hypothesis Handling

This packet replaces the unpromoted Emerald Moon switch probe note with a scoped
live-positive contract. It does not complete the Magic Ball switch/lever
subsystem.

## Revision History

- 2026-04-29: Initial live-positive packet from object `3` middle-switch proof
  and object `4` corrected lower/right-switch evidence.
