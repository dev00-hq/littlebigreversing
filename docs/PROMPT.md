# Next Step: Unsupported Switch-Family Life Opcode Source Pass

## Summary

The repo now has a separate offline audit path at `zig build tool -- audit-life-programs [--json]` on top of `port/src/game_data/scene/life_program.zig`. That audit keeps the scene/parser/CLI surface unchanged and proves that unsupported switch-family ids are present in canonical real assets:

- scene `2` hero hits `LM_DEFAULT` at byte offset `170`
- scene `5` hero hits `LM_END_SWITCH` at byte offset `46`
- scene `44` hero hits `LM_END_SWITCH` at byte offset `713`
- scene `44` objects `2` and `3` hit `LM_DEFAULT` at offsets `274` and `43`

The next bounded step is to decide whether checked-in source can prove structural handling for `LM_DEFAULT` and `LM_END_SWITCH`, or whether those ids should remain explicitly outside the supported decoder boundary.

This slice should:
- keep `life_program.zig`, `life_audit.zig`, the scene parser/model, and `inspect-scene` unchanged unless stronger source-backed evidence is found
- focus only on the unsupported switch-family ids that now have confirmed real-asset hits: `LM_DEFAULT` and `LM_END_SWITCH`
- tighten docs/tests around whether those ids are structurally provable from checked-in evidence or must remain deliberate blockers
- preserve raw `life_bytes` as the canonical scene surface either way

## Key Changes

- Audit the checked-in classic source specifically for switch-family handling.
  - Re-check `reference/lba2-classic/SOURCES/GERELIFE.CPP`, related helpers, and any nearby checked-in evidence for structural handling of `LM_DEFAULT` and `LM_END_SWITCH`.
  - If the checked-in source still does not prove live handling, document that explicitly instead of inferring operand widths or skip behavior from names alone.
  - If stronger checked-in evidence does prove safe structural layouts, call out exactly why the previous boundary was insufficient and keep the new path fail-fast outside the proven subset.

- Keep the audit tooling honest.
  - Do not widen `inspect-scene`, `SceneProgramBlob`, or parser-owned scene state.
  - Keep `audit-life-programs` as the separate offline reporting path for unsupported real-asset hits.
  - Do not add compatibility skipping for unsupported ids just to continue decoding later bytes.

- Refresh durable docs after the source pass lands.
  - Update `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` with the source-backed conclusion for `LM_DEFAULT` and `LM_END_SWITCH`.
  - Update `docs/PROMPT.md` again only after that conclusion changes the next boundary.
  - Update `docs/codex_memory/handoff.md`, append a task event, and append a decision record if the supported/unsupported boundary changes or is reaffirmed.
  - Run `python3 tools/codex_memory.py validate` after the memory/doc updates.

## Test Plan

- Keep `zig build test` as the primary gate.
- Keep `zig build tool -- audit-life-programs --json` as the executable evidence report for canonical real assets.
- Add coverage only if the checked-in source pass changes the supported boundary; otherwise keep the current fail-fast tests and audit regressions intact.
- Acceptance commands:
  - `zig build test`
  - `zig build tool -- audit-life-programs`
  - `zig build tool -- inspect-scene 2 --json`

## Assumptions

- The supported subset of `life_program.zig` is no longer the blocker; the blocker is unresolved switch-family ids that are now proven to occur in canonical real assets.
- Checked-in classic source still outranks header names and previous summaries if they drift.
- Raw `life_bytes` remain the canonical source of truth until unsupported real-asset switch-family ids are either structurally proven or deliberately kept outside the product boundary.
- The local acceptance gate is still environment-dependent: `zig build test`, `audit-life-programs`, and `inspect-scene` depend on the canonical extracted asset tree and the repo-local SDL2 layout on this machine.
