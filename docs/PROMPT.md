# Next Step: Rendered Interior Debug View

## Summary

The data-backed interior viewer shell is already live, asset-backed, and validated on the current workspace. `zig build run -- --scene-entry 2 --background-entry 2` now loads the canonical pair through `port/src/app/viewer_shell.zig`, prints runtime diagnostics, and keeps the SDL window open until quit, so the old prompt is stale because it still asks for that completed shell slice.

Life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, so the next bounded slice should stay on the viewer-prep path: turn the blank metadata-backed window into a minimal rendered debug view for the locked pair `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` without widening into gameplay, exterior loading, speculative actor binding, or a new shared room layer.

Keep the canonical data sources as `port/src/game_data/scene.zig` and `port/src/game_data/background.zig`. Keep any composition or render-state helpers local to the app/runtime edge. Do not introduce `port/src/game_data/room.zig`, and do not make the runtime depend on `inspect-room` as its data path.

## Key Changes

- Replace the blank SDL shell with the first deterministic debug render.
  - Keep the explicit acceptance path as `zig build run -- --scene-entry 2 --background-entry 2`.
  - Continue loading the scene and background through the existing public facades, then render from the already-loaded runtime snapshot instead of from tool output.
  - Preserve the real quit-driven SDL loop and fail-fast startup diagnostics.

- Add a narrow viewer-local render snapshot for drawable facts that are already decoded.
  - Build from the existing room snapshot and promote only the minimum extra fields needed for rendering: hero start, object positions, track points, zone bounds, zone kinds, and the background column-table dimensions.
  - Keep this render-facing shape local to the app/runtime boundary instead of widening `game_data`.
  - Treat `inspect-room`, `inspect-scene`, and `inspect-background` as cross-check surfaces, not as runtime implementation dependencies.

- Render a simple interior schematic instead of real room art.
  - Draw a stable placeholder frame that makes the loaded metadata visible on screen for the canonical pair.
  - Use the `64 x 64` background column-table dimensions as the room-grid backdrop for the first debug view.
  - Overlay the scene-space facts already available today: hero start marker, object markers, track points, and zone bounds with type-distinct colors.
  - If a visual fit step is needed, derive it from the loaded room data in-process rather than inventing a general camera or scene-mapping layer.

- Keep the slice strictly pre-gameplay and pre-asset-rasterization.
  - Do not decode bricks, masks, or `GRM` redraw payloads in this slice.
  - Do not add actor visuals from `BODY.HQR`, `ANIM.HQR`, `FILE3D.HQR`, or sprite assets.
  - Do not revisit scene-surface life integration; raw life bytes stay canonical until the switch-family blocker changes explicitly.
  - Do not widen to exterior scenes or guess a general scene-to-background pairing rule from incomplete evidence.

- Add regression coverage for the first render-facing boundary.
  - Keep the existing asset-backed `viewer_shell` load tests intact.
  - Add focused tests for any new viewer-local projection or render-snapshot helpers so the canonical `2/2` schematic stays stable.
  - Prefer deterministic geometry/projection assertions over brittle pixel-golden screenshots in this slice.

## Test Plan

- `zig build test`
- `zig build tool -- inspect-room 2 2 --json`
- `zig build run -- --scene-entry 2 --background-entry 2`
  - Verify the window stays open until quit and now shows a rendered debug schematic rather than a blank shell.

## Assumptions

- `docs/phase0/golden_targets.md` still locks the canonical interior pair as `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The current extracted asset tree and repo-local Windows SDL2 layout remain the environment boundary for validation on this machine.
- The runtime should keep building on the landed viewer shell instead of replacing it with a new tool-driven or compatibility-path bootstrap.
- A shared `game_data/room.zig` layer is still out of scope until stronger checked-in evidence proves it is needed.
- `LM_DEFAULT` and `LM_END_SWITCH` remain blocked, so this slice stays off the life-script path.
