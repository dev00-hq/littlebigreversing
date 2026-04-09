# Lessons Learned Report

## Scope

This report reflects a codebase pass across the current repo memory, roadmap docs, verification scripts, and representative Zig modules in `port/`.

Primary anchors:

- `docs/codex_memory/project_brief.md`
- `docs/codex_memory/current_focus.md`
- `sidequest/DECISION_PLAN.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `port/src/tools/cli.zig`
- `port/src/runtime/room_state.zig`
- `port/src/runtime/session.zig`
- `port/src/runtime/world_query.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/app/viewer_shell_test.zig`
- `port/build.zig`
- `scripts/verify_viewer.py`

## Executive Summary

The strongest lesson from this repo is that reverse-engineering work becomes much more productive when evidence gathering, decoding, diagnostics, and runtime code are treated as one integrated product surface.

This project does not chase broad coverage early. It narrows scope aggressively, proves one canonical path with real assets, rejects unsupported cases on purpose, and only extracts reusable runtime seams when the code has genuinely stopped depending on LBA2-shaped inputs.

## Lessons Learned

### 1. Treat tooling and diagnostics as first-class deliverables

The CLI, viewer shell, fixture generation, life audit, and verification scripts are not side utilities. They are the main way the repo turns uncertain reverse-engineering facts into reproducible evidence.

Evidence:

- `port/src/tools/cli.zig` exposes inspection and audit commands as stable entry points.
- `scripts/verify_viewer.py` turns runtime expectations into a repeatable Windows acceptance gate.
- `port/src/app/viewer_shell.zig` presents the viewer as a debug and evidence surface, not a polished gameplay loop.

Practical lesson:

When working in an under-documented format, build inspection tools and validation surfaces before widening runtime behavior. The tool often becomes the proof that the implementation is correct.

### 2. A narrow supported baseline is a force multiplier

The repo keeps `19/19` as the only supported positive guarded runtime/load pair and treats `2/2`, `44/2`, and `11/10` as explicit guarded negative cases or test-only evidence paths.

Evidence:

- `docs/codex_memory/current_focus.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `port/src/runtime/room_state.zig`

Practical lesson:

Picking one canonical success case and a few named failure cases creates faster progress than trying to support every interesting sample at once. It keeps regressions legible and stops “partial parity” from turning into a vague target.

### 3. Fail-fast boundaries beat speculative compatibility

Unsupported life-script cases are rejected at the runtime/load seam instead of being carried deeper into the viewer or hidden behind fallback behavior.

Evidence:

- `port/src/runtime/room_state.zig` validates the life boundary before room adaptation.
- `port/src/game_data/scene/life_audit.zig` owns the blocker report and audit surface.
- `port/build.zig` fails immediately when the required SDL2 dependency is missing.
- `port/src/foundation/diagnostics.zig` keeps error reporting explicit and structured.

Practical lesson:

In reverse-engineering-heavy code, precise rejection is often more valuable than partial support. It preserves trust in the working path and makes unsupported content visible enough to investigate later.

### 4. Separate compatibility work from runtime work, but classify mixed code honestly

The repo makes a useful distinction between source-faithful compatibility code, runtime code, and mixed modules that still bridge both worlds.

Evidence:

- `sidequest/DECISION_PLAN.md` defines promotion rules for calling something engine core.
- `port/src/game_data/scene.zig` and `port/src/game_data/background.zig` act as stable facades over decode internals.
- `port/src/runtime/session.zig` is a narrow neutral seam built from explicit world-position input.
- `port/src/runtime/room_state.zig` is kept as the mixed adaptation boundary instead of being mislabeled as generic engine code.

Practical lesson:

Architecture gets healthier when the codebase names its transitional states honestly. Calling a module “mixed” is better than pretending a format-shaped adapter is already reusable engine core.

### 5. Asset-backed tests are more valuable than isolated parser confidence

The tests in this repo lean on real assets, real room pairs, and exact runtime expectations instead of only synthetic byte-level fixtures.

Evidence:

- `port/src/app/viewer_shell_test.zig` checks seeded locomotion, rejected moves, and room metadata using checked-in assets.
- `port/src/runtime/session.zig` tests the separation between immutable room data and mutable runtime session state.
- The subsystem packs explicitly treat `zig build test` as asset-backed verification, not merely a unit-test pass.

Practical lesson:

If the goal is parity with opaque original data, tests should exercise real samples and real invariants. Synthetic fixtures still matter, but they are not enough on their own.

### 6. Small, opinionated project memory prevents rediscovery churn

The codex memory system is intentionally small, typed, and current-state oriented. It avoids timeline-heavy handoff sprawl and makes the current repo boundary easy to reload at task start.

Evidence:

- `docs/codex_memory/README.md`
- `tools/codex_memory.py`
- `docs/codex_memory/subsystems/*.md`

Practical lesson:

For a long-running reverse-engineering repo, compact current-state memory is part of the architecture. It reduces repeated misreads, helps future sessions avoid stale plans, and keeps subsystem truth close to the code.

### 7. Platform bias should be explicit, not accidental

This repo is clearly Windows-first for runtime verification and honest about Linux being secondary for source and doc work.

Evidence:

- `port/README.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `scripts/verify_viewer.py`
- `port/build.zig`

Practical lesson:

Declaring the primary platform removes ambiguity from acceptance criteria. It is better to have one trusted verification environment than several weakly supported ones.

### 8. Evidence should outrank legacy prose when they disagree

The repo repeatedly warns that old reports, prompt docs, and header names can lag or overclaim. Checked-in probes, asset-backed regressions, and current subsystem packs are treated as the final authority.

Evidence:

- `docs/codex_memory/subsystems/architecture.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `docs/codex_memory/current_focus.md`

Practical lesson:

In a repo that mixes plans, preserved source, and newly decoded facts, the freshest validated evidence must outrank older narrative documents. Otherwise the project slowly optimizes for old assumptions.

## What Seems To Be Working Well

- One canonical codepath per supported subsystem.
- Explicit negative cases alongside positive baselines.
- Clear separation between investigation tooling and runtime widening.
- Honest architecture language around compatibility, mixed modules, and extracted seams.
- Tight coupling between roadmap gates and real verification commands.

## Risks To Keep Watching

- Mixed runtime modules such as `room_state.zig` and `world_query.zig` can attract accidental engine-generalization language before their dependencies are truly neutralized.
- The current positive runtime surface is intentionally narrow; widening too early would make it easier to mistake evidence coverage for product support.
- Older narrative docs can drift behind the subsystem packs and current-focus file if they are not updated in the same change.

## Recommendations For Future Work

- Keep the `19/19` guarded baseline canonical until new checked-in evidence justifies widening it.
- Continue treating unsupported life-script cases as deliberate runtime boundary failures rather than “almost supported” content.
- Extract new runtime seams only when a real LBA2-shaped dependency disappears from the checked-in call path.
- Preserve tool and test work as product work, especially when a new format fact is promoted into code.
- Prefer updating subsystem packs and typed records over writing broad timeline summaries.

## Bottom Line

The repo’s most transferable lesson is not “how to port LBA2 in Zig.” It is how to make reverse-engineering progress reliable: choose one defensible baseline, prove it with tools and tests, fail fast outside it, and only generalize after the evidence stops being format-shaped.
