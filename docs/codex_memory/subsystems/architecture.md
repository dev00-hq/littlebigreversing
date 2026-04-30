# Architecture

## Purpose

Own repo direction, memory workflow, and the port/original-runtime boundary.

## Invariants

- `port/` stays the canonical implementation path.
- Original-runtime evidence stays explicit.
- `inspect-room-intelligence`, `cdb-agent`, and `ghb` are the canonical evidence layers.
- `project_brief.md` plus `current_focus.md` are the only always-loaded memory docs.
- Subsystem packs own current-state truth; typed JSONL files own durable history.
- `lessons.md` owns durable lessons; generated memory files are derived only.
- `ISSUES.md` is the companion trap log for recurring repo confusion.

## Current Parity Status

- `inspect-room-intelligence` is the canonical repo-local room/scene inspection surface.
- `cdb-agent` is the approved debugger/live-trace layer, and `ghb` is the approved Ghidra layer.
- Viewer input stops at intent submission; runtime owns mutable gameplay state and pending transition consumption.
- Original-runtime split: Tavern uses FRA, Scene11 uses debugger snapshots, transitions escalate to Frida plus `cdb` only as needed.
- Runtime seam widening is gated by `docs/promotion_packets/`: canonical behavior requires `live_positive` or `approved_exception`.
- Phase 5 starts from normal player affordances in known quest/world state; decoded room edges are only evidence.

## Known Traps

- Dump rankings and temporary seed-admission probes are evidence only, not runtime behavior.
- Original-runtime helpers are not default port pickup; use `life_scripts.md` and `ISSUES.md`.
- `context --path` needs `INDEX.md`; unmapped paths fail.
- For room-transition proof, do not generalize from a door/save/watcher until the exact seam is tested live.
- Do not let decoded candidates become runtime commits; promotion packets keep statuses distinct, and `canonical_runtime: true` requires `live_positive` or `approved_exception`.
- Do not model LBA2 as a linear room graph. It is quest-state over world, inventory, dialogue, access, actors, and flags; decoded transitions need state proof before they imply gameplay.
- `reference/twinsuniverse` is mixed LBA1/LBA2 reference only; runtime claims still need repo-owned proof.
- Do not treat `collision_observer.py` as a blocked/moved oracle. Step outcome is authoritative.
- Room `36/36`: visible page turns are renderer pagination; keep fresh entry and loaded reconstruction separate.
- Viewer default: isometric room first; old top-down grid only behind `V`.

## Reverse / Porting Slice Checklist

- Name proof surface before coding: player affordance, quest/world state, room pair, zone, trigger path, mode, and manual steps.
- Keep decode, runtime, and gameplay semantics separate until classic execution proves they collapse.
- Do not rename raw fields to `final_*` or treat decoded payloads as resolved runtime state without seam-level evidence.
- Start with asset/decode inspection, pin the port seam with tests, then probe that exact seam live.
- Scope claims/code to the proved seam; do not generalize one door, zone, or save lane to a room/cube rule.
- For live play, capture machine evidence and visual evidence.
- Escalate by need: watcher for coarse behavior, Frida for sequencing, `cdb-agent`/`cdb` for writes.
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
