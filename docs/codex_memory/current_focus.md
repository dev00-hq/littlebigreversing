# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.
- Align implementation planning around the Zig 0.15.2 + SDL2 port direction and execute the typed zone-semantics slice as the next bounded Phase 2 step.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- Zig-first LBA2 port implementation and typed-decoding preparation
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- Phase 2 typed asset decoding has started with `SCENE.HQR` metadata parsing, but typed decoding for scene scripts, actor script blobs, and related cross-asset links is still open.
- The worktree currently has a small number of active user edits; new work must still avoid reverting unrelated changes.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
- Extend the new `SCENE.HQR` decoder from typed scene metadata into the next bounded Phase 2 slice instead of skipping ahead to gameplay systems.
