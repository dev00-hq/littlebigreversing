# Handoff

## Current State

The repo still has more checked-in research than runtime code overall, but `port/` now contains the first canonical Zig workspace for the Phase 1 `Foundation + asset CLI` package. The checked-in phase 0 baseline under `docs/phase0/` remains the planning authority, while deterministic Phase 1 outputs now regenerate under `work/port/phase1/`.
The next bounded Phase 2 slice is now implemented on top of that workspace: `SCENE.HQR` zones decode into a typed, source-backed zone model that preserves raw payload fields alongside normalized load-time semantics. The old phase 0 exterior target ambiguity is now resolved: the misclassified `SCENE.HQR[4]` room scene has been retired in favor of the canonical exterior target `SCENE.HQR[44]`.

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
- `zig build tool -- inspect-scene <entry-index> [--json]` now decodes `SCENE.HQR` through that typed path, and real-asset verification succeeded for entries `2`, `5`, and the canonical exterior target `44`.
- `zig build test` now includes both synthetic negative coverage and real asset-backed regression checks for wrapped `SCENE.HQR` entry decompression plus typed scene metadata decoding for the canonical scene targets, instead of relying only on handcrafted fixtures and manual inspection.
- `port/src/game_data/scene.zig` now treats `SceneZone` as a typed zone record with `raw_info`, `zone_type`, and source-backed `semantics`, failing fast on unsupported zone types plus unsupported message or escalator direction encodings.
- The zone semantic layer now maps change-cube, camera, GRM, ladder, rail, escalator, hit, message, and scenario fields from classic loader/runtime evidence while keeping unresolved control bytes in `raw_info`, including the change-cube control selector in `raw_info[4]`.
- Giver zones now expose allowed bonus kinds from the classic `Info0` flag mask instead of inventing one fixed load-time bonus kind; `already_taken` stays a load-time-initialized `false` projection while the raw mask remains available.
- `zig build tool -- inspect-scene --json` now emits `zone_type`, `raw_info`, and a stable `semantics` object with a required `kind` field for every zone, and text mode prints compact semantic summaries instead of raw type ids alone.
- `zig build tool -- inspect-scene --json` now also emits `classic_loader_scene_number`, making the classic `LoadScene(numscene + 1)` boundary explicit beside the raw HQR entry index.
- The phase 0 exterior golden target is now `exterior-area-citadel-tavern-and-shop` on `SCENE.HQR[44]`; classic-source evidence plus live decoding prove that raw entry `44` is loader scene `42`, `cube_mode == 1`, `island == 0`, `cube_x == 7`, and `cube_y == 9`, while the old `SCENE.HQR[4]` target is a `~1` interior room scene.
- `tools/lba2_phase0.py build`, `zig build test`, `zig build tool -- generate-fixtures`, `zig build validate-phase1`, and `zig build tool -- inspect-scene 44 --json` all pass with the corrected exterior target in place.
- `docs/PROMPT.md` now tightens the upcoming typed zone-semantics slice so it preserves the source-backed change-cube control selector in `raw_info[4]`, treats GRM state as `Info2`-backed on/off instead of inventing a redraw-state field, models rail semantics as switch state rather than a generic enable flag, names camera `Info0..Info2` conservatively as anchor/start-cube fields, and keeps scene `5` regression coverage out of the locked phase 0 fixture target set.
- A 2026-03-19 readiness review confirmed the typed zone-semantics prompt is executable against the current workspace: `zig build test`, `zig build validate-phase1`, and `zig build tool -- inspect-scene {2,4,5} --json` all pass, and the remaining execution caveats are to keep camera `Info0..Info2` conservatively tied to start-cube semantics, map GRM on/off state from raw `Info2`, and remember that the test gate depends on the canonical extracted asset tree plus the repo-local SDL2 install.
- A 2026-03-19 multi-agent structure review concluded that `port/src/game_data/scene.zig` can be split safely if it remains the stable public facade, with the strongest seams being `scene/zones.zig`, `scene/model.zig`, and `scene/parser.zig`; only `port/src/tools/cli.zig` and `port/src/root.zig` currently depend on its exported surface.
- `port/src/game_data/scene.zig` is now that thin public facade, with production code split into `port/src/game_data/scene/model.zig`, `port/src/game_data/scene/zones.zig`, and `port/src/game_data/scene/parser.zig`, while synthetic and asset-backed scene tests now live in `port/src/game_data/scene/tests.zig`.
- The scene production modules no longer import test-only fixture/path helpers, but the coverage bar stayed intact: `zig build test` and `zig build tool -- inspect-scene 44 --json` both pass after the split, and the asset-backed scene assertions still exercise entries `2`, `5`, and `44`.

## Open Risks

- Avoid reverting or normalizing unrelated user changes, even though the current worktree no longer looks broadly dirty.
- Without regular updates, Codex state can drift back into chat-only context and stop being durable.
- `zig build test` is not hermetic yet: the real-asset scene regressions require the canonical extracted asset tree, and `port/build.zig` still hard-fails if the repo-local SDL2 layout is missing.
- The player actor target for `SCENE.HQR[2]` is only partially locked: slot `0` is proven, but a direct hero body/animation binding is still unresolved and should not be guessed in phase 1 code.
- Giver semantics are still intentionally conservative: the loader can expose allowed bonus kinds from `Info0`, but the final spawned bonus remains runtime-dependent through `WhichBonus()` and should not be collapsed into one canonical load-time value without stronger evidence.
- The next decoder slice still needs to respect the existing boundary: track blobs can be surfaced and decoded as scene-local metadata, but life-script interpretation is still coupled to broader runtime state and should stay deferred.

## Next 3 Steps

1. Use `python3 tools/codex_memory.py context` at the start of the next substantive task.
2. Extend the scene decoder so hero and object track blobs stop being skipped and become preserved raw payloads in the typed scene model.
3. Add a narrow track decoder/disassembler plus `inspect-scene` output for hero/object track programs before attempting any life-script interpretation.
