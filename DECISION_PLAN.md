# Decision Plan

## Purpose

This document records one binding strategic decision and the operating rules that follow from it.

Its job is to stop future sessions from re-litigating project identity while the repo is still inside the current branch-B parity boundary.

## Document Ownership

- `docs/LBA2_ZIG_PORT_PLAN.md` remains the canonical roadmap for phases, gates, and acceptance checks.
- `docs/codex_memory/current_focus.md` remains the canonical source for the checked-in supported baseline, blockers, and active execution focus.
- `DECISION_PLAN.md` records the long-term framing decision and the layer-boundary policy that roadmap work must follow.
- If those docs diverge, align them in the same diff. Do not leave split strategy owners in-tree.

## Current Strategic Decision

Continue the repo.

Near-term execution remains parity-first, evidence-first, Windows-first, and fail-fast on the current supported LBA2 boundary.

We are not pausing parity work to invent a generic engine.

We are also not accepting deeper LBA2-shaped architecture than the active gate requires.

The governing rule is:
keep current work useful for LBA2 parity now, but extract reusable runtime seams only when the extraction is explicit and passes the promotion rules below.

## Non-Goals

This decision does not authorize:

- sequel systems
- a second game target
- a generic scripting runtime designed ahead of evidence
- a broad save/load architecture designed ahead of a concrete runtime need
- editor-platform scope expansion that is not required by the active roadmap gate
- direct competition with `idajs` on near-term modding speed
- direct competition with `lba2remake` on near-term remake/editor UX

## Current Repo Reality

- The checked-in guarded runtime/load baseline is still `19/19`.
- `11/10` remains evidence-only on unchecked test paths, not a supported runtime-positive load.
- Branch B remains active: `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary unless new checked-in primary-source evidence reopens that decision.
- The current viewer/runtime path is real and valuable, but it is still LBA2-shaped.
- No current module should be described as clean engine core without extraction work.

Current working classification:

- compatibility: `port/src/assets/hqr.zig`
- compatibility: `port/src/game_data/scene/parser.zig`
- compatibility: `port/src/game_data/background/parser.zig`
- compatibility: `port/src/game_data/scene/life_program.zig`
- compatibility: `port/src/game_data/scene/track_program.zig`
- mixed/currently coupled: `port/src/runtime/room_state.zig`
- mixed/currently coupled: `port/src/runtime/session.zig`
- mixed/currently coupled: `port/src/runtime/world_query.zig`

This classification is a decision rule, not branding.
Mixed modules remain mixed until their public APIs stop depending on LBA2-specific asset/load types.

## Layer Policy

### Engine Core

Engine core owns generic runtime concerns that can survive without original LBA2 formats or opcodes:

- platform
- timing
- input
- rendering
- audio
- deterministic update ownership
- long-lived runtime/session/entity state
- generic world/query primitives
- diagnostics primitives that are not format-shaped

Engine core must not:

- import from `port/src/assets/` or `port/src/game_data/`
- expose HQR, scene entry indices, classic-loader indices, `LM_*`, or `TM_*` in public APIs
- require `RoomSnapshot`, `SceneMetadata`, or `BackgroundMetadata` as construction inputs

### Compatibility Layer

Compatibility owns original-format decoding and source-faithful adaptation:

- HQR and original asset containers
- scene/background parsing
- life/track decoding and auditing
- original loader rules, indices, and source-shaped behavior
- adaptation from classic payloads into neutral runtime inputs

Compatibility may be ugly and source-faithful when needed.
Compatibility must not be renamed engine core just because it is useful.

### Tools And Diagnostics

Tools may depend on core and compatibility to inspect, validate, visualize, or compare behavior.

Core and compatibility should not depend on tools for their semantics.

### Mixed Modules

Mixed is an allowed temporary state, not a target architecture.

A module is mixed when it both:

- owns runtime/session/render/query state
- directly depends on original asset/load/audit types or semantics

Mixed modules should only be kept while extraction work is active and explicit.

## Promotion Rules For Engine-Core Claims

A module may be called engine core only when all of the following are true:

1. Its public API can be constructed from neutral runtime inputs rather than `RoomSnapshot`, `SceneMetadata`, `BackgroundMetadata`, or direct asset-loader outputs.
2. It does not import from `port/src/assets/` or `port/src/game_data/`.
3. Its public types and function names do not expose HQR terms, scene entry indices, classic-loader indices, `LM_*`, or `TM_*`.
4. LBA2-specific adaptation happens at the boundary above or below it, not inside it.
5. The extraction removes a real current dependency on original-format semantics instead of introducing a speculative abstraction.
6. The module is already consumed through a format-agnostic interface, or the extraction removes a documented LBA2-specific dependency that was previously present in the checked-in call path.

If a module fails any one rule, it stays compatibility or mixed.

## Operating Consequences For Future Sessions

Future sessions should:

- continue parity work inside the current branch-B boundary
- keep fail-fast rejection for unsupported scene life
- classify modules honestly as compatibility, mixed, tools, or core
- prefer extracting a narrow neutral runtime seam over inventing a broad engine-wide abstraction
- use `port/src/runtime/session.zig` as the first concrete extraction target by removing direct `RoomSnapshot`-based initialization before claiming broader generic runtime ownership
- treat refactors as architecture progress only when they remove an actual LBA2-shaped dependency
- keep tool work first-class when it strengthens parity evidence, diagnostics, or validation

Future sessions should not:

- pause the active parity path to design a hypothetical second-game engine
- describe current mixed runtime files as already generic engine core
- generalize life/track semantics into engine APIs before evidence and a neutral boundary exist
- add save/load or scripting frameworks that are broader than the current validated runtime need
- create a second roadmap or phase model in this file

## Revisit Conditions

Revisit this decision only if one of the following becomes true:

- new checked-in primary-source evidence reopens branch B for `LM_DEFAULT` or `LM_END_SWITCH`
- the repo gains a second concrete runtime/content consumer in-tree
- at least one extracted runtime seam satisfies the promotion rules with no LBA2-shaped public API
- the roadmap phases or `current_focus` constraints change enough that this framing no longer matches execution reality

## Required Follow-On Updates

If this decision continues to matter, keep these docs aligned with it:

- `docs/LBA2_ZIG_PORT_PLAN.md`
- `port/README.md`
- `docs/codex_memory/subsystems/architecture.md`

Do not leave this file saying "extract engine seams when proven" while the roadmap and memory still describe the repo as a pure LBA2-port effort with no layer policy.
