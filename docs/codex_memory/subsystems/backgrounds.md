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
- The viewer now uses a viewer-local composition snapshot to render a height-aware occupied-cell debug view with relief, contour, and shape cues behind the scene overlays for `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- Exterior `.ILE/.OBL`, fragment application, full brick rasterization, and actor visual binding are still outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.

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

- Which next interior-only slice should come after the height-aware composition debug rendering.
- When, if ever, interior and exterior background paths should share more runtime surface.
