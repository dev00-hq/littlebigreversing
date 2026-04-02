# Next Prompt

Relevant subsystem packs for this task: `architecture`, `life_scripts`, `scene_decode`, and `platform_windows`.
Load `phase0_baseline` only if you need to compare the current Phase 4 question against the older milestone framing. Load `backgrounds` only if you need to prove why the next slice is not more viewer-local work.

The previous prompt aimed at a richer blocker report. That is no longer the right next step. The current offline audit JSON already exposes the headline blocker counts for both canonical scenes and `--all-scene-entries`: canonical is `36` blobs with `5` unsupported hits (`LM_DEFAULT` `3`, `LM_END_SWITCH` `2`), and the full archive is `3109` blobs with `394` unsupported hits (`LM_DEFAULT` `188`, `LM_END_SWITCH` `206`). Another aggregate-report pass would mostly be presentation churn.

The real open question for Phase 4 is narrower: do the checked-in sources, preserved docs, and real-asset probes contain enough structural evidence to support `LM_DEFAULT` and `LM_END_SWITCH` in one canonical decoder path, or is the correct current-state decision to reject switch-family-dependent life paths from the active parity target until stronger evidence exists?

The current checked-in state already has:

- a roadmap that names the Phase 4 life-boundary decision as the current strategic gate
- an offline life audit path that already proves only `LM_DEFAULT` and `LM_END_SWITCH` are active real-asset blockers
- a life evidence memo that already says those two opcodes still lack structural proof beyond header names and the `LM_BREAK` destination comment
- a canonical scene-model boundary where raw `life_bytes` stay authoritative and typed life decoding remains unwired

Implement a bounded hypothesis-test pass that:

- treats the existing audit counts as sufficient inventory and does not spend the slice on report-shape polish
- targets the actual uncertainty directly:
  - search the checked-in classic source, preserved docs, and existing real-asset probes for structural or runtime evidence specific to `LM_DEFAULT` and `LM_END_SWITCH`
  - use the known canonical blocker hits (`scene 2` hero, `scene 5` hero, `scene 44` hero, and the known `scene 44` object hits) as the minimum real-asset anchor set
- if the current probe surfaces are insufficient, adds only the smallest offline helper needed to inspect the local byte window or decoded control-flow context around those unsupported hits
- updates `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` so it answers the real question explicitly for each opcode:
  - what is proven
  - what is still unproven
  - whether branch A is supportable from checked-in evidence today
- if the evidence memo supports a recommendation, promote the actual current-state branch recommendation through `docs/codex_memory/current_focus.md` or `docs/LBA2_ZIG_PORT_PLAN.md`, because the evidence memo is supporting context rather than the owner of product-boundary decisions
- ends in one of two explicit outcomes:
  - stronger checked-in evidence exists, with exact file references and the narrowest defensible decoder claim
  - stronger checked-in evidence still does not exist, with an explicit recommendation in the owning strategic/current-state doc that the current parity target should take the Phase 4 rejection branch until new evidence appears
- keeps all life work offline: no scene parser wiring, no runtime interpreter work, no viewer changes, no gameplay widening
- keeps the hard-cut policy intact: fail fast on unsupported opcodes and do not invent placeholder semantics, compatibility glue, or a second life path
- updates memory only if this prompt refresh or the new evidence pass changes active repo status, and only in canonical v2 locations

Relevant files are likely in:

- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `port/src/tools/cli.zig`
- `port/src/game_data/scene/life_audit.zig`
- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/tests/life_audit_tests.zig`
- `reference/lba2-classic/SOURCES/COMMON.H`
- `reference/lba2-classic/SOURCES/GERELIFE.CPP`
- `reference/lba2-classic/SOURCES/DISKFUNC.CPP`
- `ISSUES.md`
- `docs/codex_memory/task_events.jsonl`

Guardrails:

- Do not spend the slice on a nicer aggregate blocker report unless a tiny helper is genuinely required to inspect the target hits.
- Do not wire typed life instructions into scene parsing or widen into scene-surface life integration.
- Do not claim semantics or operand layouts for `LM_DEFAULT` or `LM_END_SWITCH` from header names alone.
- Do not keep the Phase 4 decision ambiguous if the evidence pass finds nothing new; say that clearly.
- Do not add compatibility fallbacks, partial switch-family execution, or a temporary second decoder/interpreter path.
- Do not turn this into viewer/runtime work just because that path landed most recently.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `zig build tool -- audit-life-programs --json`
  - `zig build tool -- audit-life-programs --json --all-scene-entries`
- the resulting work explicitly answers whether checked-in evidence supports branch A for `LM_DEFAULT` and `LM_END_SWITCH`
- if no new structural proof is found, `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md` states that plainly and the owning strategic/current-state doc carries the rejection-branch recommendation for the current parity target until new evidence lands
- if new structural proof is found, the updated evidence memo names the exact sources and the narrowest defensible decoder claim
- no runtime/viewer/gameplay wiring is added
- any memory update stays within `codex-memory-v2` conventions
