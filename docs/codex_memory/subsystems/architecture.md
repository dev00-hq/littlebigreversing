# Architecture

## Purpose

Own repo-wide port direction, stable module seams, and the canonical Codex memory workflow surface.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `docs/LBA2_ZIG_PORT_PLAN.md` remains the canonical roadmap.
- `port/` is the only canonical implementation workspace.
- The v2 memory tree replaced the old handoff-plus-mixed-log model.

## Known Traps

- `docs/PROMPT.md` can lag behind completed repo work; cross-check against current packs before following it literally.
- `docs/PORTING_REPORT.md` still carries older feasibility context; use it as evidence background, not as the execution owner.
- The canonical Windows Zig checks should run from native PowerShell, usually after `.\scripts\dev-shell.ps1`; `bash -lc` is fine for inspection work but can miss the actual Windows toolchain layout.
- `ISSUES.md` must stay aligned with new recurring traps instead of leaving them only in chat or task history.
- Preserved legacy format docs are evidence, not a numeric ground truth. If an imported spec mixes index bases or disagrees with an asset-backed regression, keep the structural insight but trust the checked-in asset probe or test for exact values.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `docs/codex_memory/README.md`
- `tools/codex_memory.py`

## Test / Probe Commands

- `python3 tools/codex_memory.py validate`
- `python3 tools/codex_memory.py context`

## Open Unknowns

- Which future runtime seams deserve their own subsystem packs once implementation moves past inspection-only slices.
- Whether repo-local skills are worth adding on top of the current CLI without becoming canonical dependencies.
