# Next Step: Unsupported Real-Asset Life Opcode Audit

## Summary

The strict offline decoder now exists at `port/src/game_data/scene/life_program.zig`, and it stays off the scene/parser/CLI surface by design. The next bounded step is to use that decoder to audit unsupported named life opcodes that still appear in canonical real asset blobs before any scene integration is considered.

This slice should:
- keep `life_program.zig` offline and leave the current scene parser, typed scene model, and CLI output unchanged
- inventory unsupported named `LM_*` ids that appear in selected canonical real-asset life blobs, starting with scene `2` hero `LM_DEFAULT`
- tighten the evidence/docs around any unsupported ids that appear in real data, including whether checked-in source proves them or still leaves them unimplemented
- add decoder-focused coverage that locks both successful structural decoding and intentional fail-fast rejection on real asset samples

## Key Changes

- Add a narrow offline audit path on top of `life_program.zig` rather than widening the scene surface.
  - Use `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` as the source boundary and the decoder as the executable structural oracle.
  - Report unsupported named opcode ids, byte offsets, and owning scene/object blob identity for selected canonical samples.
  - Keep the reporting offline: no `life_instructions` on `SceneProgramBlob`, no parser wiring, no CLI JSON/text surface changes unless the new path is explicitly a separate offline tool.

- Treat unsupported real-asset hits as evidence, not decode failures to paper over.
  - Keep rejecting `LM_NOP`, `LM_ENDIF`, `LM_REM`, `LM_DEFAULT`, `LM_END_SWITCH`, `LM_SPY`, `LM_DEBUG`, and `LM_DEBUG_OBJ` unless stronger checked-in evidence appears.
  - If a canonical blob reaches one of those ids, record that fact in docs/tests instead of adding a compatibility path or silently skipping it.
  - Keep `LM_MESSAGE_CHAPTER` out of scope; it remains commented dead code rather than live evidence.

- Refresh durable docs after implementation.
  - Update `docs/PROMPT.md` to the next slice only after the unsupported-opcode audit changes the boundary.
  - Update `docs/codex_memory/handoff.md` and append a task event.
  - Append a decision record if the audit confirms that scene integration must stay blocked on unsupported named ids in real assets.
  - Run `python3 tools/codex_memory.py validate` after the memory/doc updates.

## Test Plan

- Keep `zig build test` as the primary gate.
- Add decoder tests for:
  - real-asset success cases that fully decode through the current supported subset
  - real-asset fail-fast cases that intentionally hit unsupported named ids such as `LM_DEFAULT`
  - fixed-width operand decoding, null-terminated `LM_PLAY_ACF`, and nested `LF_*` + `DoTest()` parsing stay covered so the audit rides on a locked decoder
- Acceptance commands:
  - `zig build test`
  - `zig build tool -- inspect-scene 2 --json`

## Assumptions

- The next blocker is unsupported real-asset life opcodes, not missing structural coverage for the already-supported subset.
- The checked-in evidence memo is authoritative for supported layouts, but the live `GERELIFE.CPP` switch still wins if the memo and source drift.
- Raw `life_bytes` remain the canonical source of truth, and the offline decoder stays derived until unsupported real-asset ids are resolved.
- The local acceptance gate is still environment-dependent: `zig build test` and `inspect-scene` depend on the canonical extracted asset tree and the repo-local SDL2 layout on this machine.
