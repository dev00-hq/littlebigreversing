# Next Step: Fragment-Aware Interior Composition Debug View

## Summary

The height-aware interior composition debug view is already live, asset-backed, and validated on the current workspace. From `port/`, `zig build run -- --scene-entry 2 --background-entry 2` now loads the canonical pair through `port/src/app/viewer_shell.zig`, builds the viewer-local composition snapshot from `port/src/game_data/background.zig`, and renders relief, contour edges, and shape markers behind the existing hero, object, track, and zone overlays. The canonical `2/2` pair currently remains a zero-fragment / zero-fragment-zone boundary, so the next slice should treat fragment work as evidence-gathering rather than as already-present runtime behavior.

Life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, so the next bounded slice should stay on the viewer-prep path: keep the locked pair `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` as the canonical zero-fragment acceptance boundary, and only pursue viewer-local `GRM` fragment application evidence when a checked-in fragment-bearing interior pair supports it. Do not treat the locked `2/2` pair as implied proof that positive fragment rendering should already exist. If a positive fragment case is needed, identify it from checked-in probes first, then deepen evidence before widening runtime behavior. This is a narrow phase-3 interior viewer sub-slice, not a new architectural layer. Treat fragments as canonical background evidence and debug-view state, not as a reason to widen into gameplay, exterior loading, speculative actor binding, or a shared room layer. If checked-in fragment evidence is incomplete, stop and deepen evidence instead of inventing a fallback parser, shared room layer, compatibility path, or alternate runtime path.

Keep the canonical data sources as `port/src/game_data/scene.zig` and `port/src/game_data/background.zig`, with `port/src/app/viewer_shell.zig` as the runtime edge and `port/src/tools/cli.zig` as the probe surface. Keep any new fragment projection or render-state helpers local to the app/runtime edge. Do not introduce `port/src/game_data/room.zig` or any compatibility facade, and do not make the runtime depend on `inspect-room` or `inspect-background` as its implementation path.

## Key Changes

- Build on the landed composition and height-cue path instead of replacing it.
  - Keep the explicit runtime acceptance path as `cd port && zig build run -- --scene-entry 2 --background-entry 2`.
  - Reuse the existing decoded `GRI` cells, span metadata, `BLL` layouts, and the new viewer-local height cues as the baseline runtime inputs.
  - Promote only the minimum extra decoded facts needed for fragment-aware evidence, such as stable fragment coverage, target cells, or fragment-local mutation metadata for the canonical pair.

- Add fragment-aware debug cues only where the checked-in evidence supports them.
  - Keep `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` as the explicit zero-fragment / zero-fragment-zone boundary.
  - If a positive fragment case is required, identify a checked-in fragment-bearing interior pair first and promote only the minimum extra facts needed to show where that room can mutate without guessing gameplay semantics.
  - Favor deterministic overlays, delta tinting, fragment outlines, or mutation annotations over speculative full-art rendering.
  - Keep the result obviously pre-art and pre-gameplay: this is still a debug viewer, not a shipping renderer.

- Keep fragment decoding canonical and fragment presentation viewer-local.
  - Keep `game_data/background.zig` responsible for canonical background linkage and any newly added fragment facts, not SDL-facing presentation policy.
  - Build any new fragment projection state on top of the existing viewer-local composition snapshot path instead of inventing a parallel bootstrap.
  - Treat the preserved LBArchitect docs and CLI probes as cross-check surfaces, not runtime dependencies.

- Keep the slice strictly pre-full-art rasterization and pre-gameplay.
  - Do not decode or render brick pixel art from `BRK` entries yet.
  - Do not add actor visuals from `BODY.HQR`, `ANIM.HQR`, `FILE3D.HQR`, or sprite assets.
  - Do not revisit scene-surface life integration; raw life bytes stay canonical until the switch-family blocker changes explicitly.
  - Do not widen to exterior scene support or guessed scene/background pairing rules as part of this prompt.

- Add regression coverage for the fragment-aware boundary.
  - Keep the existing asset-backed background decoder tests, room inspection tests, `viewer_shell.zig` regression tests, and zero-fragment boundary assertions for the canonical `2/2` pair intact.
  - Add focused tests for any new fragment parsing helpers and for stable canonical fragment-derived facts or viewer-local delta helpers only after a fragment-bearing interior pair is locked by checked-in evidence.
  - Prefer deterministic structural assertions over screenshot goldens in this slice.

## Test Plan

Run the canonical validation commands from native PowerShell. If the Windows Zig/MSVC environment is not already loaded, run `.\scripts\dev-shell.ps1` from the repo root first, then `cd port`.

- `cd port && zig build test`
- `cd port && zig build tool -- inspect-background 2 --json`
  - Probe only: use this to cross-check canonical background facts, not as a runtime dependency.
- `cd port && zig build tool -- inspect-room 2 2 --json`
  - Probe only: use this to cross-check the paired interior metadata, including the current zero-fragment boundary, not as a runtime dependency.
- `cd port && zig build run -- --scene-entry 2 --background-entry 2`
  - Verify the window stays open until quit and continues to show the height-aware composition render; for the canonical `2/2` pair, fragment probes should still report zero fragment zones unless checked-in evidence changes.

## Assumptions

- `docs/phase0/golden_targets.md` still locks the canonical interior pair as `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`, and the current `2/2` probes still report zero fragment entries for that pair.
- The current extracted asset tree and repo-local Windows SDL2 layout remain the environment boundary for validation on this machine.
- The runtime should keep building on the landed viewer shell, height-aware composition debug render, and viewer-local snapshot path instead of replacing them with a new tool-driven or compatibility-path bootstrap.
- A shared `game_data/room.zig` layer is still out of scope until stronger checked-in evidence proves it is needed.
- `LM_DEFAULT` and `LM_END_SWITCH` remain blocked, so this slice stays off the life-script path.
