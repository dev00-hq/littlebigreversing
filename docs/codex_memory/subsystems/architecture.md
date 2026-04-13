# Architecture

## Purpose

Own repo-wide direction and the canonical Codex memory workflow across the two active tracks: the Zig port and the original-runtime evidence lane.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence work stays explicit and tool-owned; it is supporting evidence, not the default port execution path.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- The Zig port remains decode-first, Windows-first, and fail-fast.
- `life_audit.zig` owns offline decoded-interior ranking and unsupported-life evidence.
- `tools/life_trace/trace_life.py` owns original-runtime evidence capture.
- The canonical original-runtime split is stable for now: Tavern uses a live Frida/FRA proof lane, Scene11 uses a debugger-backed snapshot lane.

## Known Traps

- `docs/PROMPT.md` can lag; prefer subsystem packs and typed history.
- `sidequest/` and `LM_TASKS/` are independent workstreams unless a prompt explicitly widens scope.
- Tracked `work/` artifacts can lag the real worktree; verify code, `git status`, and asset paths before treating generated files as canonical truth.
- On this Windows checkout, prefer native Windows Git for repo-state checks; Bash-under-`/mnt/d` can over-report dirtiness.
- In PowerShell-hosted sessions, `bash -lc "..."` can be mangled before Bash sees it; prefer single-quoted Bash payloads in tool calls.
- `scripts/verify_viewer.py` is the canonical Windows acceptance gate for the port path.
- Original-runtime evidence helpers are not default port pickup; use `life_scripts.md` when the task is about Tavern, Scene11, Frida, or debugger capture.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `port/README.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `tools/codex_memory.py`
- `tools/life_trace/trace_life.py`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`

## Open Unknowns

- Which future runtime seams deserve their own subsystem packs.
- Whether the current split between port work and original-runtime evidence should eventually become a more explicit top-level repo boundary.
