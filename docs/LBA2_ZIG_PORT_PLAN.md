# LBA2 Zig Port Plan

## Purpose

This document is the canonical implementation roadmap for the modern LBA2 port.

Use the classic source tree, extracted original CD assets, and preserved MBN tooling as behavioral and format evidence. Do not treat any one source as sufficient on its own, and do not directly transplant old engine code into the new runtime.

## Canonical Direction

- Target language/runtime: Zig 0.15.2 with SDL2
- Target platform: Windows-first native desktop runtime
- Product goal: high-parity reimplementation with one canonical codepath per subsystem
- Tooling goal: make discovery, inspection, validation, and fixture generation first-class deliverables

If a format or behavior is not yet understood, fail with a precise diagnostic and deepen evidence for that subsystem. Do not add fallback parsers, compatibility shims, or speculative dual behavior.

## Delivery Structure

Run discovery continuously through three explorer tracks:

1. Source explorer for classic engine module maps, entrypoints, globals, and subsystem ownership.
2. Asset explorer for canonical CD assets, file relationships, and reusable fixtures.
3. Evidence explorer for defendable format facts from the MBN workbench and preserved tools.

Start worker tracks only after explorer output is strong enough to support implementation:

1. Foundation worker for the Zig workspace, SDL2 shell, config/path handling, logging, and diagnostics.
2. Asset worker for HQR and related parsers, fixture generators, and inspection CLIs.
3. Runtime worker for scene loading, rendering, object/runtime behavior, scripts, audio/video, and save/load.

Use explicit replan gates after the foundation package, first viewer, first gameplay slice, and script milestone. Each gate should choose one of three outcomes: continue, deepen evidence, or split the subsystem into a narrower slice.

## Roadmap Phases

### Phase 0: Canonical Inputs and Evidence Baseline

- Freeze canonical runtime inputs to the extracted original CD data plus the preserved classic source tree.
- Keep checked-in findings in `docs/` and generated indexes, catalogs, fixtures, and comparisons in `work/`.
- Define golden targets covering one room, one exterior area, one actor, one dialog or voice path, and one cutscene path.

### Phase 1: Foundation and Asset CLI

- Replace the `hello-world` placeholder with the real Zig workspace layout.
- Stand up an SDL2-backed application shell with fail-fast asset-root and config handling.
- Add structured logging plus a basic debug UI or overlay hook.
- Build CLI tooling for asset inventory, HQR inspection, entry extraction, and fixture generation.
- Establish generated-state locations under `work/` for catalogs, decoded samples, and comparison outputs.

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

### Phase 3: World and Viewer Slice

- Load one interior room end-to-end: scene metadata, background or layout link, actor placement, camera framing, and debug visualization for zones and tracks.
- Add one exterior or island viewer path separately.
- Do not force indoor and outdoor pipelines to converge before the evidence is strong enough.
- Treat scene and object inspection as product features, not throwaway scripts.

### Phase 4: Runtime and Gameplay Slice

- Port the object model, update loop, zone handling, collision and movement, and track execution needed for one playable path.
- Implement life-script decoding and interpretation as a dedicated subsystem with tracing and deterministic stepping.
- Expand from one scripted slice to a small vertical slice with room transitions, inventory or state mutation, dialog or text, and basic combat or interaction.

### Phase 5: Completion Layers

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

## First Work Package

The first package is `Foundation + asset CLI`. It is intentionally narrower than the first scene viewer.

That package should leave the repo ready for the first implementation spec to cover:

- real Zig workspace bootstrap
- SDL2 application shell
- canonical asset-root discovery and config
- HQR base reader and inspection CLI
- machine-readable asset inventory and golden-fixture pipeline
- initial validation harness

Prepare the first implementation spec against this package boundary. Do not expand the spec to gameplay, scene viewing, or script work until the foundation package lands and the first replan gate is complete.

## Test Plan

### Foundation Tests

- `zig build` and `zig build test` pass for the workspace skeleton and SDL2 smoke path.
- Invalid asset roots and missing canonical files fail with explicit diagnostics.

### Asset Tests

- HQR header and table parsing match known fixture bytes.
- Selected entries from `RESS.HQR`, `SCENE.HQR`, `ANIM.HQR`, and `SPRITES.HQR` decode consistently across repeated runs.
- Asset inventory output is deterministic.

### Viewer and Runtime Tests

- One interior scene loads with the correct scene or background pairing and actor count.
- Zone and track metadata for the golden scene can be dumped and inspected.
- A scripted vertical-slice path can be replayed with stable state transitions.

### Evidence and Regression Tests

- Every promoted format fact used by code has at least one corresponding source, asset, or tool-backed fixture.
- New subsystem work adds fixtures before broad feature expansion.

## Assumptions and Defaults

- Use the classic source as behavioral reference, not as transplant code.
- Keep CLI and debug tooling inside the core deliverable, not as optional support work.
- Treat each milestone as re-plannable.
- If a subsystem is under-documented, increase evidence and tooling before increasing runtime surface area.
- Do not preserve compatibility with intermediate local layouts or experimental schemas unless a later task explicitly asks for it.
