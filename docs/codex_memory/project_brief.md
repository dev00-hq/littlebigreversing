# Project Brief

## Purpose

Reverse-engineering and port-planning workspace for Twinsen's Little Big Adventure 2. The canonical implementation path moves through the Zig `port/` workspace, while original-runtime evidence tooling remains a separate supporting track.

LBA2 gameplay is a story-gated, hub-based action-adventure: world state, inventory, dialogue, location access, actor state, and quest flags unlock affordances and change behavior. Do not model the campaign as a linear room graph.

## Repo Map

- `docs/`: checked-in research, plans, subsystem memory packs, and reference memos
- `tools/`: repo-local utilities for memory, phase0, and MBN corpus work
- `tools/life_trace/`: original-runtime evidence, debug-control probes, and save-driven automation helpers
- `reference/`: imported classic source, preserved tooling, and external source material
- `work/`: rebuildable generated outputs and extracted assets
- `port/`: canonical modern port implementation

## Canonical Sources

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/current_focus.md`
- `port/README.md`

## Invariants

- One canonical current-state codepath per subsystem.
- One canonical investigative stack for narrowing runtime gaps: `inspect-room-intelligence`, `cdb-agent`, and `ghb`.
- Repo-owned generated metadata artifacts beat legacy external text exports on canonical tool paths.
- Codex memory lives only under `docs/codex_memory/`.
- Structured history uses only `codex-memory-v2` JSONL files.
- Default canonical memory pickup excludes `sidequest/` and `LM_TASKS/`.
- Fail fast instead of adding silent fallbacks or compatibility glue.

## Non-Goals

- cross-repo personal memory
- transcript archiving
- v1 memory compatibility
- task-local sidequest or LM trackers as canonical memory
- canonical generated mirrors or SQLite indexes
