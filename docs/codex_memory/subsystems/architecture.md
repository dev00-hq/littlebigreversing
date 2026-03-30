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
- `port/src/app/viewer_shell.zig` now includes deterministic brick-index probe patterns, but those overlays are not the same thing as actual decoded `BRK` brick output. If the next prompt says "brick-backed" work, verify whether it means the already-landed placeholder overlay or new real brick-data evidence.
- Older prompt text can outrun the current `inspect-room --json` surface too. The CLI still reports `11/10` fragment counts, linkage, and `BRK` summaries, but not the projected fragment cells behind the viewer-local comparison panel, so validate per-cell deltas through the viewer tests/runtime.
- The canonical `2/2` interior pair is not guaranteed to exercise the next viewer slice just because the prompt says so. For fragment work specifically, the checked-in probes now show `SCENE.HQR[2]` has no `grm` zones and `LBA_BKG.HQR[2]` owns zero fragment entries, so use the explicit zero-state as the truth and do not fabricate runtime overlays from `my_grm` or `grm_entry_index` alone.
- The checked-in positive fragment evidence pair is `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]`, not a same-index guess. Scene-driven `grm` projection on that pair also requires boundary-aligned max-coordinate handling, so do not reuse the older `max - min + 1` span math from non-fragment overlays.
- `docs/PORTING_REPORT.md` still carries older feasibility context; use it as evidence background, not as the execution owner.
- The canonical Windows Zig checks should run from native PowerShell, usually after `.\scripts\dev-shell.ps1`; `bash -lc` is fine for inspection work but can miss the actual Windows toolchain layout.
- `zig build test` is not a substitute for the explicit acceptance command in a prompt. App-only compile errors can still hide on the `zig build run` path until you build the executable target directly, so keep the prompt's explicit `run` or `tool` command in the validation pass when the slice changes runtime code.
- `ISSUES.md` must stay aligned with new recurring traps instead of leaving them only in chat or task history.
- The checked-in v2 history can already be dirty. If `python tools/codex_memory.py validate` fails at task start, inspect the flagged JSONL records for canonicalization drift such as stale `record_id` hashes, fractional-second timestamps, or overlong summaries before treating the CLI as the problem.
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
