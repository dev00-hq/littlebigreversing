# Current Focus

## Current Priorities

- Use this Codex memory system as the default handoff and state-externalization path for future repo work.
- Preserve the repo's existing split between canonical checked-in knowledge and rebuildable generated state.
- Keep reverse-engineering findings, task decisions, and next steps cheap for a new Codex session to reload.

## Active Streams

- MBN corpus analysis and evidence workbench maintenance
- High-level LBA2 port planning and subsystem selection
- Codex memory hygiene for long-horizon repo work

## Blocked Items

- `port/` is still only a placeholder; there is no active gameplay/runtime implementation yet.
- The worktree is intentionally dirty in several corpus/reference areas, so new work must avoid reverting unrelated changes.

## Next Actions

- Run `python3 tools/codex_memory.py validate` before and after substantive memory updates.
- Keep `handoff.md` aligned with the latest meaningful repo state.
- Record durable architecture or workflow conclusions in `decision_log.jsonl` instead of leaving them only in chat context.
