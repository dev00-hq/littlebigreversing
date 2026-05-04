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
- The only supported memory schema is `codex-memory-v2`.
- Subsystem packs under `docs/codex_memory/subsystems/` are the on-demand current-state layer.
- Typed JSONL files under `docs/codex_memory/` are the only durable history layer.
- Generated files under `docs/codex_memory/generated/` are reproducible derived context, not canonical truth.

### Issue logging 
- Goes in `ISSUES.md` and is linked through the architecture subsystem.
- Keep track of unresolved problems / bugs / TODOs / investigation backlog, like a work queue.
- Put it in ISSUES.md when it answers what is still broken, unknown, blocked, or waiting to be investigated?
- ISSUES.md entries exists only until a test or a lint exists or the behavior is encoded in a CLI diagnostic or the ambiguity is captured in a typed evidence/contract record.

### Lessons
- Go in lessons `docs/codex_memory/lessons.md`
- Durable knowledge the agent must remember even after an issue is closed
- An entry in lessons.md answers what lesson, invariant, trap, decision, or proven fact should future agents not forget?
  
So the same topic can appear in both in ISSUES.md and lessons.md temporarily, but not with the same role.

### Required workflow for future Codex sessions

1. At task start, read `docs/codex_memory/project_brief.md` and `docs/codex_memory/current_focus.md`, or run `python3 tools/codex_memory.py context`.
2. Load only the subsystem packs relevant to the task, or use `python3 tools/codex_memory.py context --path <repo-path>`.
3. Use `python3 tools/codex_memory.py briefing --task "<task>"` only as an optional task lens; do not treat it as canonical startup truth.
4. Use typed history only when current state or a blocked question needs it.
5. After meaningful milestones, append the appropriate typed record and update `current_focus.md` only if the active repo status changed.
6. If you discover a new repo trap or recurring confusion point, update `ISSUES.md` and keep the architecture pack aligned with that trap surface.
7. Never reintroduce v1 files or schema labels.

## Runtime/gameplay promotion packets

- Runtime/gameplay seam widening is gated by `docs/promotion_packets/`.
- Decoded or inferred seams may remain tooling candidates, but canonical runtime behavior requires a promotion packet with `live_positive` or `approved_exception`.
- Run `py -3 tools/validate_promotion_packets.py` after changing packet docs, packet fixtures, or emitted runtime contract ids.
- Do not promote `decode_only` or `live_negative` seams into runtime commits.

## Reporting when the user is working on his phone
- When the user specifies that he's on his phone send completion, blocker, and unattended-work reports to the LBR Slack channel (`#lbr`, `C0AVAUZ4077`).
- If the game is opened, publish phone-viewable screenshots or reports first, then include the phone-share URL in #lbr.

# Shell specific tools
- Use the provided environment context to determine whether the current shell is PowerShell or Linux Bash; do not rely on a Bash-evaluated PowerShell redirection snippet.

## On Linux Bash
- Prefer these tools: ripgrep (rg), ast-grep (sg), jq (json processor)

## On Powershell
- Prefer bundled bash helpers (`bash -lc`), always set the `workdir` parameter. Fallback to native Powershell.
- Prefer native PowerShell ONLY for canonical build/test/tool commands. Use `py -3 .\scripts\dev-shell.py shell` for an interactive configured shell, or `py -3 .\scripts\dev-shell.py exec --cwd port -- ...` for scripted Zig/MSVC verification.
- Use rg/rg --files for searches; fall back only if unavailable.
- Use the `apply_patch` to edit files, fallback to sed.
- Use jq for json processing

Note: Use the $critical-sparring skill as your main driver to keep uncertainty low and not overtrust, for planning and implementations use $make-change-easy
