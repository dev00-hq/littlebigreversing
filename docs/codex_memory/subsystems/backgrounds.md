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
- `GRM` fragment ownership is decoded, and `inspect-background` / `inspect-room` now report explicit fragment counts instead of only exposing the raw base GRM cursor.
- The viewer now uses a viewer-local composition snapshot to render a height-aware debug view with relief, contour, and shape cues behind the scene overlays for `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The canonical `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` pair resolves to zero scene `grm` zones and zero owned fragment entries, so the viewer surfaces an explicit zero-fragment state there instead of guessed overlays.
- The fragment-bearing interior evidence pair is `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]`, and the viewer/runtime path accepts it with one projected fragment zone backed by background `10` fragment `149`.
- The background decoder now loads the main `RESS.HQR[0]` palette plus the selected top-surface `BRK` entries referenced by the current composition and fragment surfaces, and the probes report deterministic `BRK` preview summaries.
- The viewer now derives a fragment comparison panel, focused-cell highlight, and selected-cell detail strip so the `11/10` pair exposes swatch deltas plus per-cell brick / floor / shape / stack-depth differences without a shared room layer, and same-brick floor / shape / stack mismatches now rank ahead of exact matches.
- Exterior `.ILE/.OBL`, full brick rasterization, and actor visual binding stay outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.
- `gri_header.my_grm` is a forward cursor, not proof that the current grid owns fragment entry `grm_start + my_grm`. In the checked-in assets, backgrounds `0..10` all report `my_grm = 0`, but only the last grid owns fragment `149`; canonical background `2` owns none.
- Scene `grm` zone bounds are not expressed like the older zero-fragment overlays. The positive pair `11/10` only projects cleanly if fragment-zone maxima are treated as boundary-aligned endpoints, yielding `16x10x13` cells for the scene `11` `grm` zone instead of failing the room as out-of-bounds.
- `inspect-room --json` no longer mirrors the viewer-local fragment comparison state. It still reports `11/10` fragment counts and `BRK` preview summaries, but not the projected fragment cells behind the comparison panel, so use the CLI for probe-level cross-checks and the viewer/tests for per-cell delta behavior.
- `drawBrickProbe` is still synthetic after the `BRK` slice landed. Treat the palette-backed swatches as the current `BRK` evidence surface, not as proof that the repo now has a full room-art renderer.

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

- When, if ever, interior and exterior background paths should share more runtime surface.
