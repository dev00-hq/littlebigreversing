# Decode Scene-Local Track Programs

## Summary

Implement one bounded Phase 2 slice: decode preserved hero/object track program blobs into a typed instruction stream and expose that disassembly through `inspect-scene`.

This task stops at structural track-program decoding. It does **not** include life-script interpretation, gameplay semantics for track opcodes, or any changes to the existing scene-global `tracks` point table.

## Implementation Changes

### Track decoder boundary

- Keep the preserved raw program bytes as the canonical source of truth.
- Add a track-program decoder in the scene module that consumes a `SceneProgramBlob` and produces a typed instruction list for hero/object track programs only.
- Make the decoder boundary explicit:
  - scene-global `tracks` point coordinates remain a separate concept
  - life-script blobs remain opaque raw bytes in this slice
  - decoded track instructions are derived from preserved raw bytes, not a replacement for them
- Fail fast on truncated operands, trailing partial instructions, or unsupported opcode layouts instead of guessing.

### CLI and JSON surface

- Keep text-mode `inspect-scene` compact:
  - keep the current hero/object byte-length summary lines
  - add a compact decoded-track summary for hero/object programs
  - do not dump life-script bytes in text mode
- Expand `inspect-scene --json` to expose decoded track instructions beside the preserved raw bytes:
  - `hero_start.track_instructions`
  - `objects[].track_instructions`
- Keep the existing JSON shape otherwise stable: preserved raw bytes stay present, zones stay unchanged, `classic_loader_scene_number` stays explicit, and scene-global `tracks`/patches stay as they are.

### Docs and durable state

- Refresh `docs/PROMPT.md` so it no longer claims raw blob preservation is the next action.
- Update `docs/codex_memory/handoff.md` and append a task event after the slice lands.
- Append a decision record only if the decoded-track boundary is being treated as a durable model decision.
- Run `python3 tools/codex_memory.py validate` after the memory/doc updates.
- Do not touch `ISSUES.md` unless implementation uncovers a new reusable trap beyond the current scene-numbering / non-hermetic-test warnings.

## Test Plan

- Keep `zig build test` as the primary gate.
- Add synthetic decoder coverage for:
  - one short hero track blob with multiple instructions
  - one object track blob with a different opcode mix
  - explicit truncation inside an instruction operand
  - explicit failure on unsupported opcode layout if the decoder does not yet support the full corpus
- Add JSON-shape tests that pin `track_instructions` for hero/object output while keeping the existing raw-byte arrays present.
- Add asset-backed regression assertions for representative preserved track blobs from scenes `2`, `5`, and `44`.
- For the asset-backed checks in this slice, assert decoder stability at the structural level:
  - the instruction stream covers the full raw track blob without gaps
  - decoded instruction counts stay fixed for the chosen sample blobs
  - raw life blobs remain untouched and opaque

## Assumptions and Defaults

- Raw preservation is already complete; the next step is a narrow track disassembler.
- JSON should keep both preserved raw bytes and decoded track instructions.
- Life-script bytes remain preserved but uninterpreted in this slice.
- No compatibility layer is needed; use one canonical preserved-bytes-plus-decoded-track path.
- `zig build test` remains a real-asset, non-hermetic gate that depends on the repo-local SDL2 layout and canonical extracted asset tree.
