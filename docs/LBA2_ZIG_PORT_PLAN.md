# LBA2 Zig Port Plan

## Purpose

This document is the canonical implementation roadmap for the modern LBA2 port.

Use the classic source tree, extracted original CD assets, and preserved MBN tooling as behavioral and format evidence. Do not treat any one source as sufficient on its own, and do not directly transplant old engine code into the new runtime.

## Document Ownership

- `DECISION_PLAN.md` owns long-term strategic framing and the promotion rules for calling code engine core rather than compatibility.
- `docs/LBA2_ZIG_PORT_PLAN.md` owns active roadmap phases, replan gates, and acceptance checks on the current execution path.
- `docs/codex_memory/current_focus.md` owns active repo state, current blockers, and the operating focus for the checked-in tree.
- `docs/PROMPT.md` owns only the next narrow slice to execute.
- `docs/PORTING_REPORT.md` plus the evidence memos remain supporting context, not execution owners.

## Canonical Direction

- Target language/runtime: Zig 0.15.2 with SDL2
- Target platform: Windows-first native desktop runtime
- Product goal: high-parity reimplementation with one canonical codepath per subsystem
- Tooling goal: make discovery, inspection, validation, and fixture generation first-class deliverables

Long-term framing and layer-boundary policy live in `DECISION_PLAN.md`. This roadmap stays parity-first on the checked-in execution path and should only claim extracted engine seams when they satisfy that document's promotion rules.

If a format or behavior is not yet understood, fail with a precise diagnostic and deepen evidence for that subsystem. Do not add fallback parsers, compatibility shims, or speculative dual behavior.

The hard-cut product policy applies throughout this roadmap: prefer one canonical current-state implementation, fail-fast diagnostics, and explicit recovery steps over compatibility bridges, silent fallbacks, migration glue, or temporary second paths.

## Current Strategic Status

- The old `Foundation + asset CLI` boundary is already behind the repo; that baseline has landed.
- The first-viewer gate is crossed. The checked-in port already has a runtime-backed interior viewer path, `BRK`-backed top-surface previews, viewer-local comparison and HUD surfaces, and a canonical Windows verification gate in `scripts/verify-viewer.ps1`; under the current branch-B boundary, `19/19` is the only supported positive guarded runtime/load pair, while `2/2`, `44/2`, and `11/10` are explicit guarded `ViewerUnsupportedSceneLife` rejections.
- The current implementation stream is viewer-prep evidence work on top of that validated runtime/viewer path, not another foundation/bootstrap slice.
- The remaining strategic blocker for widening from viewer-prep into scene-surface gameplay work is the life-script boundary around `LM_DEFAULT` and `LM_END_SWITCH`.

## Delivery Structure

Run discovery continuously through three explorer tracks:

1. Source explorer for classic engine module maps, entrypoints, globals, and subsystem ownership.
2. Asset explorer for canonical CD assets, file relationships, and reusable fixtures.
3. Evidence explorer for defendable format facts from the MBN workbench and preserved tools.

Start worker tracks only after explorer output is strong enough to support implementation:

1. Foundation worker for the Zig workspace, SDL2 shell, config/path handling, logging, and diagnostics.
2. Asset worker for HQR and related parsers, fixture generators, and inspection CLIs.
3. Runtime worker for scene loading, rendering, object/runtime behavior, scripts, audio/video, and save/load.

Use explicit replan gates after the evidence baseline, the first-viewer gate, the Phase 4 life-boundary decision, and the first gameplay slice. Each gate should choose one of three outcomes: continue, deepen evidence, or narrow the subsystem/product target explicitly.

## Roadmap Phases

### Phase 0: Canonical Inputs and Evidence Baseline

- Freeze canonical runtime inputs to the extracted original CD data plus the preserved classic source tree.
- Keep checked-in findings in `docs/` and generated indexes, catalogs, fixtures, and comparisons in `work/`.
- Define golden targets covering one room, one exterior area, one actor, one dialog or voice path, and one cutscene path.

### Phase 1: Foundation, Asset CLI, and Runtime Skeleton

- Land the real Zig workspace layout, SDL2-backed application shell, fail-fast asset-root/config handling, and the core inspection CLI/tooling baseline.
- Keep future work here limited to supporting later gates; do not reopen this phase as the current execution boundary.

### Phase 2: Core Asset Decoding

- Implement canonical readers for HQR primitives first.
- Prioritize the minimum dependent formats needed for viewing content:
  - `SCENE.HQR`
  - `LBA_BKG.HQR`
  - `RESS.HQR`
  - `BODY.HQR`
  - `ANIM.HQR`
  - `SPRITES.HQR`
- Add enough text and voice metadata decoding to unblock later gameplay work.
- Cross-check decoded outputs against source, assets, and preserved tools instead of trusting any single input.
- Treat the current checked-in decode surface as already sufficient for the validated interior viewer/evidence path; future decode work should follow later gates rather than reintroducing a pre-viewer package boundary.

### Phase 3: Viewer-Prep Evidence on a Validated Runtime Path

- Status: crossed.
- Keep the runtime-backed interior viewer path on Windows validated through `scripts/verify-viewer.ps1`, with `SCENE.HQR[19]` plus `LBA_BKG.HQR[19]` as the only supported positive guarded runtime/load baseline.
- Keep `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`, `SCENE.HQR[44]` plus `LBA_BKG.HQR[2]`, and `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]` as explicit guarded negative `inspect-room` / viewer-load cases under branch B.
- Preserve `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]` as the checked-in fragment-bearing evidence pair only on explicit test-only unchecked paths, not as a supported guarded runtime fixture.
- Treat viewer-local composition snapshots, `BRK`-backed previews, fragment comparison, HUD/legend cues, and provenance overlays as evidence surfaces on top of a landed runtime path, not as proof that the repo is still pre-viewer.
- Keep indoor and outdoor expansion decoupled until the evidence warrants widening the target.

### Phase 4: Life Boundary Decision Gate

- Before scene-surface life integration or gameplay work widens further, make an explicit product-boundary decision for `LM_DEFAULT` and `LM_END_SWITCH`.
- Allowed branch A: deepen checked-in evidence until those switch-family opcodes can be supported in one canonical decoder/interpreter path.
- Allowed branch B: explicitly reject switch-family-dependent life paths from the current parity target and keep the runtime fail-fast when those paths are encountered.
- Current checked-in decision: branch B. `LM_DEFAULT` and `LM_END_SWITCH` remain outside the supported decoder/interpreter boundary because the repo still lacks checked-in primary-source structural proof beyond header names and the `LM_BREAK` destination comment.
- Do not add speculative partial support, compatibility glue, silent fallbacks, or a temporary second life path while this gate is unresolved.
- Keep offline life-oriented probes, audits, and source-backed evidence work in scope; only scene-surface life integration is blocked here.

### Phase 5: Runtime and Gameplay Slice

- After Phase 4 resolves, port the object model, update loop, zone handling, collision and movement, and track execution needed for one playable path.
- If Phase 4 takes branch A, implement life-script decoding and interpretation with tracing and deterministic stepping on the supported boundary.
- If Phase 4 takes branch B, keep rejected switch-family paths outside the parity target with explicit diagnostics and continue only on gameplay slices that stay inside the chosen product boundary.
- Expand from one scripted slice to a small vertical slice with room transitions, inventory or state mutation, dialog or text, and basic combat or interaction.

### Phase 6: Completion Layers

- Add audio playback, voice routing, music behavior, menus, save or load, cutscenes, and remaining media subsystems.
- Expand parity coverage scene-by-scene and subsystem-by-subsystem until campaign-complete behavior is realistic.
- Only consider controlled modernization work after stable parity.

## Stable Module Boundaries

Organize the Zig project around a small set of stable modules:

- `platform`: SDL2 windowing, timing, input, audio hooks, and filesystem abstraction
- `assets`: HQR and container primitives, typed decoders, asset catalog, and fixture emitters
- `game_data`: scene, room or background, actor, zone, track, animation, text, and voice metadata models
- `runtime`: renderer, scene or world state, object update loop, script interpreter, and save or load state
- `tools`: CLI inspectors, validators, scene dumpers, and comparison runners

Expose a small set of first-class commands early:

- inventory assets
- inspect or decode asset entries
- dump scene metadata
- run a viewer for a chosen scene
- run validation against golden fixtures

## Current Strategic Gate

- The first-viewer gate is already complete; do not reframe the repo as if it were still waiting for a foundation/bootstrap package.
- The current strategic gate outcome is Phase 4 branch B for `LM_DEFAULT` and `LM_END_SWITCH`.
- Keep scene-surface life integration and any future life execution fail-fast on those switch-family-dependent paths unless new checked-in primary-source evidence reopens the decision.

## Test Plan

### Foundation and Decode Tests

- `zig build` and `zig build test` pass for the checked-in workspace and decode/runtime baseline.
- Invalid asset roots and missing canonical files fail with explicit diagnostics.
- HQR header and table parsing match known fixture bytes.
- Selected entries from `RESS.HQR`, `SCENE.HQR`, `ANIM.HQR`, and `SPRITES.HQR` decode consistently across repeated runs.
- Asset inventory output is deterministic.

### Viewer Gate Tests

- `scripts/verify-viewer.ps1` is the canonical Windows acceptance gate for the landed viewer/runtime path.
- `SCENE.HQR[19]` plus `LBA_BKG.HQR[19]` is the only positive guarded runtime/load launch and `inspect-room` success case.
- `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`, `SCENE.HQR[44]` plus `LBA_BKG.HQR[2]`, and `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]` remain explicit guarded `ViewerUnsupportedSceneLife` rejection cases for `inspect-room`.
- Fragment-bearing `11/10` evidence stays covered on explicit test-only unchecked loader paths, not through the canonical guarded CLI/runtime seam.
- Viewer-local evidence surfaces stay covered by deterministic tests and the explicit Windows runtime launches.

### Life Boundary Tests

- `zig build tool -- audit-life-programs --json` and `zig build tool -- audit-life-programs --json --all-scene-entries` remain the canonical blocker reports until Phase 4 resolves.
- If Phase 4 takes branch A, add decoder/interpreter tests that prove supported handling for `LM_DEFAULT` and `LM_END_SWITCH`.
- Phase 4 currently takes branch B, so keep explicit rejection tests and diagnostics for switch-family-dependent paths outside the target boundary.

### Evidence and Regression Tests

- Every promoted format fact used by code has at least one corresponding source, asset, or tool-backed fixture.
- New subsystem work adds fixtures before broad feature expansion.

## Assumptions and Defaults

- Use the classic source as behavioral reference, not as transplant code.
- Keep CLI and debug tooling inside the core deliverable, not as optional support work.
- Treat each milestone as re-plannable.
- If a subsystem is under-documented, increase evidence and tooling before increasing runtime surface area.
- Do not preserve compatibility with intermediate local layouts or experimental schemas unless a later task explicitly asks for it.
