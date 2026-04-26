# Backgrounds

## Purpose

Own the interior `LBA_BKG.HQR` decode path and the bounded viewer evidence surfaces built directly on it.

## Invariants

- Keep background inspection separate from `inspect-scene`.
- Use classic zero-based HQR access where loader slot `0` matters.
- Keep this pack interior-only until evidence justifies broader convergence.
- Keep decoded scene zones, fragment-zone layout, and runtime containing-zone membership as separate surfaces.

## Current Parity Status

- `inspect-background` is implemented with the loader-faithful header, `TabAllCube`, `GRI`, and `BLL` path for canonical interior backgrounds.
- `19/19`, `2/2`, `11/10`, and `187/187` are guarded-positive viewer pairs. Seeding reaches `19/19` via explicit `39/6`; `2/2`, `11/10`, and `187/187` use runtime-owned nearest-standable seeding, with `187/187` as the first fragment-bearing same-index compatible pair.
- `SCENE.HQR[44]` with `LBA_BKG.HQR[2]` now fails at the guarded seam for the right reason: `ViewerSceneMustBeInterior`, not unsupported life.
- The old `219/219` blocker remains, but it is no longer the top offline decoded interior candidate; `inspect-room 219 219 --json` still emits `reason=invalid_fragment_zone_bounds` plus six per-zone issue lines before rethrowing `InvalidFragmentZoneBounds`.
- `triage-same-index-decoded-interior-candidates` is now the canonical offline report for ranked same-index fragment-zone compatibility: `86/86` is the highest-ranked compatible pair overall, and `187/187` is the first compatible pair with both fragments and GRM zones present.
- Exterior `.ILE/.OBL`, full brick rasterization, and actor visual binding stay outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.
- `gri_header.my_grm` is a forward cursor, not ownership proof. In the checked-in assets, backgrounds `0..10` all report `my_grm = 0`, but only the last grid owns fragment `149`; canonical background `2` owns none.
- The positive pair `11/10` only projects cleanly if fragment-zone maxima are treated as boundary-aligned endpoints.
- Winning the offline decoded-candidate ranking does not prove fragment-zone compatibility. `SCENE.HQR[101]` is now the top decoded interior candidate overall, but `inspect-room 219 219` still dies on `InvalidFragmentZoneBounds`.
- A same-index compatibility win can still be trivial. `86/86` currently outranks `19/19` and clears the checked-in fragment-zone rules, but only because it has `fragment_count=0` and `grm_zone_count=0`; `187/187` is the first compatible same-index pair that actually has fragment-zone data (`fragment_count=2`, `grm_zone_count=2`, `compatible_zone_count=2`).
- `inspect-room --json` reports probe counts and `BRK` summaries, not the projected fragment cells behind the comparison panel; even though `11/10` and `187/187` are now guarded-positive, use viewer/tests for per-cell deltas instead of expecting the CLI to surface fragment-cell projection details.

## Canonical Entry Points

- `port/src/game_data/background.zig`
- `port/src/game_data/background/parser.zig`
- `port/src/game_data/background/model.zig`

## Important Files

- `port/src/game_data/background/tests/`
- `port/src/assets/hqr.zig`
- `port/src/tools/cli.zig`

## Test / Probe Commands

- `cd port && zig build tool -- inspect-background 2 --json`
- `cd port && zig build tool -- inspect-room 19 19 --json`
- `cd port && zig build tool -- inspect-room 2 2 --json`
- `cd port && zig build tool -- inspect-room 11 10 --json`
- `cd port && zig build tool -- inspect-room 187 187 --json`
- `cd port && zig build tool -- inspect-room 44 2 --json`
- `cd port && zig build tool -- inspect-room-fragment-zones 219 219 --json`
- `cd port && zig build tool -- triage-same-index-decoded-interior-candidates --json`

## Open Unknowns

- Whether interior and exterior background paths should ever share more runtime surface than they do today.

