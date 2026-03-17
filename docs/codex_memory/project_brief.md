# Project Brief

## Purpose

This repository is a reverse-engineering and port-planning workspace for Twinsen's Little Big Adventure 2. It currently centers on source collection, corpus analysis, tooling, and port-specification work rather than a runnable modern port.

## Repo Map

- `docs/`: reverse-engineering reports, reference corpora, and canonical checked-in knowledge
- `tools/`: local Python utilities for derived research state and query workflows
- `reference/`: imported upstream material, legacy tooling, and preserved external sources
- `work/`: generated outputs, extracted payloads, and rebuildable machine state
- `port/`: reserved location for the future canonical port implementation

## Canonical Sources

- `docs/PORTING_REPORT.md` is the main high-level porting assessment.
- `docs/LBA2_ZIG_PORT_PLAN.md` is the canonical implementation roadmap and work-package boundary.
- `docs/mbn_reference/README.md` names the canonical MBN corpus snapshot.
- `tools/mbn_workbench.py` is the existing pattern for "checked-in source material + generated SQLite state".
- `port/README.md` states that `port/` is the destination for the future modern implementation.

## Invariants

- Optimize for one canonical current-state implementation, not compatibility with historical local states.
- Durable Codex memory lives in `docs/codex_memory/`; generated retrieval state lives in `work/codex_memory/`.
- Derived machine state must be rebuildable from checked-in memory.
- Prefer fail-fast diagnostics over silent fallback behavior.

## Non-Goals

- Cross-repo personal memory
- Chat transcript archiving
- Automatic migration of older memory schemas
- Blending Codex memory into the MBN corpus database or other unrelated research stores
