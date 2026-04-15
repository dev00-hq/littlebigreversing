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
- `life_audit.zig` owns offline decoded-interior ranking and the canonical all-scenes life inventory.
- Viewer key handling now stops at intent submission for hero movement; runtime session owns the pending intent, and a minimal runtime tick owns consuming and applying it.
- Runtime session now also owns mutable object-position copies for the live viewer/app path, while `RoomSnapshot` remains immutable decode state.
- Guarded `19/19` now also carries an explicit immutable object-behavior seed for object `2`, while runtime owns the mutable life-byte copy and later reward-loop state.
- The life decoder structure now has a machine-readable `life-catalog-v1` CLI surface, sourced from the production enums in `life_program.zig` rather than from markdown-only evidence notes.
- `tools/life_trace/trace_life.py` owns original-runtime evidence capture.
- The canonical original-runtime split is stable for now: Tavern uses a live Frida/FRA proof lane, Scene11 uses a debugger-backed snapshot lane, and Sendell's Ball writes typed `sendell_summary.json` bundles with direct story-state reads.
- Runtime now also owns a bounded Sendell room-`36` seam: viewer input submits `cast_lightning` / `advance_story` intents, session owns magic plus `ListVarGame`, and object behavior advances the red-ball slice.

## Known Traps

- `docs/PROMPT.md` can lag; prefer subsystem packs and typed history.
- `sidequest/` and `LM_TASKS/` are independent workstreams unless a prompt explicitly widens scope.
- `work/` artifacts can lag the real worktree; verify code, `git status`, and asset paths before trusting generated outputs.
- Prefer native Windows Git for repo-state checks; Bash-under-`/mnt/d` can over-report dirtiness.
- In PowerShell-hosted sessions, prefer single-quoted `bash -lc` payloads.
- Keep the tiny top-level Zig test roots under `port/src/`; direct subdirectory roots can fail with `import of file outside module path`.
- `scripts/verify_viewer.py` is the canonical Windows acceptance gate for the port path.
- Original-runtime evidence helpers are not default port pickup; use `life_scripts.md` for Tavern, Scene11, Frida, or debugger capture work.
- Sendell room proof menus need held-key input; keep that quirk in `life_scripts.md` instead of generalizing it into the port path.
- On the current Sendell proof lane, use `0x00499E98` as the direct `ListVarGame` base, not Ghidra `DAT_00499E96`.

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
- Whether the next runtime widening slice should pay down bonus-lifecycle parity for guarded `19/19` object `2` or push the scheduler farther away from viewer-driven ticks first.
- Whether the current split between port work and original-runtime evidence should eventually become a more explicit top-level repo boundary.
