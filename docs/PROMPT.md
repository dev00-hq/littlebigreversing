# Foundation + Asset CLI Spec

## Summary

Replace the placeholder `port/hello-world` package with the canonical Zig workspace rooted directly at `port/`, and deliver two artifacts for Phase 1:

- `lba2`: a minimal SDL2 smoke app that proves the runtime shell, path resolution, and diagnostics.
- `lba2-tool`: a CLI-first asset tool focused on deterministic inventory, HQR inspection, raw entry extraction, fixture generation, and validation.

This phase stays intentionally narrow: no viewer, no typed scene/body/anim decoding, no gameplay, and no compatibility paths for alternate repo layouts. The Python phase 0 tool remains the authority for the locked baseline and is not replaced.

## Implementation Changes

- Workspace structure:
  - `port/build.zig` installs both executables and defines `run`, `tool`, `test`, and `validate-phase1` steps.
  - Modules are split into `foundation` (path resolution, logging, diagnostics), `platform` (SDL2 bootstrap), `assets` (HQR container primitives and catalog generation), and `tools` (CLI command handlers).
- Path/config policy:
  - Default `asset_root` is the canonical phase 0 path `work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2`.
  - Both executables accept `--asset-root <path>` as the only override.
  - No env-var config, no persisted config file, and no fallback search paths in Phase 1.
  - All generated Phase 1 artifacts live only under `work/port/phase1`.
- SDL app behavior:
  - `zig build run` launches `lba2`, resolves paths, validates the required Phase 1 files, opens a basic SDL2 window, and logs startup diagnostics in line-oriented `key=value` form.
  - The app does not decode gameplay assets yet; it only proves the shell and exits cleanly on invalid roots, missing required files, or SDL init failures.
- CLI behavior:
  - `inventory-assets`: scan the selected asset root and write `work/port/phase1/asset_catalog.json` using the same core entry fields already present in phase 0 (`relative_path`, `asset_class`, `locale_bucket`, `required_for_phase1`, `size_bytes`, `sha256`).
  - `inspect-hqr <relative-path> [--json]`: parse only the HQR container/table layer and report `entry_count` plus per-entry `index`, `offset`, `byte_length`, and `sha256`. No typed payload interpretation.
  - `extract-entry <relative-path> <entry-index>`: write raw bytes to `work/port/phase1/extracted/<sanitized-asset-path>/<entry-index>.bin`.
  - `generate-fixtures`: emit `work/port/phase1/fixture_manifest.json` plus raw fixture dumps for the locked targets needed by later phases: `SCENE.HQR[2]`, `LBA_BKG.HQR[2]`, `SCENE.HQR[4]`, `VOX/EN_GAM.VOX[1]`, `VIDEO/VIDEO.HQR[1]`, and `RESS.HQR[49]`.
  - `validate-phase1`: re-run required-file checks, inventory generation, and fixture generation, then fail on output drift or invalid container structure.
- Public interfaces/types:
  - `ResolvedPaths { repo_root, asset_root, work_root }`
  - `AssetCatalogEntry { relative_path, asset_class, locale_bucket, required_for_phase1, size_bytes, sha256 }`
  - `HqrArchive { entry_count, entries }`
  - `HqrEntry { index, offset, byte_length, sha256 }`
  - `FixtureManifestEntry { target_id, asset_path, entry_index, output_path, sha256 }`
- Explicit non-goals for this package:
  - typed `SCENE.HQR`, `BODY.HQR`, `ANIM.HQR`, `SPRITES.HQR`, or `TEXT.HQR` decoding
  - scene viewer or renderer beyond the SDL smoke window
  - guessed hero body/animation linkage for `SCENE.HQR[2]`
  - forced resolution of the provisional scene-to-island or subtitle pairings

## Test Plan

- `zig build test` passes using checked-in synthetic HQR fixtures and covers:
  - canonical path resolution and `--asset-root` override behavior
  - deterministic catalog ordering and JSON serialization
  - HQR header/table parsing, invalid offsets/counts, and out-of-range entry access
  - extraction path sanitization so outputs cannot escape `work/port/phase1`
- `zig build validate-phase1` requires the selected asset root and covers:
  - required Phase 1 files exist and are readable
  - regenerated `asset_catalog.json` and `fixture_manifest.json` are deterministic
  - fixture extraction for the locked target entries succeeds repeatedly with stable hashes
- Manual smoke acceptance:
  - `zig build run` opens and closes the SDL2 shell successfully on Windows
  - `zig build tool -- inspect-hqr SCENE.HQR --json` returns machine-readable metadata
  - invalid asset roots, missing required files, corrupt HQR structure, and bad entry indices all fail with explicit diagnostics

## Assumptions And Defaults

- Phase 1 is CLI-first; the SDL app is a smoke shell, not an early viewer.
- External dependencies are limited to Zig stdlib plus SDL2, if not enough, give the user a couple of options and wait for confirmation.
- The Zig CLI complements phase 0 outputs; it does not mutate or redefine `docs/phase0/` or `work/phase0/`.
- Default tests must not depend on live game assets; asset-backed verification is isolated to `validate-phase1`.
- The placeholder `port/hello-world` is deleted rather than preserved behind compatibility glue.
