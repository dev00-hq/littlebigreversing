# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.
- Align implementation planning around the Zig 0.15.2 + SDL2 port direction, keep the new offline life decoder canonical, and use real-asset unsupported-opcode evidence to decide the next life-program source pass before any scene integration lands there.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- Zig-first LBA2 port implementation and typed-decoding preparation
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- Phase 2 typed asset decoding now has an unwired offline `life_program.zig` decoder for the live `GERELIFE.CPP` subset, but scene-surface life integration is still blocked: canonical scene data already hits unsupported `LM_DEFAULT`, and the header inventory still contains seven other named ids without live runtime cases.
- `zig build test` is still a real-asset gate that depends on the canonical extracted asset tree and the repo-local SDL2 layout.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
- Keep raw HQR entry indices and classic loader scene numbers explicit when working with `SCENE.HQR` targets.
- Use `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` plus the new `port/src/game_data/scene/life_program.zig` tests as the boundary documents when touching life decoding.
- Audit unsupported named life opcodes that appear in canonical real-asset blobs, starting with scene `2` hero `LM_DEFAULT`, before proposing parser or CLI integration.
- Keep raw `life_bytes` canonical and do not add `life_instructions` to scene parsing or CLI until unsupported real-asset cases are either proven or deliberately rejected by the product boundary.
