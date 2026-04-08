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
- Same-index triage now exposes both top-level answers: `86/86` is the highest-ranked compatible same-index pair above the guarded baseline, but it clears trivially with `fragment_count=0` and `grm_zone_count=0`; `187/187` is the first fragment-bearing compatible pair.

## Known Traps

- `docs/PROMPT.md` can lag; cross-check packs and history.
- `sidequest/` and `LM_TASKS/` are independent workstreams, not part of canonical memory pickup unless a prompt explicitly widens scope.
- The checked-in memory docs can lag the worktree; verify code and `git status`.
- Use native PowerShell for Windows verification and Python package installs: run `.\scripts\dev-shell.ps1` before Zig checks, and use `py -3 -m pip install -r requirements.txt` because the Bash-side `python3` lacks `pip` here.
- `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` are the daily loop, not the full gate.
- `zig build test` is not a substitute for explicit `zig build run` or `zig build tool` acceptance.
- Tool-only CLI/report paths need a real `zig build tool -- ...` run; test targets alone can miss parse/run/format drift.
- Memory history lookup now treats repo-relative `evidence_refs` as retrieval edges too; if a hit is missing, recheck the query path string.
- `scripts/verify-viewer.ps1` mixes expected-failure probes with success-path assertions; helpers that inspect nonzero exits must clear `$LASTEXITCODE`.
- On current PowerShell, expected-failure native stderr should be normalized line-by-line; `Out-String` over the whole captured collection can rewrap raw tool output as `NativeCommandError` noise.
- Interrupted `zig build run` launches can strand `port/zig-out/bin/lba2.exe`; clear the stale process before blaming the code.
- On guarded `19/19`, the exact containing-zone result for admitted `39/6` and the accepted south step is the empty set.
- Guarded `19/19` is still diagnostic-only: it lands on `raw_invalid_start` with `track_count=0`.
- Offline ranking is not runtime admission: `219` ranks first and `19` is `49/50`, but `inspect-room 219 219` still fails `InvalidFragmentZoneBounds`.
- Reuse the `219/219` blocker surfaces instead of inventing another blocker-only CLI.
- Same-index compatibility is not fragment-bearing evidence: `86/86` is the top compatible pair overall, but `187/187` is the first one that actually exercises fragment-zone matching.
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
