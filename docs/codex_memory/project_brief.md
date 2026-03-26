# Project Brief

## Purpose

Reverse-engineering and port-planning workspace for Twinsen's Little Big Adventure 2, with the canonical implementation path moving through the Zig `port/` workspace.

## Repo Map

- `docs/`: checked-in research, plans, subsystem memory packs, and reference memos
- `tools/`: repo-local utilities for memory, phase0, and MBN corpus work
- `reference/`: imported classic source, preserved tooling, and external source material
- `work/`: rebuildable generated outputs and extracted assets
- `port/`: canonical modern port implementation

## Canonical Sources

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/PORTING_REPORT.md`
- `docs/mbn_reference/README.md`
- `docs/phase0/README.md`
- `port/README.md`

## Invariants

- One canonical current-state codepath per subsystem.
- Codex memory lives only under `docs/codex_memory/`.
- Structured history uses only `codex-memory-v2` JSONL files.
- Fail fast instead of adding silent fallbacks or compatibility glue.

## Non-Goals

- cross-repo personal memory
- transcript archiving
- v1 memory compatibility
- canonical generated mirrors or SQLite indexes
