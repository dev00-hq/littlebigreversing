# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.
- Align implementation planning around the Zig 0.15.2 + SDL2 port direction, keep the offline life decoder plus audit path canonical, and use the verified `LM_DEFAULT`/`LM_END_SWITCH` real-asset hits to decide the next life-program source pass before any scene integration lands there.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- Zig-first LBA2 port implementation and typed-decoding preparation
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- Phase 2 typed asset decoding now has both an unwired offline `life_program.zig` decoder and a separate `audit-life-programs` path, but scene-surface life integration is still blocked: the canonical sample set reaches unsupported `LM_DEFAULT` and `LM_END_SWITCH` in real hero/object blobs, and the header inventory still contains six other named ids without live runtime cases.
- `zig build test` is still a real-asset gate that depends on the canonical extracted asset tree and the repo-local SDL2 layout.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
- Keep raw HQR entry indices and classic loader scene numbers explicit when working with `SCENE.HQR` targets.
- Use `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`, `port/src/game_data/scene/life_program.zig`, and `port/src/game_data/scene/life_audit.zig` as the boundary documents/code when touching life decoding.
- Use `zig build tool -- audit-life-programs` as the executable report for canonical real-asset blockers before proposing parser or CLI integration.
- Audit checked-in source specifically for the now-confirmed switch-family blockers `LM_DEFAULT` and `LM_END_SWITCH` before widening the supported decoder boundary.
- Keep raw `life_bytes` canonical and do not add `life_instructions` to scene parsing or CLI until unsupported real-asset cases are either proven or deliberately rejected by the product boundary.
