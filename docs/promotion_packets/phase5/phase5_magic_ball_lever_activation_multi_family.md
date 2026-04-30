# Phase 5 Magic Ball Lever Activation Multi Family

## Packet Identity

- `id`: `phase5_magic_ball_lever_activation_multi_family`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: direct-launched named saves `lever-magic-ball.LBA` and
  `lever-wizard-tent.LBA`
- source state: Magic Ball owned, Normal behavior mode, named save loaded with
  active `autosave.lba` hidden before launch and restored afterward
- trigger: select Magic Ball with `1`, hold weapon key `.` for `0.75s`, release
- primary Radar target: scene `23` object `19`, a save-restored lever-like object
  at `(27617, 512, 12245, beta=2800)`
- primary Wizard target: object `2`, a lever/script owner with saved
  `label_track=6`, `gen_anim=155`, `index_file3d=67`, and `exe_switch_func=31`
- destination: target lever/script state changes and linked door/platform state
  changes after Magic Ball impact

This packet promotes only a narrow Magic Ball impact-to-lever/script activation
contract across two observed lever families. It does not promote generic support
for every switch or lever, does not specify a single object-field encoding for
all levers, and does not promote the warehouse blocked-lever case as activation.

## Decode Evidence

The live-slot to decoded-object mapping was resolved with
`tools/life_trace/save_object_context_dump.py` before promotion.

- `lever-magic-ball.LBA` serializes `NbObjets=22`; live slot `19` is the lever
  object with `gen_anim=242`, `next_gen_anim=242`, pose
  `(27617,512,12245,beta=2800)`, and `index_file3d=57`. Slot `21` starts with
  `label_track=3` and is a linked script/effect object.
- `lever-wizard-tent.LBA` identifies slot `2` as the lever/script owner:
  `gen_anim=155`, `next_gen_anim=155`, `index_file3d=67`, `label_track=6`, and
  `exe_switch_func=31`. Slot `3` is the linked moving door/platform object.
- `lever-magicball-2.LBA` is supporting evidence for a second Radar room lever
  that toggles linked door movement close/open.
- `tralu-lever-1.LBA` is supporting but noisy evidence because NPC/enemy motion
  shares the scene.
- `01-warehouse.LBA` is a negative control: the Magic Ball launches, hits, and
  returns, but the blocked/progression-gated lever does not activate.

## Original Runtime Live Evidence

`tools/life_trace/phase5_magic_ball_switch_probe.py` was used for the live
non-CDB runs, and `tools/life_trace/phase5_magic_ball_cdb_agent_watch_probe.py`
or the earlier one-shot CDB watcher was used to prove writer ownership.

- Radar primary positive:
  `work/live_proofs/phase5_magic_ball_radar_lever_run1_20260430/timeline.jsonl`
  and `work/live_proofs/phase5_magic_ball_radar_lever_run2_20260430/timeline.jsonl`
  repeat object `19` `gen_anim/next_gen_anim 242 -> 244`, slot `21`
  `label_track 3 -> 0`, and linked door/platform movement.
- Radar writer proof:
  `work/live_proofs/phase5_magic_ball_radar_lever_cdb_watch_20260430_r7/summary.json`
  watched `ListObjet[19].GenAnim` at `0x0049C9A1` and hit writer `0x004386ec`
  (`mov dword ptr [ebp+206h], ebx`) with `ebp` matching slot `19`.
- Wizard primary positive:
  `work/live_proofs/phase5_magic_ball_wizard_tent_lever_run1_20260430/timeline.jsonl`
  shows object `2` advancing through `label_track 6 -> 8 -> 9`, later
  `gen_anim/next_gen_anim 155 -> 0`, and linked object `3` movement to
  `z=5632`.
- Wizard writer proof:
  `work/live_proofs/phase5_magic_ball_wizard_tent_lever_cdb_label_run1_20260430/summary.json`
  watched `ListObjet[2].label_track` at `0x0049A7CE`, armed validly, observed one
  hit at writer `0x0042468c`, and captured memory `0049a7ce  0009`.
- Radar second-lever toggle:
  `work/live_proofs/phase5_magic_ball_radar_lever2_toggle_run1_20260430`,
  `run2`, and `run3` show close/open movement on linked object `7` with lever
  animation toggles.
- Tralu dungeon:
  `work/live_proofs/phase5_magic_ball_tralu_lever1_run1_20260430` and `run2`
  repeatedly show object `2` reaching `label_track=100` and object `7` playing
  `0 -> 123 -> 0`, but this remains supporting because scene actors add noise.
- Warehouse negative:
  `work/live_proofs/phase5_magic_ball_warehouse_blocked_lever_run1_20260430`
  shows projectile sprite `8` and return sprite `12`, but no lever-style
  activation; object `25` only flag-toggles and remains `label_track=-1`.

## Runtime Invariant

For these proof seams only, a Magic Ball impact can enter a lever/object-script
activation path that mutates the target lever state and triggers downstream
door/platform state.

The canonical contract id is `magic_ball_lever_activation_multi_family`.

## Source And Decompilation Cross-Check

The CDB writer paths are not Magic Ball-specific field setters. They are generic
object animation and track-script machinery reached after the impact path enters
the target object's normal script/track handling.

- Radar writer `0x004386ec` resolves inside `FUN_004385ec`, matching classic
  `InitAnim` in `reference/lba2-classic/SOURCES/OBJECT.CPP`. That function sets
  `GenAnim`, `NextGenAnim`, animation flags, and clears hit/animation work flags
  after `SearchAnim`/`ObjectInitAnim`.
- Wizard writer `0x0042468c` resolves inside `FUN_004237e0`, matching classic
  `DoTrack` in `reference/lba2-classic/SOURCES/GERETRAK.CPP`. The watched write
  is in `TM_LABEL`, which updates `LabelTrack`, increments `OffsetTrack`, and
  stores `OffsetLabelTrack`.
- The object struct fields line up with `DEFINES.H`: `GenAnim` is the early
  animation field, `OffsetLabelTrack`/`OffsetTrack`/`LabelTrack` are track state,
  and `ExeSwitch` is script-owned object behavior state.

Implementation consequence: broad support must route Magic Ball impact into the
normal object hit/script/track activation path and let existing animation/track
systems update object fields. Do not implement lever activation as direct writes
to `GenAnim`, `NextGenAnim`, or `LabelTrack` based on these observed deltas.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in multi-family
  lever fixture.
- `tools/validate_promotion_packets.py` validates this packet identity,
  manifest entry, fixture presence, and runtime contract coverage.

## Negative Test

Do not infer a single implementation rule from the observed object deltas.
Radar and Wizard use different watched write paths (`0x004386ec` and
`0x0042468c`), and the source/decompilation cross-check confirms those paths are
generic animation/track-script code, not projectile-specific setter functions.
The warehouse run proves that Magic Ball contact is not by itself sufficient to
activate a lever; script/progression eligibility still matters.

## Reproduction Command

Run from named-save launches with active `autosave.lba` hidden:

```powershell
py -3 tools\life_trace\phase5_magic_ball_switch_probe.py --out-dir work\live_proofs\phase5_magic_ball_radar_lever_run1_20260430 --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\lever-magic-ball.LBA --set-normal-mode --select-magic-ball --splash-timeout-sec 30 --poll-sec 0.005 --per-throw-observe-sec 3.0
py -3 tools\life_trace\phase5_magic_ball_switch_probe.py --out-dir work\live_proofs\phase5_magic_ball_wizard_tent_lever_run1_20260430 --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\lever-wizard-tent.LBA --set-normal-mode --select-magic-ball --splash-timeout-sec 30 --poll-sec 0.005 --per-throw-observe-sec 3.0
py -3 tools\life_trace\phase5_magic_ball_cdb_agent_watch_probe.py --out-dir work\live_proofs\phase5_magic_ball_wizard_tent_lever_cdb_label_run1_20260430 --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\lever-wizard-tent.LBA --watch-object-index 2 --watch-field label_track --set-normal-mode --select-magic-ball
```

## Failure Mode

If an active `autosave.lba` changes the loaded state, if no Magic Ball projectile
is observed, if the target object does not mutate through the expected
activation path, or if the linked door/platform does not move, do not use the
run as activation evidence. Treat warehouse-style blocked cases as negative
controls until progression/script state explains them.

## Docs And Memory

- `tools/fixtures/promotion_packets/phase5_magic_ball_lever_activation_multi_family_live_positive.json`
- `work/live_proofs/phase5_magic_ball_radar_lever_run1_20260430/summary.json`
- `work/live_proofs/phase5_magic_ball_radar_lever_run2_20260430/summary.json`
- `work/live_proofs/phase5_magic_ball_radar_lever_cdb_watch_20260430_r7/summary.json`
- `work/live_proofs/phase5_magic_ball_wizard_tent_lever_run1_20260430/summary.json`
- `work/live_proofs/phase5_magic_ball_wizard_tent_lever_cdb_label_run1_20260430/summary.json`
- `work/live_proofs/phase5_magic_ball_warehouse_blocked_lever_run1_20260430/summary.json`

## Old Hypothesis Handling

This packet replaces the unpromoted Radar/Wizard lever candidate notes with a
scoped live-positive contract. It deliberately leaves broad switch/lever support
as future work, but the immediate source/decompilation writer-mapping blocker is
closed: the watched writer addresses are generic object systems.

## Revision History

- 2026-04-30: Initial live-positive packet from Radar room and Wizard tent
  primary proofs, with Radar second-lever and Tralu supporting evidence plus the
  warehouse blocked-lever negative control.
- 2026-04-30: Cross-checked CDB writer addresses against decompilation and
  classic source; both writes are generic object animation/track-script paths,
  not Magic Ball-specific direct field setters.
