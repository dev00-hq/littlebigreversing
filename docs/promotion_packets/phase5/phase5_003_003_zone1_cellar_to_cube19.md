# Phase 5 3/3 Zone 1 Cellar To Cube 19

## Packet Identity

- `id`: `phase5_003_003_zone1_cellar_to_cube19`
- `status`: `live_negative`
- `evidence_class`: `zone_transition`
- `canonical_runtime`: `false`

## Exact Seam Identity

- room/load: scene `3`, background `3`
- source: corrected cellar-side source save `0013-weapon.LBA`, active cube `21`, decoded zone `1`
- destination: decoded destination cube `19`
- trigger: candidate zone crossing from the cellar-side source toward decoded zone `1`

## Decode Evidence

`inspect-room-transitions 3 3 --json` exposes guarded `3/3` decoded destination candidates. Zone `1` decodes to destination cube `19`; this is a candidate, not a promoted runtime transition.

## Original Runtime Live Evidence

`tools/fixtures/promotion_packets/phase5_003_003_zone1_cellar_to_cube19_live_negative.json` records the durable live-negative summary. The corrected `phase5_33_cellar_probe.py` run loaded `0013-weapon.LBA` and tested the zone `1` candidate. Direct-center hero-object injection briefly observed zone membership, but neither direct-center nor outside-to-inside injected edge crossing produced `NewCube=19` or `active_cube=19`. Twinsen fell to `y=1024`.

## Runtime Invariant

The promoted invariant is negative: `3/3` zone `1` is not canonical gameplay transition behavior. It remains a decoded cellar-source destination candidate until original-runtime evidence observes a runtime-owned transition signal.

## Positive Test

No positive gameplay test is admitted. A future positive test must cite a packet revision with `live_positive` or `approved_exception`.

## Negative Test

- `port/src/tools/cli.zig`: `inspect-room-transitions payload keeps guarded 3/3 decoded candidates non-canonical` asserts zone `1` has no `canonical_runtime_contract`.
- `tools/test_validate_promotion_packets.py`: `test_checked_in_manifest_is_valid` asserts the live-negative fixture is present through the manifest.
- `tools/test_validate_promotion_packets.py`: `test_three_three_live_negative_fixture_pins_non_promotion_facts` asserts the checked-in fixture keeps `status=live_negative`, `destination_cube=19`, and no runtime transition signal.

## Reproduction Command

```powershell
py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room-transitions 3 3 --json
```

This reproduces the decoded candidate. Before changing this packet status, run a checked-in original-runtime proof lane for the exact cellar-source transition and preserve the resulting proof bundle.

## Failure Mode

If code attempts to promote this seam without runtime-owned `NewCube`/`NewPos`, active cube change, target-zone membership through a valid movement path, or an explicitly approved exception, fail fast and keep `canonical_runtime: false`.

## Docs And Memory

- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `ISSUES.md`

## Old Hypothesis Handling

The old Tralu framing is downgraded. This seam is a cellar-source decoded candidate and live-negative gameplay transition.

## Revision History

- 2026-04-29: Recorded current `3/3` zone `1` status as live-negative and non-canonical for runtime gameplay.
