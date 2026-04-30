# Phase 5 Magic Ball Enemy Damage Tralu Level 1

## Packet Identity

- `id`: `phase5_magic_ball_enemy_damage_tralu_level1`
- `status`: `live_positive`
- `evidence_class`: `collision_locomotion`
- `canonical_runtime`: `true`

## Exact Seam Identity

- room/load: direct-launched `tralu-attack.LBA`
- source state: magic level `1`, Magic Ball owned, Normal behavior mode
- trigger: select Magic Ball with `1`, hold weapon key `.` for `0.75s`, release
- target: Tralu dungeon enemy object `3`
- destination: object `3` life decreases by `9` per Magic Ball hit

This packet promotes only the observed level-1 Tralu enemy-damage seam. It does
not promote the full enemy vulnerability table, damage scaling by Magic Ball
level, level-0 damage, red/fire damage, switch activation, remote pickup,
destructible object hits, or general collision geometry.

## Decode Evidence

Classic source routes weapon input through the Magic Ball throw path only after
the held weapon input is released. `ThrowMagicBall()` derives projectile force
from current magic state, creates a `ListExtra` Magic Ball projectile, and
decrements magic points when magic is available. Enemy life changes are observed
through the live object table, not inferred from animation alone.

## Original Runtime Live Evidence

`tools/life_trace/phase5_magic_ball_tralu_sequence.py` was run twice from
`tralu-attack.LBA` with autosave guarded, a `1.0s` post-load readiness delay,
Normal mode selected with `F5`, Magic Ball selected with `1`, and `.` held for
`0.75s`.

- Run 1: Tralu object `3` life changed `72 -> 63` at `1.656s`, then `63 -> 54`
  at `3.655s`; Twinsen object `0` life changed later at `6.934s`.
- Run 2: Tralu object `3` life changed `72 -> 63` at `1.625s`, then `63 -> 54`
  at `3.654s`; Twinsen object `0` life changed later at `7.04s`.

The later Twinsen damage event distinguishes enemy damage from the player being
hit by Tralu.

## Runtime Invariant

For this proof seam only, a level-1 Magic Ball hit on Tralu object `3` applies
`9` life damage. Two repeated runs observed two Magic Ball hits before the later
Twinsen hit:

- first hit: `72 -> 63`
- second hit: `63 -> 54`

The canonical contract id is `magic_ball_enemy_damage_tralu_level1`.

## Positive Test

- `tools/test_validate_promotion_packets.py` pins the checked-in Tralu damage
  fixture.
- `tools/validate_promotion_packets.py` validates this packet identity,
  manifest entry, fixture presence, and runtime contract coverage.

## Negative Test

This packet intentionally does not assert any enemy other than Tralu object `3`,
any magic level other than `1`, or any damage value other than the observed `9`
life points per Magic Ball hit. A future implementation must not use this packet
as proof for general enemy vulnerability or damage scaling.

## Reproduction Command

Run twice from a clean named-save launch with no active `autosave.lba`:

```powershell
py -3 tools\life_trace\phase5_magic_ball_tralu_sequence.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\tralu-attack.LBA --out-dir work\live_proofs\phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run1_20260429 --hold-sec 0.75 --ready-delay-sec 1.0 --set-normal-mode --select-magic-ball --second-after-tralu-hit --second-after-tralu-hit-delay-sec 0.7 --observe-sec 8.0 --poll-sec 0.02 --splash-timeout-sec 15
py -3 tools\life_trace\phase5_magic_ball_tralu_sequence.py --save work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\tralu-attack.LBA --out-dir work\live_proofs\phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run2_20260429 --hold-sec 0.75 --ready-delay-sec 1.0 --set-normal-mode --select-magic-ball --second-after-tralu-hit --second-after-tralu-hit-delay-sec 0.7 --observe-sec 8.0 --poll-sec 0.02 --splash-timeout-sec 15
```

## Failure Mode

If Tralu object `3` does not lose `9` life per hit, if Twinsen damage occurs
before Tralu damage, or if autosave is active during launch, do not use the run
as canonical Tralu damage evidence. If startup does not reach the Adeline splash
stability gate, the run is a startup miss rather than a gameplay result.

## Docs And Memory

- `tools/fixtures/promotion_packets/phase5_magic_ball_enemy_damage_tralu_level1_live_positive.json`
- `work/live_proofs/phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run1_20260429/summary.json`
- `work/live_proofs/phase5_magic_ball_tralu_sequence_after_hit_ready1_delay07_run2_20260429/summary.json`
- `docs/codex_memory/lessons.md`
- `docs/codex_memory/task_events.jsonl`

## Old Hypothesis Handling

This packet replaces the unpromoted Tralu damage proof note with a scoped
live-positive contract. It does not complete the Magic Ball combat subsystem.

## Revision History

- 2026-04-29: Initial live-positive packet from two repeated Tralu level-1
  Magic Ball damage runs.
