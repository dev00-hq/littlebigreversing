# Architecture

## Purpose

Own repo-wide port direction and the canonical Codex memory workflow.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `port/` stays canonical; `world_geometry.zig` owns geometry, `room_state.zig` the guarded `19/19` room/load seam, `session.zig` world-position seeds, `world_query.zig` zone/target/raw-start/topology/coverage diagnostics, `locomotion.zig` step/result packaging, `viewer_shell.zig` diagnostics/schematic payloads, and `render.zig` display-only cues.

## Known Traps

- `docs/PROMPT.md` can lag; cross-check packs and history before following it literally.
- `sidequest/` and `LM_TASKS/` are independent workstreams, not part of canonical memory pickup unless a prompt explicitly widens scope.
- `docs/PORTING_REPORT.md` and older migration notes are historical context, not the current contract.
- The checked-in memory docs can lag the live worktree; verify code and worktree before treating them as a statement about dirtiness or local experiments.
- Canonical Windows Zig checks should run from native PowerShell after `.\scripts\dev-shell.ps1`.
- `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` are the daily loop, not replacements for the canonical full gate.
- `zig build test` is not a substitute for a prompt's explicit `zig build run` or `zig build tool` acceptance command.
- Interrupted `zig build run` viewer launches can strand `lba2.exe` under `port/zig-out/bin/` and make the next install step fail with `AccessDenied`. If that happens, clear the stale `lba2` process before treating the runtime command as a code regression.
- The checked-in v2 history can already be dirty. If `python tools/codex_memory.py validate` fails, inspect flagged JSONL records before blaming the CLI.
- Preserved legacy docs are evidence, not numeric ground truth. If a spec mixes index bases or disagrees with asset-backed regressions, trust the checked-in probe or test for exact values.
- On the guarded `19/19` locomotion baseline, the exact containing-zone result for the admitted `39/6` fixture and the accepted south step is currently the empty set. Do not invent a current zone or alternate mapping scale to make that answer non-empty.
- The `19/19` zone-summary contract is intentional: HUD uses `ZONES NONE` / `ZONES <indices>`, stderr uses `zones=none` / `zones=<indices>`, and both come from the same zone order.
- The `19/19` admitted move-option contract is intentional: HUD uses direction/cell/status lines, stderr keeps `direction:cell:status`, and the schematic uses current-cell plus colored `N/E/S/W` target cues.
- The raw-invalid-start contract is intentional: HUD uses `DIAG ...` / `BOUNDS ...` / `NEAR ...`; stderr uses `diagnostic_status=...`, `occupied_coverage=...`, `occupied_bounds=...`, `occupied_bounds_dx=...`, `occupied_bounds_dz=...`, and `nearest_*=...`.
- `19/19` admitted footing is intentional: HUD uses `SURF ...`, stderr uses `current_footing=...`, and both come from `local_topology.origin_surface` plus `origin_standability`.
- `19/19` rejected-target coverage is intentional: stderr uses `target_occupied_coverage=...`, `target_occupied_bounds=...`, `target_occupied_bounds_dx=...`, and `target_occupied_bounds_dz=...` for admitted-position `target_rejected` only.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `port/README.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `docs/codex_memory/README.md`
- `tools/codex_memory.py`

## Test / Probe Commands

- `python3 tools/codex_memory.py validate`
- `python3 tools/codex_memory.py context`

## Open Unknowns

- Which future runtime seams deserve their own subsystem packs once work moves past viewer/runtime slices.
