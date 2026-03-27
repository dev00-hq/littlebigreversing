# Backgrounds

## Purpose

Own the interior `LBA_BKG.HQR` metadata path exposed by `inspect-background`, including the header, `TabAllCube`, `GRI`, and `BLL` linkage.

## Invariants

- Keep background inspection separate from `inspect-scene`.
- Use classic zero-based HQR access where loader slot `0` matters.
- Keep this pack interior-only until evidence justifies broader convergence.

## Current Parity Status

- `inspect-background` is implemented.
- The canonical interior target `2` is asset-backed through the loader-faithful header and indirection path.
- `GRI` column payloads and `BLL` layout contents are decoded for the canonical interior background path.
- `GRM` fragment ownership and payload summaries are decoded for the interior background path, and `inspect-background` / `inspect-room` now report explicit fragment counts instead of only exposing the raw base GRM cursor.
- The viewer now uses a viewer-local composition snapshot to render a height-aware occupied-cell debug view with relief, contour, and shape cues behind the scene overlays for `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The canonical `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` pair currently resolves to zero scene `grm` zones and zero owned fragment entries, so the fragment-aware viewer path now surfaces an explicit zero-fragment state for that pair instead of guessed mutation overlays.
- Exterior `.ILE/.OBL`, full brick rasterization, and actor visual binding are still outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.
- `gri_header.my_grm` is a forward cursor, not proof that the current grid owns fragment entry `grm_start + my_grm`. In the checked-in assets, backgrounds `0..10` all report `my_grm = 0`, but only the last grid in that run owns fragment `149`; canonical background `2` owns none.

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
- `cd port && zig build tool -- inspect-room 2 2 --json`
- `cd port && zig build run -- --scene-entry 2 --background-entry 2`
- `cd port && zig build test`

## Open Unknowns

- Which fragment-bearing interior pair should become the next evidence target now that the canonical `2/2` pair is confirmed to be a zero-fragment case.
- When, if ever, interior and exterior background paths should share more runtime surface.
