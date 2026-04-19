# Architecture

## Purpose

Own repo direction, Codex memory workflow, and the boundary between the Zig port and original-runtime evidence.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence stays explicit.
- `inspect-room-intelligence`, `cdb-agent`, and `ghb` are the canonical evidence layers.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- The Zig port remains decode-first and fail-fast.
- `inspect-room-intelligence` is the canonical repo-local room/scene inspection surface.
- `cdb-agent` is the approved debugger/live-trace layer, and `ghb` is the approved Ghidra layer.
- Viewer input stops at intent submission; runtime owns mutable gameplay state and pending transition consumption.
- The original-runtime split is stable: Tavern uses FRA, Scene11 uses debugger snapshots, room-transition seams escalate to Frida plus `cdb` only as needed, and the committed debug-control lane uses `debug_compass.py`, `heading_inject.py`, and `waypoint_step_probe.py`.

## Known Traps

- `sidequest/` and `LM_TASKS/` are independent workstreams unless a prompt explicitly widens scope.
- Dump-driven rankings and temporary seed-admission probes are evidence only, not supported runtime behavior.
- `work/` artifacts can lag the real worktree; verify code, `git status`, and asset paths before trusting generated outputs.
- `scripts/verify_viewer.py` is the canonical Windows acceptance gate for the port path.
- Original-runtime evidence helpers are not default port pickup; use `life_scripts.md` and `ISSUES.md`.
- For room-transition proof, do not generalize from a door, save lane, or watcher until the exact seam is pinned in tests and live evidence.
- Do not treat `collision_observer.py` as a blocked/moved oracle. Step outcome is authoritative; collision observation only explains persistent pin versus transient pin.
- Do not promote raw scene-object placements into floor-truth spawn positions. On guarded `19/19`, reward spawning resolves through the nearest admitted standable cell.
- The deferred wall-mapping / wall-walk spike is not canonical repo state. It lives on a side branch and should not re-enter `main` without a fresh bounded justification.

## Reverse / Porting Slice Checklist

- Name the proof surface before coding: room pair, zone index, trigger path, player mode, and any manual steps needed.
- Keep decode semantics, runtime semantics, and final gameplay semantics separate until the classic execution path proves they collapse.
- Do not rename raw fields to `final_*` or treat decoded payloads as resolved runtime state without seam-level evidence.
- Start with asset or decode inspection, then pin the matching port seam with tests, then use original-runtime probes on that exact seam.
- Scope claims and code to the exact seam that is proved; do not generalize from one observed door, zone, or save lane to a room-wide or cube-wide rule.
- When live play is involved, capture both machine evidence and visual evidence; screenshots are part of the proof, not optional garnish.
- Escalate instrumentation by need: watcher for coarse behavior, Frida for sequencing, `cdb-agent` or `cdb` for exact write ownership.
- If hot hooks crash, back off and combine safer probes instead.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/intelligence.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `port/README.md`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `tools/life_trace/heading_inject.py`
- `tools/life_trace/waypoint_step_probe.py`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`

## Open Unknowns

- Whether the next runtime widening slice should pay down `19/19` reward parity or deepen the Sendell/story scheduler path first.
