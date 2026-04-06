# Architecture

## Purpose

Own repo-wide port direction and the canonical Codex memory workflow.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `port/` stays canonical; `world_geometry.zig` owns geometry, `room_state.zig` guarded loads plus negative-load life diagnostics, `session.zig` world-position seeds, `world_query.zig` query/coverage plus neighbor-summary computation, `locomotion.zig` step results, `viewer_shell.zig` diagnostics/schematic payloads, `main.zig` input routing plus guarded negative startup formatting, and `render.zig` display-only cues.

## Known Traps

- `docs/PROMPT.md` can lag; cross-check packs and history.
- `sidequest/` and `LM_TASKS/` are independent workstreams, not part of canonical memory pickup unless a prompt explicitly widens scope.
- `docs/PORTING_REPORT.md` and old migration notes are historical context.
- The checked-in memory docs can lag the worktree; verify code and `git status`.
- Canonical Windows Zig checks should run from native PowerShell after `.\scripts\dev-shell.ps1`.
- `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` are the daily loop, not the full gate.
- `zig build test` is not a substitute for explicit `zig build run` or `zig build tool` acceptance.
- Interrupted `zig build run` launches can strand `port/zig-out/bin/lba2.exe`; clear the stale process before blaming the code.
- If `python tools/codex_memory.py validate` fails, inspect the flagged JSONL records before blaming the CLI.
- Preserved legacy docs are evidence, not numeric ground truth; trust checked-in probes for exact values.
- On guarded `19/19`, the exact containing-zone result for admitted `39/6` and the accepted south step is the empty set.
- Do not confuse the guarded `19/19` diagnostic baseline with a Phase 5 playable-path candidate. The supported startup still lands on `raw_invalid_start` with `track_count=0`.
- The `19/19` zone-summary contract is intentional: HUD uses `ZONES NONE` / `ZONES <indices>`, stderr uses `zones=none` / `zones=<indices>`, and both come from the same zone order.
- The positive `19/19` startup contract is intentional: stderr now includes runtime-owned `event=neighbor_pattern_summary ...`; do not recompute it in viewer code.
- The `19/19` move-option contract is intentional: HUD uses direction/cell/status lines, stderr keeps `direction:cell:status:coverage_relation:coverage_dx:coverage_dz`, and the schematic uses current-cell plus colored `N/E/S/W` target cues.
- Guarded negative `inspect-room` and viewer-startup loads keep `ViewerUnsupportedSceneLife` public while preceding it with `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` for the first blocking blob only.
- The raw-invalid-start contract is intentional: HUD uses `DIAG ...` / `BOUNDS ...` / `NEAR ...`; stderr uses `diagnostic_status=...`, `occupied_coverage=...`, bounds, and `nearest_*=...`.
- `19/19` admitted footing is intentional: HUD uses `SURF ...`, stderr uses `current_footing=...`, and both come from `local_topology`.
- `19/19` rejected-target coverage is intentional: stderr uses explicit `target_occupied_*` fields for admitted-position `target_rejected` only.
- On admitted-position `target_rejected`, widened per-option `move_options=` coverage is contextual only; keep explicit `target_occupied_*` as the chosen-attempt surface.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `port/README.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `tools/codex_memory.py`

## Test / Probe Commands

- `python3 tools/codex_memory.py validate`

## Open Unknowns

- Which future runtime seams need their own subsystem packs.
