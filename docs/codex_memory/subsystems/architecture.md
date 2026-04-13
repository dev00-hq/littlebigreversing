# Architecture

## Purpose

Own repo-wide port direction and the canonical Codex memory workflow.

## Invariants

- The Zig port stays decode-first, Windows-first, and fail-fast.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo mistakes and confusion points.

## Current Parity Status

- `port/` stays canonical; runtime/viewer ownership is still split across the current `world_geometry` through `render` modules.
- `life_audit.zig` owns offline decoded-interior ranking, surfaced through `tools/cli.zig`.
- `inspect-room` failures distinguish unsupported life from fragment-zone bounds; `219/219` prints per-zone diagnostics before the raw error.
- Same-index triage still splits compatibility from fragment evidence: `86/86` is the top compatible pair above baseline, while `187/187` is the first fragment-bearing pair.

## Known Traps

- `docs/PROMPT.md` can lag; cross-check packs and history.
- `sidequest/` and `LM_TASKS/` are independent workstreams, not part of canonical memory pickup unless a prompt explicitly widens scope.
- The checked-in memory docs and bulky `work/` artifacts can lag this worktree; verify code, `git status`, and external asset paths.
- Parked nested Git metadata under `reference/discourse-downloader/.git.disabled/` and `reference/littlebigreversing/.git.disabled/` is portability noise, not canonical project state. Do not treat tracked `objects/`, `refs/`, `logs/`, `HEAD`, or `config` files there as dependencies that need to follow every machine.
- On this Windows checkout, `bash -lc 'git status'` under `/mnt/d/...` can over-report worktree dirtiness. For canonical repo-state checks, prefer native Windows Git from the PowerShell-hosted shell before deciding that large tracked trees need to be synchronized.
- A usable `.codex/worktrees/...` checkout can still have stale git metadata; if `git status` says `not a git repository`, confirm the filesystem tree directly before treating the checkout as missing or clean.
- In the PowerShell-hosted workflow, `bash -lc "..."` can still be mangled before Bash sees it. Prefer single-quoted Bash payloads in tool calls.
- Use native PowerShell for Windows verification and Python package installs: run Zig checks through `py -3 .\scripts\dev-shell.py`, and use `py -3 -m pip install ...` because the Bash-side `python3` lacks `pip`.
- `zig build test-fast` plus `scripts/verify_viewer.py --fast` are the daily loop, not the full gate.
- `zig build test` is not a substitute for explicit `zig build run` or `zig build tool` acceptance.
- Tool-only CLI/report paths need a real `zig build tool -- ...` run; test targets alone can miss parse/run/format drift.
- Memory history lookup treats repo-relative `evidence_refs` as retrieval edges too; if a hit is missing, recheck the query path string.
- `scripts/verify_viewer.py` is the canonical Windows acceptance gate; if a failure reproduces only there, debug the underlying tool or viewer output before adding another verifier path.
- `scripts/dev-shell.py` normalizes Windows environment keys case-insensitively because `vcvars` can emit `Path` instead of `PATH`.
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
