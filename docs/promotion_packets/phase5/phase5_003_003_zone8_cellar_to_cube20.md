# Phase 5 3/3 Zone 8 Cellar To Cube 20

## Packet Identity

- `id`: `phase5_003_003_zone8_cellar_to_cube20`
- `status`: `live_negative`
- `evidence_class`: `zone_transition`
- `canonical_runtime`: `false`

## Exact Seam Identity

- room/load: scene `3`, background `3`
- source: corrected cellar-side source save `0013-weapon.LBA`, save cube `1`, decoded zone `8`
- destination: decoded destination cube `20`
- trigger: direct-center source-zone membership probe for decoded zone `8`

## Decode Evidence

`inspect-room-transitions 3 3 --json` exposes zone `8` as a decoded committed candidate to destination cube `20`, scene/background `22/20`, with decoded destination `(28672,1536,31744)`.

## Original Runtime Live Evidence

`tools/fixtures/promotion_packets/phase5_003_003_zone8_cellar_to_cube20_live_negative.json` records the live-negative summary from `work/live_proofs/phase5_33_cellar_zone8_20260429/summary.json`. The run loaded `0013-weapon.LBA`, observed direct-center zone `8` membership, but did not observe `NewCube=20`, active cube `20`, or nonzero `NewPos`. Twinsen then lost a clover and reset to the source save pose.

## Runtime Invariant

The promoted invariant is negative: `3/3` zone `8` is not canonical gameplay transition behavior. It remains a decoded cellar-source destination candidate until original-runtime evidence observes a runtime-owned transition signal.

## Positive Test

No positive gameplay test is admitted. A future positive test must cite a packet revision with `live_positive` or `approved_exception`.

## Negative Test

- `tools/test_validate_promotion_packets.py`: asserts the checked-in fixture keeps `status=live_negative`, `destination_cube=20`, zone membership observed, life loss observed, and no runtime transition signal.
- `tools/test_phase5_33_cellar_probe.py`: asserts the probe can target zone `8` without accepting zone `1` destination signals.

## Reproduction Command

```powershell
py -3 tools\life_trace\phase5_33_cellar_probe.py --zone 8 --out-dir work\live_proofs\phase5_33_cellar_zone8_20260429 --duration-sec 3 --source-sustain-sec 1 --load-timeout-sec 25
```

This command is expected to return nonzero for the checked-in live-negative result.

## Failure Mode

If code attempts to promote this seam without runtime-owned `NewCube`/`NewPos`, active cube change, target-zone membership through a valid movement path that does not immediately collapse into life loss, or an explicitly approved exception, fail fast and keep `canonical_runtime: false`.

## Docs And Memory

- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `ISSUES.md`

## Old Hypothesis Handling

The old Tralu framing is downgraded. This seam is a cellar-source decoded candidate and live-negative gameplay transition.

## Revision History

- 2026-04-29: Recorded current `3/3` zone `8` status as live-negative and non-canonical for runtime gameplay.
