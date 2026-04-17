# Memory System Brief

## Purpose

This repo now uses the topology-first `codex-memory-v2` model under `docs/codex_memory/`.

The goal is to keep the always-loaded layer small, move durable current-state truth into subsystem packs, and keep structured history typed and narrow.

## Current Layout

- always loaded:
  - `docs/codex_memory/project_brief.md`
  - `docs/codex_memory/current_focus.md`
- on demand:
  - `docs/codex_memory/subsystems/*.md`
- structured history:
  - `policies.jsonl`
  - `subsystem_facts.jsonl`
  - `investigations.jsonl`
  - `compat_events.jsonl`
  - `task_events.jsonl`
- tooling:
  - `tools/codex_memory.py`

## Key Rules

- `handoff.md`, `decision_log.jsonl`, `task_log.jsonl`, and `work/codex_memory/` are retired.
- The only supported schema is `codex-memory-v2`.
- Subsystem packs are current-state briefings, not append-only changelogs.
- Typed JSONL files are the only durable history layer.
- When a typed history file already exists in `HEAD`, validation treats it as append-only. Durable fixes are new appended records, not in-place rewrites of old timestamped rows.
- Validation is fail-fast on missing sections, oversized docs, bad schema values, bad repo-relative paths, and ambiguous path mappings.

## CLI Surface

From native PowerShell on the canonical Windows host:

```powershell
py -3 .\tools\codex_memory.py validate
py -3 .\tools\codex_memory.py context
py -3 .\tools\codex_memory.py context --path port/src/game_data/background/parser.zig --include-history 3
py -3 .\tools\codex_memory.py add-policy ...
py -3 .\tools\codex_memory.py add-fact ...
py -3 .\tools\codex_memory.py add-investigation ...
py -3 .\tools\codex_memory.py add-compat-event ...
py -3 .\tools\codex_memory.py add-task-event ...
```

From Bash:

```bash
python3 tools/codex_memory.py validate
python3 tools/codex_memory.py context
python3 tools/codex_memory.py context --path port/src/game_data/background/parser.zig --include-history 3
python3 tools/codex_memory.py add-policy ...
python3 tools/codex_memory.py add-fact ...
python3 tools/codex_memory.py add-investigation ...
python3 tools/codex_memory.py add-compat-event ...
python3 tools/codex_memory.py add-task-event ...
```

## Operator Workflow

1. Read `project_brief.md` and `current_focus.md`.
2. Load only the subsystem packs needed for the task.
3. Use typed history only when current state or a blocker needs it.
4. Append typed records when durable conclusions or task-state updates matter.
5. Keep `current_focus.md` small and update it only when active repo status changes.
