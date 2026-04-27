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
- `ISSUES.md` is the companion repo trap log for the memory system and is linked through the architecture subsystem.

### Required workflow for future Codex sessions

1. At task start, read `docs/codex_memory/project_brief.md` and `docs/codex_memory/current_focus.md`, or run `python3 tools/codex_memory.py context`.
2. Load only the subsystem packs relevant to the task, or use `python3 tools/codex_memory.py context --path <repo-path>`.
3. Use typed history only when current state or a blocked question needs it.
4. After meaningful milestones, append the appropriate typed record and update `current_focus.md` only if the active repo status changed.
5. If you discover a new repo trap or recurring confusion point, update `ISSUES.md` and keep the architecture pack aligned with that trap surface.
6. Never reintroduce v1 files or schema labels.

## Reporting

- Always send completion, blocker, and unattended-work reports to the LBR Slack channel (`#lbr`, `C0AVAUZ4077`).
- `#lbr` is the default channel to send Slack messages to the user.
- If the game is opened, publish phone-viewable screenshots or reports first, then include the phone-share URL in the LBR Slack update.

# Issues logging
- The role of the `ISSUES.md` file is to describe common mistakes and confusion points that the agents might encounter as they work in this project. If you ever counter something in the project that surprises you, please alert the developer working with you and indicate that this is the case in the ISSUES.md file to help future agents from having the same issue.

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

# Test timeout
- The command `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast` often hits timeout so make sure to give at least 220 seconds.
