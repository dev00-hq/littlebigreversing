# Architecture

## Purpose

Own repo direction, memory workflow, and the Zig port/original-runtime boundary.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence stays explicit.
- `inspect-room-intelligence`, `cdb-agent`, and `ghb` are the canonical evidence layers.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `lessons.md` owns curated durable operational lessons; generated memory files are derived context only.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- `inspect-room-intelligence` is the canonical repo-local room/scene inspection surface.
- `cdb-agent` is the approved debugger/live-trace layer, and `ghb` is the approved Ghidra layer.
- Viewer input stops at intent submission; runtime owns mutable gameplay state and pending transition consumption.
- Original-runtime split: Tavern uses FRA, Scene11 uses debugger snapshots, transitions escalate to Frida plus `cdb` only as needed.
- Runtime/gameplay seam widening is gated by `docs/promotion_packets/`: decoded seams can stay as candidates, but canonical runtime behavior requires `live_positive` or `approved_exception`.

## Known Traps

- Dump-driven rankings and temporary seed-admission probes are evidence only, not supported runtime behavior.
- Original-runtime helpers are not default port pickup; use `life_scripts.md` and `ISSUES.md`.
- `context --path` needs `INDEX.md`; unmapped paths fail.
- For room-transition proof, do not generalize from a door, save lane, or watcher until the exact seam is pinned in tests and live evidence.
- Do not let decoded candidates become runtime commits; promotion packets keep statuses distinct, and `canonical_runtime: true` requires `live_positive` or `approved_exception`.
- Do not treat `collision_observer.py` as a blocked/moved oracle. Step outcome is authoritative.
- Room `36/36`: visible page turns are renderer pagination, not durable dialog-id transitions; keep fresh entry and loaded reconstruction separate.
- Viewer default: isometric room first; old top-down grid only behind `V`; debug state belongs in the tabbed right sidebar.

## Reverse / Porting Slice Checklist

- Name the proof surface before coding: room pair, zone index, trigger path, player mode, and manual steps.
- Keep decode semantics, runtime semantics, and final gameplay semantics separate until the classic execution path proves they collapse.
- Do not rename raw fields to `final_*` or treat decoded payloads as resolved runtime state without seam-level evidence.
- Start with asset or decode inspection, then pin the matching port seam with tests, then use original-runtime probes on that exact seam.
- Scope claims and code to the exact seam that is proved; do not generalize from one observed door, zone, or save lane to a room-wide or cube-wide rule.
- For live play, capture machine evidence and visual evidence.
- Escalate instrumentation by need: watcher for coarse behavior, Frida for sequencing, `cdb-agent` or `cdb` for exact write ownership.
- If hot hooks crash, back off and combine safer probes instead.

## Canonical Entry Points

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/lessons.md`
- `docs/codex_memory/subsystems/intelligence.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `port/README.md`
- `docs/promotion_packets/README.md`
- `tools/validate_promotion_packets.py`

## Important Files

- `AGENTS.md`
- `ISSUES.md`
- `tools/life_trace/heading_inject.py`
- `tools/life_trace/waypoint_step_probe.py`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`
- `py -3 .\tools\validate_promotion_packets.py`

## Open Unknowns

- How far the new next-page-cursor helper should be promoted beyond the already-proved two-page seams before building a full generic dialog renderer.
