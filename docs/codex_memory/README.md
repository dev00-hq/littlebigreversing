# Codex Memory

This directory is the canonical repo-scoped memory for Codex work in this repository.

## Workflow

1. Read `project_brief.md`, `current_focus.md`, and `handoff.md` before major work, or run `python3 tools/codex_memory.py context`.
2. Record durable conclusions in `decision_log.jsonl`.
3. Record meaningful task checkpoints in `task_log.jsonl`.
4. Keep `handoff.md` current enough that a new Codex session can resume work without rereading the full repo.
5. Rebuild generated retrieval state with `python3 tools/codex_memory.py build-index`.

## Commands

```bash
python3 tools/codex_memory.py validate
python3 tools/codex_memory.py context
python3 tools/codex_memory.py add-decision \
  --topic codex-memory \
  --status accepted \
  --statement "Keep canonical memory under docs/codex_memory and derived state under work/codex_memory." \
  --rationale "Matches the repo's existing docs/work split and keeps memory rebuildable." \
  --evidence-ref docs/PORTING_REPORT.md \
  --affected-path docs/codex_memory \
  --affected-path tools/codex_memory.py
python3 tools/codex_memory.py add-task-event \
  --task-id codex-memory-bootstrap \
  --title "Bootstrap repo memory system" \
  --status completed \
  --summary "Created the initial memory docs, CLI, and validation flow." \
  --next-action "Use the memory workflow on the next substantive task."
python3 tools/codex_memory.py build-index
python3 tools/codex_memory.py refresh-handoff
```

## Write Rules

- `project_brief.md`, `current_focus.md`, and `handoff.md` are compact Markdown intended for humans and Codex.
- `decision_log.jsonl` and `task_log.jsonl` are append-only structured records.
- Generated state under `work/codex_memory/` is never canonical.
- Schema/version mismatches should fail fast instead of falling back.
- This system is repo-scoped only. Do not store cross-repo personal memory or chat transcripts here.
