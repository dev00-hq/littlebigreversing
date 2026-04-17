# Codex Memory

## Workflow

1. Read `project_brief.md` and `current_focus.md` at task start.
2. Load only the subsystem packs needed for the task, or use `python3 tools/codex_memory.py context --path ...`.
3. Use typed JSONL history only when current state or a blocked question needs durable history.
4. Update `current_focus.md` only when active repo status changes, and append typed records for durable conclusions, blockers, or task state.
5. If a new recurring repo trap is discovered, update `ISSUES.md` and keep the architecture subsystem pack consistent with it.

## Commands

```bash
python3 tools/codex_memory.py validate
python3 tools/codex_memory.py context
python3 tools/codex_memory.py context --path port/src/game_data/background/parser.zig --include-history 3
python3 tools/codex_memory.py context --path port/src/game_data/background/parser.zig --include-history 3 --history-mode relevant
python3 tools/codex_memory.py context --subsystem architecture --include-history 10 --include-excluded-history
python3 tools/codex_memory.py add-policy --topic memory-workflow --status accepted --statement "Use only the v2 memory tree." --rationale "The repo cut over in place." --evidence-ref docs/codex_memory/README.md --affected-path docs/codex_memory/README.md
python3 tools/codex_memory.py add-fact --subsystem life_scripts --status current --fact "Only LM_DEFAULT and LM_END_SWITCH block current real-asset life decoding." --rationale "The full-archive audit found no other unsupported life ids in the current asset tree." --evidence-ref docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md --affected-path docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md
python3 tools/codex_memory.py add-investigation --subsystem life_scripts --status blocked --question "How should LM_DEFAULT and LM_END_SWITCH be handled?" --current-best-answer "Keep them outside the supported decoder until stronger checked-in evidence appears or the product boundary rejects them." --confidence high --next-probe "Revisit only if source evidence or canonical assets change." --evidence-ref docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md --affected-path port/src/game_data/scene/life_program.zig
python3 tools/codex_memory.py add-compat-event --subsystem architecture --status removed --title "Retire v1 memory tree" --summary "Removed handoff.md, mixed logs, and generated mirrors from the canonical design." --evidence-ref tools/codex_memory.py --affected-path tools/codex_memory.py
python3 tools/codex_memory.py add-task-event --stream viewer-prep --status blocked --summary "Scene-surface life integration remains blocked on switch-family evidence." --next-action "Keep life work on explicit evidence probes or deliberate rejection only." --evidence-ref docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md --affected-path port/src/game_data/scene/life_program.zig
```

## Write Rules

- `project_brief.md` and `current_focus.md` are the only always-loaded Markdown files.
- Subsystem packs own durable current-state truth for their subsystem; do not turn them into append-only changelogs.
- Typed JSONL files are the only structured history layer.
- When a JSONL history file already exists in `HEAD`, validation treats it as append-only. Restore old rows and append new ones; do not rewrite timestamped history in place.
- Default canonical memory pickup excludes `sidequest/` and `LM_TASKS/` until those streams are explicitly promoted into the checked-in path.
- `--include-history` keeps chronological `## Recent History` by default; `--history-mode relevant` is the opt-in ranked alternative for path/subsystem queries.
- `python3 tools/codex_memory.py context --include-excluded-history` is the opt-in escape hatch when you explicitly need excluded durable history.
- `ISSUES.md` is a companion trap log, not a replacement for packs or typed history; keep it linked through the architecture subsystem.
- All paths in JSONL records must be repo-relative and schema-valid.
- Do not restore `handoff.md`, `decision_log.jsonl`, `task_log.jsonl`, or `work/codex_memory/`.

## Budgets

- `project_brief.md`: `<= 2 KB`
- `current_focus.md`: `<= 3 KB`
- each subsystem pack: `<= 4 KB`
- summary-like JSONL fields: `<= 240` chars
- `rationale` and `current_best_answer`: `<= 600` chars
