# Lessons

Curated durable lessons for future agents. This file is not a task log, issue
queue, or replacement for typed JSONL evidence.

### trap.current-focus-heading-is-schema

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, validation
Related tests: tools/test_codex_memory.py
Related files: tools/codex_memory.py, docs/codex_memory/current_focus.md

`docs/codex_memory/current_focus.md` section headings are part of the validated
memory contract. Do not rename required headings such as `## Blocked Items`
unless `tools/codex_memory.py` and its tests change in the same diff.

### decision.task-briefing-is-derived

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, generated, canonical
Related tests: tools/test_codex_memory.py
Related files: tools/codex_memory.py, docs/codex_memory/README.md

`docs/codex_memory/generated/task_briefing.md` is a reproducible task lens, not
canonical truth. The canonical startup path remains `project_brief.md`,
`current_focus.md`, selected subsystem packs, and typed history through
`tools/codex_memory.py context`.

### trap.lessons-are-not-logs

Status: active
Confidence: high
Last verified: 2026-04-29
Tags: codex-memory, lessons, hard-cut
Related tests: tools/test_codex_memory.py
Related files: docs/codex_memory/README.md, ISSUES.md

`lessons.md` is curated operational truth. Do not append to it just because work
finished; add a lesson only when it states reusable future behavior, a durable
trap, a decision, or an invariant that remains useful after the immediate issue
is closed.
