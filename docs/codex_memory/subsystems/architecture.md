# Architecture

## Purpose

Own repo-wide port direction and the canonical Codex memory workflow.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `docs/LBA2_ZIG_PORT_PLAN.md` remains the roadmap, `port/` remains the only implementation workspace, the v2 memory tree stays canonical, `port/src/runtime/room_state.zig` owns the guarded `19/19` room/load seam, and `port/src/runtime/world_query.zig` owns the explicit hero-start mapping diagnostics over immutable room snapshots.

## Known Traps

- `docs/PROMPT.md` can lag behind repo work; cross-check current packs and history before following it literally.
- The current viewer uses decoded `BRK` previews plus a live HUD/legend, but it is still not a full room-art renderer and the window title/stderr dump is no longer the canonical debug surface.
- `inspect-room --json` now shares the guarded runtime/load seam, so `11/10` no longer succeeds there by design. Even on supported rooms it still reports counts, linkage, and `BRK` summaries rather than projected comparison cells, so validate per-cell deltas via viewer tests/runtime.
- Treat `2/2` as the explicit zero-fragment control path and do not infer fragments from `my_grm` or `grm_entry_index` alone.
- After the branch-B load guard landed, `2/2` stopped being a positive runtime fixture; use it as an explicit unsupported-scene-life rejection case instead.
- The positive fragment evidence pair is `11/10`, not a same-index guess, and its `grm` projection needs boundary-aligned max-coordinate handling.
- `11/10` is still valuable fragment evidence, but it is no longer a guarded runtime-positive load; keep it on explicit test-only evidence paths unless the supported life boundary widens.
- `docs/PORTING_REPORT.md` still carries older feasibility context; use it as evidence background, not as the execution owner.
- Canonical Windows Zig checks should run from native PowerShell after `.\scripts\dev-shell.ps1`; reserve `bash -lc` for inspection work.
- `zig build test` is not a substitute for a prompt's explicit `zig build run` or `zig build tool` acceptance command.
- Interrupted `zig build run` viewer launches can strand `lba2.exe` under `port/zig-out/bin/` and make the next install step fail with `AccessDenied`. If that happens, clear the stale `lba2` process before treating the runtime command as a code regression.
- `tools/codex_memory.py` validates subsystem-pack budgets on write. If an `add-*` command fails, check oversized packs as well as JSONL drift.
- `ISSUES.md` must stay aligned with new recurring traps instead of leaving them only in chat or task history.
- The checked-in v2 history can already be dirty. If `python tools/codex_memory.py validate` fails at task start, inspect the flagged JSONL records for canonicalization drift such as stale `record_id` hashes, fractional-second timestamps, or overlong summaries before treating the CLI as the problem.
- Preserved legacy docs are evidence, not numeric ground truth. If a spec mixes index bases or disagrees with asset-backed regressions, keep the structural insight but trust the checked-in probe or test for exact values.

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

- Which future runtime seams deserve their own subsystem packs once work moves past the current viewer/runtime slices.
