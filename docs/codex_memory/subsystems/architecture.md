# Architecture

## Purpose

Own repo-wide port direction and the canonical Codex memory workflow.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `port/` stays canonical; runtime/viewer ownership remains split across `world_geometry`, `room_state`, `session`, `world_query`, `locomotion`, `viewer_shell`, `main`, and `render`.
- `life_audit.zig` owns offline ranking of decoded interior candidates, and `tools/cli.zig` exposes `rank-decoded-interior-candidates` plus `triage-same-index-decoded-interior-candidates`.
- `inspect-room` failures now distinguish unsupported life from fragment-zone bounds; `219/219` prints per-zone `invalid_fragment_zone_bounds` diagnostics before the raw error.
- Same-index triage is now explicit: `86/86` is the highest-ranked compatible same-index pair above the guarded baseline, but it clears trivially with `fragment_count=0` and `grm_zone_count=0`; `187/187` is the first fragment-bearing compatible pair.

## Known Traps

- `docs/PROMPT.md` can lag; cross-check packs and history.
- `sidequest/` and `LM_TASKS/` are independent workstreams, not part of canonical memory pickup unless a prompt explicitly widens scope.
- The checked-in memory docs can lag the worktree; verify code and `git status`.
- Canonical Windows Zig checks should run from native PowerShell after `.\scripts\dev-shell.ps1`.
- `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` are the daily loop, not the full gate.
- `zig build test` is not a substitute for explicit `zig build run` or `zig build tool` acceptance.
- Tool-only CLI/report paths need a real `zig build tool -- ...` run; test targets alone can miss parse/run/format drift.
- `scripts/verify-viewer.ps1` mixes expected-failure probes with success-path assertions; helpers that inspect nonzero exits must clear `$LASTEXITCODE`.
- Interrupted `zig build run` launches can strand `port/zig-out/bin/lba2.exe`; clear the stale process before blaming the code.
- On guarded `19/19`, the exact containing-zone result for admitted `39/6` and the accepted south step is the empty set.
- Do not confuse the guarded `19/19` diagnostic baseline with a playable-path candidate; it still lands on `raw_invalid_start` with `track_count=0`.
- Do not confuse the offline ranking winner with runtime admission. `219` ranks first and `19` ranks `49/50`, but `inspect-room 219 219` still fails `InvalidFragmentZoneBounds`.
- Reuse the `219/219` blocker surfaces instead of inventing another blocker-only CLI.
- Do not confuse the highest-ranked compatible same-index pair with fragment-bearing evidence. `86/86` outranks the baseline under the checked-in fragment-zone rules, but it does so with zero fragments and zero GRM zones; `187/187` is the first compatible pair that actually exercises fragment-zone matching.
- Guarded negative `inspect-room` and viewer-startup loads keep `ViewerUnsupportedSceneLife` public, but precede it with the first blocking `event=room_load_rejected ... unsupported_life_*` line only.

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
