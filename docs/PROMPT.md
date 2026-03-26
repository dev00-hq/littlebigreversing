# Next Step: First Interior Background Decoder

## Summary

The targeted `LM_DEFAULT` / `LM_END_SWITCH` evidence pass is already complete, and life integration remains blocked on those two unsupported real-asset opcodes.

The next bounded subsystem should therefore move sideways into the first viewer dependency: typed interior background decoding for the canonical room target instead of more blocked life work.

Phase 0 already locks the first interior room as `SCENE.HQR[2]` paired with `LBA_BKG.HQR[2]`, but the checked-in classic loader shows that interior background loading is not just "decode entry 2 in isolation". The source-backed boundary is:

- `LBA_BKG.HQR[0]` is the typed `T_BKG_HEADER` root loaded by `InitBufferCube()`
- `TabAllCube` loads from entry `BkgHeader.Brk_Start + BkgHeader.Max_Brk`
- `InitGrille(numcube)` first remaps through `TabAllCube[numcube].Num`
- the selected `GRI` payload lives at `BkgHeader.Gri_Start + remapped_cube`
- each `GRI` payload begins with `T_GRI_HEADER` (`My_Bll`, `My_Grm`, `UsedBlock[32]`) and then carries the interior column-offset table used by `CopyMapToCube()`
- the selected `BLL` payload lives at `BkgHeader.Bll_Start + GriHeader.My_Bll`

For this slice, treat background indices in the classic `LBA_BKG.HQR[...]` number space, not the current `inspect-scene` raw one-based physical-entry number space. `inspect-background 2` should therefore mean classic `LBA_BKG.HQR[2]`, while `LBA_BKG.HQR[0]` remains the special header block at the HQR table boundary rather than a normal one-based extracted entry.

This slice should implement a typed, fail-fast interior background decoder and a separate inspection surface that make the room/background linkage executable without expanding into rendering, exterior terrain, or gameplay.

## Key Changes

- Add a dedicated interior background surface.
  - Introduce a stable `game_data` facade for interior background decoding, following the same public-surface pattern used for `scene.zig`.
  - Add `zig build tool -- inspect-background <entry-index> [--json]` as the canonical CLI for this slice, where `<entry-index>` is the classic `LBA_BKG.HQR[...]` index for the requested interior cube/background target.
  - Keep the scene and background inspection surfaces separate; do not stuff background decoding into `inspect-scene`.

- Decode source-backed interior metadata only.
  - Materialize `T_BKG_HEADER` from classic entry `0`, the `TabAllCube` indirection entry, the selected `T_GRI_HEADER`, and the selected `BLL` linkage for the requested interior background entry.
  - Expose structural facts that are already source-backed, such as remapped cube id, selected `GRI`/`BLL`/`GRM` indices, the used-block bitset summary, and the expected `64 x 64` column table shape.
  - Treat raw HQR entry bytes as the canonical input and fail fast on truncation, inconsistent offsets, or unsupported interior shapes.
  - Prove the locked canonical pair `SCENE.HQR[2]` / `LBA_BKG.HQR[2]` for this slice, but do not widen the work into a general scene-to-background mapping layer.

- Keep the slice intentionally narrower than a viewer.
  - Do not implement exterior `.ILE` / `.OBL` loading.
  - Do not implement brick raster decoding, mask generation, GRM redraw behavior, or SDL rendering in this slice unless a tiny amount of structural decoding is strictly required for metadata correctness.
  - Do not guess hero or object `BODY.HQR` / `ANIM.HQR` bindings from scene `2`.
  - Do not revisit `life_program.zig`, `life_audit.zig`, or the life-script prompt boundary as part of this work.

## Test Plan

- Keep `zig build test` as the primary validation gate.
- Add synthetic parser coverage for header, `GRI`, and indirection-table truncation or shape failures.
- Add an asset-backed regression on the canonical interior pair so the new CLI proves the scene/background linkage on the current asset tree.
- Acceptance commands:
  - `zig build test`
  - `zig build tool -- inspect-background 2 --json`
  - `zig build tool -- inspect-scene 2 --json` as a cross-check only; do not merge background decoding into the scene CLI surface.

## Assumptions

- The canonical extracted asset tree still contains the checked-in `SCENE.HQR` / `LBA_BKG.HQR` pair used by phase 0.
- `docs/phase0/golden_targets.md`, `reference/lba2-classic/SOURCES/GRILLE.CPP`, `reference/lba2-classic/SOURCES/DISKFUNC.CPP`, `reference/lba2-classic/SOURCES/INTEXT.CPP`, and `reference/lba2-classic/SOURCES/DEFINES.H` remain the primary evidence boundary for this slice.
- The first interior background decoder only needs typed metadata and linkage; full viewer rendering, exterior terrain, and actor visual binding are separate later slices.
- The local acceptance gate is still environment-dependent: `zig build test`, `inspect-background`, and `inspect-scene` depend on the canonical extracted asset tree and the repo-local SDL2 layout on this machine.
