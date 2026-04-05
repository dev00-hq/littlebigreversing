# Subsystem Index

## Pack List

- `assets`: Phase 1 asset CLI, HQR primitives, extraction, and fixtures.
- `mbn_corpus`: MBN reference corpus, preserved tooling, and workbench pipeline.
- `phase0_baseline`: Canonical inputs, evidence bundle, and golden targets.
- `scene_decode`: Typed `SCENE.HQR` metadata and track decoding.
- `life_scripts`: Offline life decoding and blocker audit surface.
- `backgrounds`: Interior `LBA_BKG.HQR` metadata and linkage path.
- `platform_windows`: Canonical Windows build and runtime host.
- `platform_linux`: Linux Bash analysis-only host notes.
- `architecture`: Repo-wide port direction, module seams, and memory workflow.

## Path Mapping Rules

- `assets`: `docs/PHASE1_IMPLEMENTATION_MEMO.md`, `port/src/assets/`, `port/src/testing/fixtures.zig`
- `mbn_corpus`: `docs/mbn_reference/`, `tools/mbn_catalog_parser.py`, `tools/mbn_workbench.py`, `tools/mbn_workbench.md`, `reference/discourse-downloader/`, `reference/littlebigreversing/`
- `phase0_baseline`: `docs/phase0/`, `tools/lba2_phase0.py`
- `scene_decode`: `port/src/game_data/scene.zig`, `port/src/game_data/scene/model.zig`, `port/src/game_data/scene/parser.zig`, `port/src/game_data/scene/zones.zig`, `port/src/game_data/scene/track_program.zig`, `port/src/game_data/scene/tests.zig`, `port/src/game_data/scene/tests/asset_regressions.zig`, `port/src/game_data/scene/tests/parser_tests.zig`, `port/src/game_data/scene/tests/support.zig`, `port/src/game_data/scene/tests/track_program_tests.zig`, `port/src/game_data/scene/tests/zone_tests.zig`
- `life_scripts`: `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`, `port/src/game_data/scene/life_audit.zig`, `port/src/game_data/scene/life_program.zig`, `port/src/game_data/scene/tests/life_audit_fast_tests.zig`, `port/src/game_data/scene/tests/life_audit_all_scene_tests.zig`, `port/src/game_data/scene/tests/life_program_tests.zig`
- `backgrounds`: `port/src/game_data/background.zig`, `port/src/game_data/background/`
- `platform_windows`: `port/build.zig`, `scripts/check-env.ps1`, `scripts/dev-shell.ps1`
- `platform_linux`: `docs/codex_memory/subsystems/platform_linux.md`
- `architecture`: `AGENTS.md`, `ISSUES.md`, `docs/LBA2_ZIG_PORT_PLAN.md`, `docs/PORTING_REPORT.md`, `docs/PROMPT.md`, `docs/codex_memory/README.md`, `docs/codex_memory/current_focus.md`, `docs/codex_memory/project_brief.md`, `port/README.md`, `tools/codex_memory.py`, `tools/test_codex_memory.py`
