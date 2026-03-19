# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.
- Align implementation planning around the Zig 0.15.2 + SDL2 port direction and extend the Phase 2 decoder into scene-local track-program disassembly as the next bounded step.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- Zig-first LBA2 port implementation and typed-decoding preparation
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- Phase 2 typed asset decoding now preserves raw hero/object track blobs and life-script blobs, but track programs are still opaque byte arrays with no typed instruction surface yet.
- `zig build test` is still a real-asset gate that depends on the canonical extracted asset tree and the repo-local SDL2 layout.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
- Keep raw HQR entry indices and classic loader scene numbers explicit when working with `SCENE.HQR` targets.
- Add a narrow scene-local track decoder/disassembler before attempting life-script interpretation or gameplay systems.
