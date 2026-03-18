# Handoff

## Current State

The repo still has more checked-in research than runtime code overall, but `port/` now contains the first canonical Zig workspace for the Phase 1 `Foundation + asset CLI` package. The checked-in phase 0 baseline under `docs/phase0/` remains the planning authority, while deterministic Phase 1 outputs now regenerate under `work/port/phase1/`.

## Verified Facts

- `tools/mbn_workbench.py` reads checked-in corpus data and writes generated SQLite state under `work/mbn_workbench/`.
- `docs/mbn_reference/README.md` explicitly names one canonical corpus snapshot.
- `port/README.md` now defines the first implementation package as `Foundation + asset CLI` for the Zig 0.15.2 + SDL2 port.
- `docs/PORTING_REPORT.md` has been trimmed to evidence, tooling, risks, and workspace-state coverage, while `docs/LBA2_ZIG_PORT_PLAN.md` owns execution planning.
- `tools/lba2_phase0.py` now rebuilds and validates the phase 0 baseline through `build`, `inventory-assets`, `map-source`, `export-evidence`, and `validate`.
- `docs/phase0/` locks canonical inputs, source ownership, golden targets, and unresolved evidence gaps for the next implementation-planning step.
- `work/phase0/` now regenerates deterministic `asset_inventory.json`, `source_ownership.json`, `evidence_bundle.json`, and `phase0_manifest.json`.
- `port/build.zig` now installs `lba2` and `lba2-tool`, with working `tool`, `test`, and `validate-phase1` steps rooted directly at `port/`.
- `port/src/` now contains the canonical Phase 1 modules for path resolution, diagnostics, SDL bootstrap, deterministic asset cataloging, HQR container inspection, raw entry extraction, fixture generation, and validation.
- `zig build run`, `zig build test`, `zig build tool -- inventory-assets`, `zig build tool -- generate-fixtures`, `zig build tool -- inspect-hqr SCENE.HQR --json`, and `zig build validate-phase1` all pass against the current workspace and asset root.
- `work/port/phase1/` now regenerates deterministic `asset_catalog.json`, `fixture_manifest.json`, extracted entry bytes, and locked raw fixture dumps.
- The `RESS.HQR[49]` fixture target is semantically backed by the phase 0 corpus label but physically extracts slot `48`, because the raw container ends with an empty terminal marker while the previous slot contains the movie-name index payload (`ASCENSEU.SMK`, etc.).
- `docs/PHASE1_IMPLEMENTATION_MEMO.md` now records the implemented Phase 1 workspace surface, validation status, the repo-local SDL2 wiring, and the HQR/fixture surprises uncovered during real-asset verification.
- `port/build.zig` now resolves SDL2 from the repo-local `vcpkg_installed/x64-windows` import library and installs `SDL2.dll` beside the emitted app, so the smoke shell is no longer blocked on ambient system PATH state.
- The obsolete ignored `port/hello-world/` placeholder workspace has been deleted, so `port/` now has one canonical Phase 1 implementation path on disk as well as in docs.
- The first Phase 2 slice is now in place: `port/src/assets/hqr.zig` parses the wrapped HQR resource header and expands classic LZ-compressed entries, while `port/src/game_data/scene.zig` parses typed `SCENE.HQR` metadata for the world header, ambience, hero start block, non-hero object prefixes, zones, track points, and patches.
- `zig build tool -- inspect-scene <entry-index> [--json]` now decodes `SCENE.HQR` through that typed path, and real-asset verification succeeded for entries `2`, `4`, and `5`.

## Open Risks

- The repo has many pre-existing modified files, especially in corpus/reference areas; avoid reverting or normalizing unrelated changes.
- Without regular updates, Codex state can drift back into chat-only context and stop being durable.
- The player actor target for `SCENE.HQR[2]` is only partially locked: slot `0` is proven, but a direct hero body/animation binding is still unresolved and should not be guessed in phase 1 code.
- The phase 0 `exterior-area-citadel-cliffs` target still needs tighter runtime validation: under the classic scene loader layout, decoded `SCENE.HQR` entries `4` and `5` both currently report `cube_mode == 0` (interior), so scene-number versus HQR-entry indexing and the semantic label both need re-checking before any exterior-specific logic depends on that target.

## Next 3 Steps

1. Use `python3 tools/codex_memory.py context` at the start of the next substantive task.
2. Extend the `SCENE.HQR` decoder into the next bounded Phase 2 slice, most likely typed zone semantics or safe handling for hero/object track and life script blobs.
3. Reconcile the phase 0 exterior target with the classic loader's `numscene + 1` indexing before relying on `SCENE.HQR[4]` for exterior-specific validation.
