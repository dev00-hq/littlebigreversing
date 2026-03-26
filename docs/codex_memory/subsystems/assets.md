# Assets

## Purpose

Own the canonical asset CLI, HQR container primitives, raw entry extraction, and deterministic fixture generation for the Zig port.

## Invariants

- Keep one canonical asset path under `port/src/assets/`.
- Treat checked-in docs as authority and `work/port/phase1/` as rebuildable output.
- Preserve the older one-based HQR helper surface where scene tooling already depends on it.

## Current Parity Status

- Phase 1 asset CLI is implemented and validated.
- `inspect-hqr`, `extract-entry`, `generate-fixtures`, and asset inventory generation are live.
- Typed BODY/ANIM/SPRITES decoding is still outside this pack.

## Known Traps

- `RESS.HQR` reuses offsets, so entry sizes are not simply "next table slot minus current slot".
- The phase0 `RESS.HQR[49]` target is semantically right but physically resolves to the previous payload slot.

## Canonical Entry Points

- `port/src/assets/hqr.zig`
- `port/src/assets/catalog.zig`
- `port/src/assets/fixtures.zig`

## Important Files

- `docs/PHASE1_IMPLEMENTATION_MEMO.md`
- `port/src/tools/cli.zig`
- `port/src/testing/fixtures.zig`

## Test / Probe Commands

- `cd port && zig build tool -- inspect-hqr SCENE.HQR --json`
- `cd port && zig build tool -- generate-fixtures`
- `cd port && zig build test`

## Open Unknowns

- Which typed asset decoders should land next after the current scene/background slices.
- Whether any future asset surfaces need new fixture targets beyond the current phase0 set.
