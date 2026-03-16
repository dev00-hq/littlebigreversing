# Handoff

## Current State

The repo is currently stronger on research assets and analysis tooling than on executable port code. The durable center of gravity is `docs/`, with generated state already living under `work/` for the MBN workbench.

## Verified Facts

- `tools/mbn_workbench.py` reads checked-in corpus data and writes generated SQLite state under `work/mbn_workbench/`.
- `docs/mbn_reference/README.md` explicitly names one canonical corpus snapshot.
- `port/README.md` says `port/` is reserved for the modern implementation and should remain separate from `docs/`, `reference/`, and `work/`.

## Open Risks

- The repo has many pre-existing modified files, especially in corpus/reference areas; avoid reverting or normalizing unrelated changes.
- Without regular updates, Codex state can drift back into chat-only context and stop being durable.
- If the port implementation begins, `project_brief.md` and `current_focus.md` will need to be updated so memory reflects real code ownership rather than only research structure.

## Next 3 Steps

1. Use `python3 tools/codex_memory.py context` at the start of the next substantive task.
2. Record the next durable implementation or architecture decision in `decision_log.jsonl`.
3. When `port/` gains real code, update the memory docs to reflect the new execution entrypoints and tests.
