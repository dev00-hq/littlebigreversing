# Handoff

## Current State

The repo is still stronger on research assets and analysis tooling than on executable port code. The durable center of gravity remains `docs/`, and the canonical implementation roadmap is now the Zig-first plan in `docs/LBA2_ZIG_PORT_PLAN.md`.

## Verified Facts

- `tools/mbn_workbench.py` reads checked-in corpus data and writes generated SQLite state under `work/mbn_workbench/`.
- `docs/mbn_reference/README.md` explicitly names one canonical corpus snapshot.
- `port/README.md` now defines the first implementation package as `Foundation + asset CLI` for the Zig 0.15.2 + SDL2 port.
- `docs/PORTING_REPORT.md` has been trimmed to evidence, tooling, risks, and workspace-state coverage, while `docs/LBA2_ZIG_PORT_PLAN.md` owns execution planning.

## Open Risks

- The repo has many pre-existing modified files, especially in corpus/reference areas; avoid reverting or normalizing unrelated changes.
- Without regular updates, Codex state can drift back into chat-only context and stop being durable.
- `port/` still lacks a checked-in canonical Zig workspace, so future sessions need to avoid treating the untracked placeholder as durable product state.

## Next 3 Steps

1. Use `python3 tools/codex_memory.py context` at the start of the next substantive task.
2. Prepare the first implementation spec for `Foundation + asset CLI`.
3. When `port/` gains the real Zig workspace, update memory to reflect the actual entrypoints, commands, and tests.
