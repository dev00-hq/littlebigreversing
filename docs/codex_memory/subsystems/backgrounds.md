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
- The canonical `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` pair resolves to zero scene `grm` zones and zero owned fragment entries, so the viewer shows an explicit zero-fragment state there.
- The fragment-bearing interior evidence pair is `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]`, and the viewer/runtime path accepts it with one projected fragment zone backed by fragment `149`.
- The background decoder now loads `RESS.HQR[0]` plus the selected top-surface `BRK` entries referenced by the current composition and fragment surfaces, and probes report deterministic `BRK` preview summaries.
- The viewer now renders composition tops, fragment cells, and comparison cards from those decoded `BRK` previews on the existing path, failing fast if a referenced preview is unexpectedly missing.
- The viewer now derives a fragment comparison panel, focus highlight, selected-cell detail strip, deterministic ranked/cell navigation, and a pinned selected-cell row so the `11/10` pair exposes real `BRK`-backed top-surface deltas without adding a shared room layer.
- Exterior `.ILE/.OBL`, full brick rasterization, and actor visual binding stay outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.
- `gri_header.my_grm` is a forward cursor, not proof that the current grid owns fragment entry `grm_start + my_grm`. In the checked-in assets, backgrounds `0..10` all report `my_grm = 0`, but only the last grid owns fragment `149`; canonical background `2` owns none.
- Scene `grm` zone bounds are not expressed like the older zero-fragment overlays. The positive pair `11/10` only projects cleanly if fragment-zone maxima are treated as boundary-aligned endpoints, yielding `16x10x13` cells instead of failing the room as out-of-bounds.
- `inspect-room --json` no longer mirrors the viewer-local fragment comparison state. It still reports `11/10` fragment counts and `BRK` preview summaries, but not the projected fragment cells behind the comparison panel, so use the CLI for probe checks and viewer/tests for per-cell deltas.
- The landed `BRK` previews are evidence surfaces, not proof that the repo now has a full room-art renderer. Keep future work scoped to the current debug/comparison path unless checked-in evidence justifies more.

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
