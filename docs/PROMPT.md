# Next Prompt

Relevant subsystem packs for this task: `architecture`, `life_scripts`, and `platform_windows`.
Load `backgrounds` only if you need to cross-check the current viewer-prep boundary while rewriting the roadmap. Load `scene_decode` only if you need to confirm how far scene-surface integration has actually progressed.

The repo has already crossed the old pre-viewer boundary. The current viewer-prep path, `11/10` and `2/2` acceptance surfaces, and the native PowerShell verification gate are landed and validated. The next step is not another viewer-local refinement slice. The next step is a doc-only replan gate that makes the strategic plan match the checked-in repo state and forces an explicit policy decision around the remaining life-script blocker.

The current checked-in state already has:

- a data-backed SDL2 interior viewer shell
- the `2/2` zero-fragment control path and the `11/10` fragment-bearing path
- `BRK`-backed top-surface previews, fragment comparison, live HUD / legend surfaces, and the focused owning-zone provenance overlay
- a canonical Windows verification gate in `scripts/verify-viewer.ps1`
- a checked-in life-program audit that says only `LM_DEFAULT` and `LM_END_SWITCH` remain as unsupported real-asset blockers for scene-surface life integration

Implement a doc-only replan pass that:

- updates `docs/LBA2_ZIG_PORT_PLAN.md` so it reflects reality instead of the old `Foundation + asset CLI` boundary
- records that the first-viewer gate has already been crossed and that the current implementation stream is viewer-prep evidence work on top of a validated runtime/viewer path
- makes the document hierarchy explicit:
  - `docs/LBA2_ZIG_PORT_PLAN.md` owns strategic phases, gates, and product-boundary decisions
  - `docs/codex_memory/current_focus.md` owns active repo state and current blockers
  - `docs/PROMPT.md` owns only the next narrow slice
- adds an explicit Phase 4 gate or equivalent decision point for `LM_DEFAULT` and `LM_END_SWITCH`
- states the two allowed branches clearly:
  - deepen evidence until those switch-family opcodes can be supported
  - or explicitly reject switch-family-dependent life paths from the current parity target
- keeps the current hard-cut policy intact: one canonical current-state codepath, fail-fast diagnostics, no compatibility bridges, no temporary second path unless explicitly justified
- updates any nearby strategic doc references that would otherwise keep pointing readers at the stale pre-viewer boundary
- updates memory only if the active repo status changed because of the replan, and only in canonical v2 locations
- adds an `ISSUES.md` note only if the rewrite uncovers a new recurring repo trap rather than ordinary doc drift

Relevant files are likely in:

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/architecture.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`
- `docs/PORTING_REPORT.md`
- `port/README.md`
- `docs/codex_memory/task_events.jsonl`
- `ISSUES.md`

Guardrails:

- Do not turn this into another viewer feature pass, runtime refactor, or life-decoder implementation task.
- Do not add new compatibility language that preserves the obsolete pre-viewer package boundary as if it were still canonical.
- Do not blur the distinction between strategic roadmap, current-state memory, and next-slice prompt. Make the ownership split explicit.
- Do not claim that all life work is blocked. The blocker is scene-surface life integration, not every offline life-oriented probe or audit.
- Do not widen the replan into gameplay design, licensing analysis, or a repo-wide prose cleanup beyond the files needed to remove the roadmap contradiction.
- Keep the viewer path framed as a validated evidence surface, not as an unfinished placeholder that still needs more polish before replanning.

Acceptance:

- `docs/LBA2_ZIG_PORT_PLAN.md` no longer describes the repo as if it were still at the pre-viewer `Foundation + asset CLI` boundary
- the rewritten roadmap explicitly says the first-viewer gate has been crossed
- the rewritten roadmap explicitly captures the `LM_DEFAULT` / `LM_END_SWITCH` decision gate for future gameplay/life integration
- the strategic/current-state/next-slice doc hierarchy is explicit and internally consistent
- any memory update stays within `codex-memory-v2` conventions
- if the repo already contains this exact replan state, land the slice as a no-op review instead of inventing another roadmap change
