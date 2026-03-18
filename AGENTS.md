# Hard-Cut Product Policy

- This application currently has no external installed user base; optimize for one canonical current-state implementation, not compatibility with historical local states.
- Do not preserve or introduce compatibility bridges, migration shims, fallback paths, compact adapters, or dual behavior for old local states unless the user explicitly asks for that support.
- Prefer:
  - one canonical current-state codepath
  - fail-fast diagnostics
  - explicit recovery steps

  over:
  - automatic migration
  - compatibility glue
  - silent fallbacks
  - “temporary” second paths
- If temporary migration or compatibility code is introduced for debugging or a narrowly scoped transition, it must be called out in the same diff with:
  - why it exists
  - why the canonical path is insufficient
  - exact deletion criteria
  - the ADR/task that tracks its removal
- Default stance across the app: delete old-state compatibility code rather than carrying it forward.

## Codex Memory System

- Canonical Codex memory for this repo lives under `docs/codex_memory/`.
- Generated Codex retrieval/index state lives under `work/codex_memory/`.
- Checked-in memory is canonical; generated state must be rebuildable and can be deleted at any time.
- Do not add compatibility code for older memory schemas. The only supported schema is `codex-memory-v1`.

### Required workflow for future Codex sessions

1. At task start, read `docs/codex_memory/project_brief.md`, `docs/codex_memory/current_focus.md`, and `docs/codex_memory/handoff.md`, or run `python3 tools/codex_memory.py context`.
2. Before major planning or implementation, review recent durable state in `docs/codex_memory/decision_log.jsonl` and `docs/codex_memory/task_log.jsonl`.
3. After meaningful milestones, append a task event and update `docs/codex_memory/handoff.md`.
4. When a durable conclusion is reached, append a decision record with evidence references and affected paths.
5. Never store speculative claims as durable memory without marking them provisional in the record status or in the surrounding Markdown.

# Issues logging
- The role of the `ISSUES.md` file is to describe common mistakes and confusion points that the agents might encounter as they work in this project. If you ever counter something in the project that surprises you, please alert the developer working with you and indicate that this is the case in the ISSUES.md file tp help future agents from having the same issue.
