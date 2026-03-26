# Replace Codex Memory With Topology-First v2

## Summary

Replace the current timeline-heavy memory system in place under `docs/codex_memory/` and `tools/codex_memory.py`, migrate once, then delete the old model entirely. The new system keeps a tiny always-loaded layer, moves durable repo truth into subsystem packs, keeps typed JSONL history only for real structured records, and removes the SQLite mirror / handoff summary / oversized handoff flow.

The final steady state is:

- always loaded: `AGENTS.md`, `project_brief.md`, `current_focus.md`
- on demand: subsystem packs under `docs/codex_memory/subsystems/`
- structured history: typed JSONL files with strict semantic contracts
- tooling: one lean CLI plus repo-local skills
- no v1 compatibility code, no parallel v2 tree, no canonical SQLite
- one explicit schema cutover in the same diff that updates `AGENTS.md`, `docs/codex_memory/README.md`, and the CLI surface

## Implementation Changes

### Canonical file model

Keep `docs/codex_memory/` as the canonical root, but replace the contents with this contract:

- `project_brief.md`
  - stable repo purpose, repo map, canonical sources, invariants, non-goals
  - hard budget: `<= 2 KB`
- `current_focus.md`
  - tiny active status only: current priorities, active streams, blocked items, next actions, relevant subsystem packs
  - no historical facts, no milestone changelog, no long narrative
  - hard budget: `<= 3 KB`
- `subsystems/INDEX.md`
  - pack list plus the canonical path-to-pack mapping rules
- `subsystems/assets.md`
- `subsystems/mbn_corpus.md`
- `subsystems/phase0_baseline.md`
- `subsystems/scene_decode.md`
- `subsystems/life_scripts.md`
- `subsystems/backgrounds.md`
- `subsystems/platform_windows.md`
- `subsystems/platform_linux.md`
- `subsystems/architecture.md`
- `README.md`
  - workflow, commands, write rules, budgets

Delete these canonical v1 files after migration:

- `handoff.md`
- `decision_log.jsonl`
- `task_log.jsonl`

Each subsystem pack uses the same fixed sections:

- Purpose
- Invariants
- Current Parity Status
- Known Traps
- Canonical Entry Points
- Important Files
- Test / Probe Commands
- Open Unknowns

Each subsystem pack has a hard budget of `<= 4 KB` and must stay subsystem-local. No repo-wide policy, no unrelated history.

The initial pack set must cover every active stream and every canonical source family currently named in `project_brief.md` and `current_focus.md`. If a live repo area has no pack, cutover is blocked until one is added.

### Structured history model

Use separate typed JSONL files, not one mixed log:

- `policies.jsonl`
- `subsystem_facts.jsonl`
- `investigations.jsonl`
- `compat_events.jsonl`
- `task_events.jsonl`

Use one new schema version for this model, for example `codex-memory-v2`. Do not keep the `codex-memory-v1` label for incompatible record shapes, and do not support both schemas at runtime after cutover.

Canonical ownership rules:

- `project_brief.md`, `current_focus.md`, and subsystem packs are the current-state briefing layer
- typed JSONL files are the durable history layer
- packs may summarize the current conclusion of a durable record when that conclusion is still operationally relevant, but they should not copy full record bodies or become another append-only changelog
- facts that matter only as history stay in the JSONL layer instead of being repeated into packs

Common required fields for every record:

- `schema_version`
- `record_id`
- `timestamp_utc`
- `author`
- `affected_paths`
- `evidence_refs`

Type-specific fields:

- `policies.jsonl`
  - `status`
  - `topic`
  - `statement`
  - `rationale`
  - `supersedes`
- `subsystem_facts.jsonl`
  - `subsystem`
  - `status`
  - `fact`
  - `rationale`
  - `supersedes`
- `investigations.jsonl`
  - `subsystem`
  - `status` with only `open`, `blocked`, `resolved`, `rejected`
  - `question`
  - `current_best_answer`
  - `confidence` with only `low`, `medium`, `high`
  - `next_probe`
- `compat_events.jsonl`
  - `subsystem`
  - `status`
  - `title`
  - `summary`
- `task_events.jsonl`
  - `stream`
  - `status` with only `planned`, `in_progress`, `blocked`, `completed`, `cancelled`
  - `summary`
  - `next_actions`

Validation rules:

- no empty strings or empty list items
- all paths repo-relative
- all timestamps timezone-qualified UTC
- `record_id` recomputed from stable typed fields, not arbitrary prose blobs
- summary-like fields capped at `240` chars
- rationale / current_best_answer capped at `600` chars
- records that exceed caps fail validation

### CLI and skills

Rewrite `tools/codex_memory.py` in place as the v2 CLI with only these commands:

- `validate`
  - validate markdown sections, budgets, JSONL schema, and subsystem index mappings
- `context`
  - default output: `project_brief.md` + `current_focus.md`
  - optional `--subsystem <name>` repeatable
  - optional `--path <repo-path>` repeatable, resolved through `subsystems/INDEX.md` mapping
  - optional `--include-history <N>` to include only the last `N` relevant records for selected subsystems
- `add-policy`
- `add-fact`
- `add-investigation`
- `add-compat-event`
- `add-task-event`

Do not add:

- SQLite generation
- summary-of-summary generation
- auto-refresh mirror commands
- v1 fallback readers

Optionally add repo-local workflow helpers under `.agents/skills/` if the host resolves repo-local skills cleanly:

- `memory-start`
  - read `project_brief.md`, `current_focus.md`, and relevant subsystem packs from touched paths
- `memory-update`
  - append typed records and keep `current_focus.md` within budget
- `memory-pack-maintenance`
  - update a subsystem pack without leaking status/history into global docs

These skills are secondary workflow helpers. The canonical cutover must not depend on skill discovery or skill installation in order to read, validate, or update memory.

Update `AGENTS.md` so the required workflow becomes:

1. read `project_brief.md` and `current_focus.md`
2. load only relevant subsystem packs for the task
3. use typed history only when needed
4. never restore or reference v1 files

## Migration And Cutover

Use an in-place cutover with no long-lived migration code in the final tree.

Temporary migration flow:

1. Freeze the v2 file model, pack index, and schema name first.
2. Update `AGENTS.md`, `docs/codex_memory/README.md`, and the CLI contract in the same cutover diff so the repo does not advertise the old workflow after the new tree lands.
3. Create the initial subsystem packs manually from the checked-in current-state docs/code for each active repo area.
4. Use a one-shot migration helper during development only for mechanical transforms and reports.
5. Review unresolved candidates explicitly, then write the final canonical v2 docs/records.
6. Validate the new tree.
7. Delete the migration helper before finalizing the implementation.
8. Delete all v1 canonical files and generated artifacts.

The temporary helper exists only because the current v1 memory is prose-heavy and repetitive enough that mechanical extraction is still useful for review. It is not sufficient to define canonical v2 pack placement by itself. Deletion criteria: remove it once the checked-in v2 tree validates and the repo no longer needs any v1-to-v2 extraction path. Track that helper removal as part of the same implementation task/ADR that performs the cutover.

Migration rules are strict and reviewable:

- `project_brief.md`
  - compact the existing file; preserve repo purpose/map/invariants/non-goals only
- `current_focus.md`
  - rebuild from current `current_focus.md` plus only the still-active blockers and next actions from `handoff.md`
  - no verified-facts import
- subsystem packs
  - seed each pack from current checked-in code/docs for that subsystem, not from log replay alone
  - treat `handoff.md` `Verified Facts`, `decision_log.jsonl`, and `task_log.jsonl` as candidate source material for manual carry-forward, not as an authority that can be reclassified by heuristics
  - use explicit path mapping where it is sufficient
  - if multiple subsystems match, fail migration and require manual resolution
  - if no subsystem matches, place into `architecture.md` only if it is genuinely repo-wide architecture; otherwise fail migration
- v1 `decision_log.jsonl`
  - repo-wide durable rules become `policies.jsonl`
  - subsystem-scoped accepted durable truths become `subsystem_facts.jsonl`
  - old codex-memory-only decisions are not preserved as durable repo truth; synthesize one `compat_event` that records v1 retirement
- v1 `task_log.jsonl`
  - unresolved or still-relevant probes become `investigations.jsonl`
  - shipped historical milestones become `compat_events.jsonl` only when they explain current subsystem state or the v1 retirement itself
  - transient completed task churn is dropped instead of being re-encoded as new history noise
- `work/codex_memory/`
  - delete entirely if present; do not recreate it in v2
- old commands and schemas
  - remove entirely after cutover

Migration must fail fast on ambiguous subsystem classification, missing subsystem coverage, or oversized outputs. No best-effort guessing.

## Test Plan

- CLI validation accepts the new canonical tree and rejects:
  - missing required sections
  - oversized `project_brief.md`, `current_focus.md`, or subsystem packs
  - invalid record statuses or confidence values
  - bad repo-relative paths
  - ambiguous path-to-pack mappings
- `context` default includes only `project_brief.md` and `current_focus.md`
- `context --path` and `context --subsystem` load the expected packs and no unrelated packs
- `context --include-history N` includes only relevant typed records for the selected subsystem(s)
- Adding each record type writes canonical IDs and passes validation
- Migration test fixture converts representative v1 inputs into:
  - compact `current_focus.md`
  - review-ready subsystem pack inputs or explicitly flagged unresolved items
  - typed history files for the mechanically classifiable carry-forward records
  - no `handoff.md`, no v1 logs, no generated mirror
- Acceptance check after cutover:
  - `AGENTS.md` references only the new workflow
  - `AGENTS.md` and canonical docs name only the new schema version
  - `tools/codex_memory.py` exposes only v2 commands
  - `docs/codex_memory/` contains no v1 files
  - every current active stream has a subsystem pack and `subsystems/INDEX.md` mapping
  - `work/codex_memory/` does not exist
  - if repo-local skills are included, they match the final v2 workflow and are not required for the canonical path

## Assumptions

- Replace in place under the existing paths; no `codex_memory_v2` tree.
- Keep `current_focus.md` as the tiny active-status file; do not introduce a separate `active_status.md`.
- The final system keeps typed JSONL as canonical structured history, with no canonical SQLite.
- Repo-local skills are optional helpers, not part of the canonical contract.
- Any durable information worth keeping from v1 is carried into v2 canonical files before deletion; do not rely on an external backup as part of the product design.
