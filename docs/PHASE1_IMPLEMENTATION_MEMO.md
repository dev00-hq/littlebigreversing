# Phase 1 Implementation Memo

## Scope

This memo records the work completed to replace the placeholder `port/hello-world` package with the canonical Phase 1 Zig workspace rooted directly at `port/`.

The target package boundary remains:

- `lba2`: SDL2 smoke app
- `lba2-tool`: CLI-first asset tool

Phase 1 stays intentionally narrow:

- no typed scene/body/anim decoding
- no viewer
- no gameplay
- no compatibility paths for alternate layouts or older local states

## What Was Implemented

The new checked-in workspace now lives directly under `port/`:

- `port/build.zig`
- `port/build.zig.zon`
- `port/src/`

The module split follows the planned boundary:

- `foundation`
  - canonical repo-root, asset-root, and work-root resolution
  - fail-fast diagnostics
  - recursive path creation for `work/port/phase1`
- `platform`
  - SDL2 bootstrap for the smoke app shell
- `assets`
  - deterministic asset catalog generation
  - HQR container parsing
  - raw entry extraction
  - fixture generation
- `tools`
  - CLI command parsing and command handlers

The workspace now provides these build surfaces:

- `zig build test`
- `zig build tool -- <command>`
- `zig build validate-phase1`
- `zig build run`

The CLI now implements:

- `inventory-assets`
- `inspect-hqr <relative-path> [--json]`
- `extract-entry <relative-path> <entry-index>`
- `generate-fixtures`
- `validate-phase1`

Generated Phase 1 outputs now live only under:

- `work/port/phase1/asset_catalog.json`
- `work/port/phase1/fixture_manifest.json`
- `work/port/phase1/extracted/`
- `work/port/phase1/fixtures/`

## Validation Status

These commands were verified successfully on this machine:

- `zig build test`
- `zig build tool -- inventory-assets`
- `zig build tool -- inspect-hqr SCENE.HQR --json`
- `zig build tool -- generate-fixtures`
- `zig build validate-phase1`
- `python3 tools/codex_memory.py validate`

`zig build run` was **not** fully verified because Zig could not link the SDL smoke app on this machine.

The exact linker failure was:

- Zig 0.15.2 could not find the dynamic system library `SDL2`

That means:

- the SDL-facing app code is present
- the build graph is wired for the smoke app
- the runtime shell still needs SDL2 installed or exposed on the system library path before `zig build run` can succeed

## Zig And SDL2 Note

The canonical runtime target is still Zig 0.15.2 plus SDL2.

The current state is:

- Zig 0.15.2 is installed and was used for all successful CLI and test validation
- SDL2 headers/libs are **not** currently discoverable by Zig for linking on this machine

So the correct next step for the smoke app is not code redesign. The missing piece is environment setup:

- install SDL2 for Windows in a location Zig can find
- or expose the SDL2 import library and runtime DLL through the expected library search path

Until that is done, `lba2-tool` is the validated executable surface and `lba2` remains source-complete but link-blocked.

## Surprises Encountered

Several implementation details were less straightforward than the initial prompt implied.

### 1. HQR offsets are not always monotonic

The first parser assumption treated HQR entry offsets as globally increasing.

That worked for:

- `SCENE.HQR`
- `LBA_BKG.HQR`
- `VOX/EN_GAM.VOX`
- `VIDEO/VIDEO.HQR`

It failed for `RESS.HQR`.

`RESS.HQR` contains repeated offsets that alias earlier payload blocks instead of always pointing to a unique later block. The parser had to be updated to:

- allow repeated offsets
- treat `0` as an empty slot
- derive entry byte lengths from the next greater offset rather than simply the next table position

### 2. `RESS.HQR[49]` is semantically right but physically awkward

The phase 0 evidence and prompt both refer to `RESS.HQR[49]` as the movie-name index entry.

The raw container bytes showed a quirk:

- the last physical table slot is an empty terminal marker
- the actual movie-name payload containing strings like `ASCENSEU.SMK` lives in the previous physical slot

To keep the Phase 1 fixture manifest aligned with the checked-in evidence vocabulary, the fixture target stays labeled as:

- `RESS.HQR`, entry `49`

But extraction is mapped internally to the physical slot that contains the bytes.

This keeps the public Phase 1 artifact aligned with the canonical evidence baseline without inventing a compatibility layer.

### 3. Windows directory creation needed explicit recursion

Creating `work/port/phase1` on Windows failed when using the simplest absolute directory creation call directly.

The path layer had to be hardened to create missing parent directories recursively for:

- `work/port/phase1`
- extracted entry directories
- fixture directories

### 4. Zig 0.15.2 stdlib APIs required a few adjustments

The initial implementation had to be adapted for actual Zig 0.15.2 APIs during compilation:

- JSON output switched to `std.json.Stringify`
- hex encoding switched to `std.fmt.bytesToHex`
- stdio handling switched to the current file writer interfaces

These were normal toolchain-fit fixes rather than design changes.

## Result

Phase 1 now has one canonical checked-in implementation path under `port/`.

The main outcome is:

- the asset CLI and validation pipeline are real, not speculative
- deterministic Phase 1 generated outputs now exist under `work/port/phase1`
- the HQR parser is validated against the live asset root, including the non-trivial `RESS.HQR` cases
- the remaining blocker for the smoke app is SDL2 linkage on this machine, not missing workspace code
