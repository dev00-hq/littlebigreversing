# Subsystem Index

## Pack List

- `assets`: Phase 1 asset CLI, HQR primitives, extraction, and fixtures.
- `mbn_corpus`: MBN reference corpus, preserved tooling, and workbench pipeline.
- `phase0_baseline`: Canonical inputs, evidence bundle, and golden targets.
- `scene_decode`: Typed `SCENE.HQR` metadata and track decoding.
- `life_scripts`: Offline life decoding and blocker audit surface.
- `backgrounds`: Interior `LBA_BKG.HQR` metadata and linkage path.
- `intelligence`: Room and scene inspection contracts.
- `platform_windows`: Canonical Windows build and runtime host.
- `platform_linux`: Linux Bash analysis-only host notes.
- `architecture`: Repo-wide port direction, module seams, and memory workflow.

## Path Mapping Rules

- `assets`: `docs/PHASE1_IMPLEMENTATION_MEMO.md`, `port/src/assets/`, `port/src/testing/`, `port/src/testing/fixtures.zig`
- `mbn_corpus`: `docs/mbn_reference/`, `tools/mbn_catalog_parser.py`, `tools/mbn_workbench.py`, `tools/mbn_workbench.md`, `reference/discourse-downloader/`, `reference/littlebigreversing/`
- `phase0_baseline`: `docs/phase0/`, `tools/lba2_phase0.py`, `tools/build_scene_crosswalk.py`
- `scene_decode`: `port/src/game_data/scene.zig`, `port/src/game_data/scene/model.zig`, `port/src/game_data/scene/parser.zig`, `port/src/game_data/scene/zones.zig`, `port/src/game_data/scene/track_program.zig`, `port/src/game_data/scene/tests.zig`, `port/src/game_data/scene/tests/asset_regressions.zig`, `port/src/game_data/scene/tests/parser_tests.zig`, `port/src/game_data/scene/tests/support.zig`, `port/src/game_data/scene/tests/track_program_tests.zig`, `port/src/game_data/scene/tests/zone_tests.zig`
- `life_scripts`: `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`, `port/src/game_data/scene/life_audit.zig`, `port/src/game_data/scene/life_program.zig`, `port/src/game_data/scene/tests/life_audit_fast_tests.zig`, `port/src/game_data/scene/tests/life_audit_all_scene_tests.zig`, `port/src/game_data/scene/tests/life_program_tests.zig`, `tools/cdb_tail.py`, `tools/ghb_export_lm_callsites.py`, `tools/lba2_frida_cdb_bootstrap.py`, `tools/life_trace/`, `tools/map_idajs_saves.py`, `tools/test_dialog_text_scan.py`, `tools/test_ghb_export_lm_callsites.py`, `tools/test_life_trace.py`
- `backgrounds`: `port/src/game_data/background.zig`, `port/src/game_data/background/`
- `intelligence`: `port/src/tools/cli.zig`, `port/src/tools/room_intelligence.zig`, `port/src/tools/cli_room_load_integration_test.zig`, `port/src/generated/`, `port/src/generated/room_metadata.zig`, `tools/generate_reference_metadata.py`, `tools/generate_room_metadata.py`, `tools/test_generate_reference_metadata.py`, `tools/test_generate_room_metadata.py`
- `platform_windows`: `port/build.zig`, `scripts/check-env.py`, `scripts/dev-shell.py`
- `platform_linux`: `docs/codex_memory/subsystems/platform_linux.md`
- `architecture`: `AGENTS.md`, `ISSUES.md`, `docs/LBA2_ZIG_PORT_PLAN.md`, `docs/PORTING_REPORT.md`, `docs/codex_memory/README.md`, `docs/codex_memory/current_focus.md`, `docs/codex_memory/project_brief.md`, `port/README.md`, `port/src/app/`, `port/src/foundation/`, `port/src/main.zig`, `port/src/platform/`, `port/src/root.zig`, `port/src/runtime/`, `port/src/sidequest_room_actor_runtime_probe.zig`, `port/src/sidequest_room_actor_seed_admission_probe.zig`, `port/src/test_cli_integration.zig`, `port/src/test_fast.zig`, `port/src/test_life_audit_all.zig`, `port/src/tool_main.zig`, `tools/benchmark_codex_memory.py`, `tools/codex_memory.py`, `tools/test_codex_memory.py`
