# Architecture

## Purpose

Own repo direction, memory workflow, and the Zig port/original-runtime boundary.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence stays explicit.
- `inspect-room-intelligence`, `cdb-agent`, and `ghb` are the canonical evidence layers.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable structured history.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- `inspect-room-intelligence` is the canonical repo-local room/scene inspection surface.
- `cdb-agent` is the approved debugger/live-trace layer, and `ghb` is the approved Ghidra layer.
- Viewer input stops at intent submission; runtime owns mutable gameplay state and pending transition consumption.
- Original-runtime split: Tavern uses FRA, Scene11 uses debugger snapshots, transitions escalate to Frida plus `cdb` only as needed, and debug control uses `debug_compass.py`, `heading_inject.py`, `waypoint_step_probe.py`.

## Known Traps

- Dump-driven rankings and temporary seed-admission probes are evidence only, not supported runtime behavior.
- Original-runtime evidence helpers are not default port pickup; use `life_scripts.md` and `ISSUES.md`.
- `context --path` needs `INDEX.md`; unmapped paths fail.
- For room-transition proof, do not generalize from a door, save lane, or watcher until the exact seam is pinned in tests and live evidence.
- Do not treat `collision_observer.py` as a blocked/moved oracle. Step outcome is authoritative.
- On room `36/36`, visible page turns are renderer pagination inside one decoded text record, not durable dialog-id transitions.
- The bounded next-page-cursor helper is reusable for proved two-page seams, not a full generic dialog renderer.
- On room `36/36`, keep fresh entry (`applyRoomEntryState`) and loaded reconstruction (`reconstructLoadedRoomState`) separate.
- Viewer debug state and controls belong in the tabbed right sidebar; `C` switches tabs, `+`/`-` zoom, and `0` resets fit.

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

- How far the new next-page-cursor helper should be promoted beyond the already-proved two-page seams before building a full generic dialog renderer.
