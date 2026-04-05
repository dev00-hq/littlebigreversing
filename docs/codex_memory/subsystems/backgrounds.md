# Backgrounds

## Purpose

Own the interior `LBA_BKG.HQR` decode path and the bounded viewer evidence surfaces built directly on it.

## Invariants

- Keep background inspection separate from `inspect-scene`.
- Use classic zero-based HQR access where loader slot `0` matters.
- Keep this pack interior-only until evidence justifies broader convergence.

## Current Parity Status

- `inspect-background` is implemented with the loader-faithful header, `TabAllCube`, `GRI`, and `BLL` path for canonical interior backgrounds.
- `inspect-background` and `inspect-room` report explicit fragment ownership/counts instead of only the base `GRM` cursor.
- The viewer-local background evidence path renders composition tops, fragment cells, comparison cards, decoded `BRK` previews, and concise provenance cues on top of those decoded interior structures.
- `SCENE.HQR[19]` with `LBA_BKG.HQR[19]` is the only supported positive guarded runtime/load baseline for the background-backed viewer path.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` remains the explicit zero-fragment control path for evidence and test surfaces, but the guarded `inspect-room` / viewer seam rejects it with `ViewerUnsupportedSceneLife`.
- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` remains the checked-in fragment evidence pair, but only on explicit unchecked or test-local paths rather than the guarded runtime/load seam.
- The decoder loads `RESS.HQR[0]` plus referenced top-surface `BRK` entries and fails fast if an expected preview is missing.
- Exterior `.ILE/.OBL`, full brick rasterization, and actor visual binding stay outside this pack.

## Known Traps

- `LBA_BKG.HQR[2]` is not the whole room story; the global header and late `TabAllCube` entry matter.
- Mixing zero-based classic indices with the older one-based helpers will shift you onto the wrong payload.
- `gri_header.my_grm` is a forward cursor, not ownership proof. In the checked-in assets, backgrounds `0..10` all report `my_grm = 0`, but only the last grid owns fragment `149`; canonical background `2` owns none.
- The positive pair `11/10` only projects cleanly if fragment-zone maxima are treated as boundary-aligned endpoints.
- `inspect-room --json` reports probe counts and `BRK` summaries, not the projected fragment cells behind the comparison panel; under the current guard it succeeds only for supported pairs such as `19/19`, so use viewer/tests for per-cell deltas and explicit unchecked evidence paths for `11/10`.
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
- `cd port && zig build tool -- inspect-room 19 19 --json`
- `pwsh -File .\scripts\verify-viewer.ps1`
- `cd port && zig build test`

## Open Unknowns

- Whether interior and exterior background paths should ever share more runtime surface than they do today.

