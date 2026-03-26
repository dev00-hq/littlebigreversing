# Memory System Report

## Scope

This report reviews the current Codex memory system described in `docs/MEMSYS.md`, the live canonical memory under `docs/codex_memory/`, the implementation in `tools/codex_memory.py`, and the relevant official OpenAI Codex guidance:

- [Run long horizon tasks with Codex](https://developers.openai.com/blog/run-long-horizon-tasks-with-codex)
- [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md)
- [Agent Skills](https://developers.openai.com/codex/skills)

I also split the analysis across three subagents: design/docs, implementation/tooling, and OpenAI-guidance comparison.

## Executive Summary

Your diagnosis is mostly correct.

The current system is not failing because it lacks storage. It is failing because it mixes too many semantic roles into a small set of global files:

- active state
- durable facts
- milestone history
- retrieval cache
- generated mirrors

The result is a timeline-heavy memory system that keeps growing, overlaps with itself, and still does not retrieve by subsystem or task topology.

The strongest conclusion is this:

- the repo needs less "memory system" and more information hierarchy
- the always-loaded layer needs to be much smaller
- durable facts need subsystem-local homes
- append-only history should stop being the default reading path

## What I Verified

### 1. No hard information hierarchy

Verdict: correct.

Evidence:

- `docs/MEMSYS.md` already states that the system has "no explicit information hierarchy beyond file names."
- `docs/codex_memory/current_focus.md` carries current priorities, blockers, and next actions.
- `docs/codex_memory/handoff.md` carries current state, verified facts, open risks, and next steps.
- `docs/codex_memory/decision_log.jsonl` and `docs/codex_memory/task_log.jsonl` also restate status and milestones.

This means facts, status, and history leak across multiple canonical surfaces instead of having one strict home per semantic type.

### 2. Too much prose in canonical state

Verdict: correct.

Evidence:

- `docs/codex_memory/handoff.md` is `23540` bytes.
- Its `Verified Facts` section alone is `15089` bytes across `58` bullets.
- `decision_log.jsonl` averages about `1275` bytes per record.
- `task_log.jsonl` averages about `1083` bytes per record.

The records are structured at the envelope level, but the payloads are still long prose blocks. That pushes the system back toward transcript-like storage.

### 3. “Always loaded” memory is too fat

Verdict: correct.

Evidence:

- `project_brief.md` is `1745` bytes.
- `current_focus.md` is `4376` bytes.
- `handoff.md` is `23540` bytes.
- `python3 tools/codex_memory.py context` renders one large linear briefing.
- `docs/MEMSYS.md` reports that the rendered context is about `15 KB`.

For a repo primer, that is already too large. More importantly, most of that space is not topology-filtered. It is global narrative state.

### 4. Derived artifacts do not currently earn their keep

Verdict: correct, with one nuance.

Evidence:

- `tools/codex_memory.py` `build_index()` rebuilds a SQLite database by copying markdown bodies and JSON fields into tables.
- `refresh_handoff_summary()` rerenders `context` and writes it out again as `handoff_summary.md`.
- There are no retrieval/query commands over the SQLite file.
- The tool never consults the generated artifacts during normal `context` rendering.

Nuance:

- this proves the current derived artifacts are weakly justified
- it does not prove derived artifacts are inherently useless

A generated index could be worth keeping later, but only if it becomes a real retrieval layer over subsystem-scoped records. Right now it is mostly mirror-and-summary duplication.

### 5. No lifecycle rules

Verdict: correct.

Evidence:

- `add_decision()` and `add_task_event()` append forever.
- There is no compaction, archival, rollup, pruning, or active-state rewrite command.
- `supersedes` is stored but not operationalized into active-view filtering.
- markdown validation only checks required headings and non-empty sections.

Append-only history is fine. Append-only active state is not. The system has no compaction boundary for the part that is supposed to stay small.

## Additional Findings

### Timeline memory is dominating topology memory

The current memory surfaces are mostly time-oriented:

- `handoff.md`
- `decision_log.jsonl`
- `task_log.jsonl`
- `handoff_summary.md`
- SQLite mirror

That is the wrong default shape for a wide reverse-engineering and porting repo. Most future tasks will care about one subsystem, one platform, one asset format, or one parity boundary, not the full project timeline.

### `handoff.md` is both overloaded and partially dead weight

There is a concrete mismatch between the docs and the implementation:

- `tools/codex_memory.py` requires `handoff.md` to contain `Verified Facts`
- `render_context()` does not include `Verified Facts` in the default briefing

So the system forces that section to exist, allows it to grow large, and then omits it from the main cold-start path. That is a strong sign the file has outgrown its semantic contract.

### Decisions and tasks are overloaded

Many decision records are not really long-lived architectural decisions. They are milestone freezes, scope boundaries, or implementation checkpoints. Many task events also act as semi-durable subsystem summaries.

That makes both logs harder to query and increases duplication with `handoff.md`.

### The current identity model still rewards prose

`decision_id` is hashed from `topic + statement`, and `event_id` is hashed from `task_id + summary`.

That means the canonical identity scheme is still tied to prose-heavy fields rather than compact typed record keys.

### The documented generated-state footprint is stale relative to the current worktree

`docs/MEMSYS.md` describes measured generated artifacts under `work/codex_memory/`, but `work/codex_memory/` is absent in the current worktree.

That does not change the design critique, but it is a concrete repo trap: the design memo is discussing a rebuilt generated surface that is not currently present on disk.

## Comparison To OpenAI Guidance

### What matches

- The repo is using durable markdown rather than relying on chat-only context.
- `AGENTS.md` is being used for repo-wide operating rules, which matches OpenAI's intended role for it.
- The repo has explicit workflow commands and validation paths instead of vague conversational memory.

### What diverges

- OpenAI's long-horizon example uses a small set of durable files with distinct roles: spec, plan, runbook, and status/audit log.
- OpenAI's AGENTS guidance says `AGENTS.md` is auto-loaded and combined instructions are capped by `project_doc_max_bytes` (`32 KiB` by default).
- OpenAI's skills guidance uses progressive disclosure: load metadata first, load the full skill only when needed.

This repo diverges in three ways:

1. The always-loaded layer is too large.
2. Too much detail lives in global markdown instead of on-demand subsystem docs or skills.
3. Repeated workflows are not being packaged as repo-local skills.

Inference:

OpenAI's guidance supports durable files, but it does not support turning the default startup path into a repo-wide narrative database. The direction is closer to:

- small pinned instructions
- explicit task/runbook docs
- on-demand workflows
- progressive disclosure

not:

- one big always-read briefing plus mirrors and summaries

## Recommended Redesign

### Layer 1: tiny global pinned context

Always loaded:

- `AGENTS.md`
- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`

Hard rules:

- keep these short
- no subsystem fact dumps
- no milestone changelog
- no long verified-facts inventory

Suggested role split:

- `AGENTS.md`: repo rules, workflow rules, product policy
- `project_brief.md`: repo purpose, map, top-level invariants, canonical sources
- `current_focus.md`: current priorities, active streams, blockers, immediate next actions only

### Layer 2: subsystem memory packs

Load only when the task touches that area.

Suggested structure:

- `docs/codex_memory/subsystems/assets.md`
- `docs/codex_memory/subsystems/scene_decode.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `docs/codex_memory/subsystems/backgrounds.md`
- `docs/codex_memory/subsystems/platform_windows.md`
- `docs/codex_memory/subsystems/platform_linux.md`
- `docs/codex_memory/subsystems/architecture.md`

Each pack should contain only:

- invariants
- current parity status
- known traps
- canonical entry points
- important files
- test/probe commands
- open unknowns

This is the most important architectural change. It shifts memory from timeline shape to topology shape.

### Layer 3: structured historical store

Keep history append-only, but stop treating it as default reading.

Recommended record types:

- `policy`
- `subsystem_fact`
- `investigation`
- `compat_event`
- `task_event`

Suggested semantics:

- `policy`: stable repo-wide rules
- `subsystem_fact`: durable fact scoped to one subsystem/platform/format
- `investigation`: unresolved finding with evidence and confidence
- `compat_event`: milestone, regression, parity shift, or temporary hack record
- `task_event`: active-work checkpoint, not durable truth

This separates stable truth from uncertainty and from milestone history.

## What To Remove Or Downgrade

### Replace `handoff.md`

Replace it with `active_status.md` under a hard budget.

Contents:

- active streams
- current blockers
- immediate next steps
- pointers to relevant subsystem packs

Do not let it become a fact inventory or milestone changelog.

### Remove `handoff_summary.md`

Unless it can prove startup or retrieval value, it is summary-of-summary bloat.

### Remove the SQLite mirror or turn it into real retrieval

Keep it only if it becomes a genuine query surface over typed records and subsystem packs.

Do not keep it as a plain mirror.

## Minimal Transition Plan

1. Stop growing `handoff.md`.
2. Introduce `active_status.md` with a strict size budget.
3. Create initial subsystem packs for the memory-heavy areas already present in `handoff.md`.
4. Move durable facts out of `handoff.md` into subsystem packs or typed records.
5. Keep append-only history, but downgrade it from default-reading material to query-only material.
6. Delete `handoff_summary.md` and the SQLite mirror unless a real retrieval path is implemented immediately.
7. Add repo-local skills for repeated workflows instead of expanding the always-loaded markdown path.

## Bottom Line

The current system is serviceable, but its information model is wrong for this repo.

It externalizes state, which is good. But it organizes that state mostly by timeline, stores too much of it as prose, duplicates it across multiple surfaces, and keeps too much of it in the always-loaded path.

The redesign should optimize for:

- bounded startup
- one canonical home per information type
- subsystem-first retrieval
- explicit uncertainty
- compact active state

That is the shift from timeline memory to topology memory.
