# Next Step: Viewer-Local Refinement Beyond the Landed Fragment-Focus Callout

## Summary

The height-aware interior composition debug view is already live, asset-backed, and validated on the current workspace. From `port/`, `zig build run -- --scene-entry 2 --background-entry 2` still loads the canonical zero-fragment interior pair through `port/src/app/viewer_shell.zig`, builds the viewer-local composition snapshot from `port/src/game_data/background.zig`, and renders relief, contour edges, shape markers, synthetic brick-index probe patterns, actual sparse `BRK`-backed swatch previews, and the existing hero/object/track/zone overlays. The repo also has a checked-in positive fragment evidence path: `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]` projects one runtime fragment zone from background-owned fragment data and is covered by asset-backed viewer and CLI regressions.

Life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, so the next bounded slice should stay on the viewer-prep path. Keep `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` as the canonical zero-fragment acceptance boundary, keep `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]` as the checked-in fragment-bearing interior evidence pair, and use that positive pair to drive the next viewer-local rendering step. The intended frontier is no longer first delivery of actual `BRK` swatches or the first fragment-focus callout layer, because those surfaces are already landed. The next step is to make the existing swatch-and-callout surface more inspectable for the checked-in fragment pair: richer selected-cell detail, deterministic composition-vs-fragment delta surfacing, a tighter comparison panel, or another equally narrow viewer-local refinement that makes the `11/10` evidence easier to inspect without widening into a room renderer.

Treat background fragment library facts and projected runtime fragment zones as separate surfaces. `port/src/game_data/background.zig` remains the canonical owner of decoded background linkage, composition, fragment-library facts, and the landed `BRK` swatch evidence. `port/src/app/viewer_shell.zig` remains the runtime edge that can project scene `grm` zones, compose viewer-local render state, and turn the checked-in evidence into debug-visible cues. Keep `port/src/tools/cli.zig` as the probe surface, not as the runtime implementation path. If checked-in raster or brick evidence is incomplete, stop and deepen evidence instead of inventing a fallback parser, compatibility path, guessed same-index pairing, or alternate runtime layer.

## Key Changes

- Build on the landed composition, fragment-zone, and `BRK` swatch path instead of replacing it.
  - Keep the explicit zero-fragment acceptance path as `cd port && zig build run -- --scene-entry 2 --background-entry 2`.
  - Keep the checked-in positive fragment evidence path as `cd port && zig build run -- --scene-entry 11 --background-entry 10`.
  - Reuse the existing decoded `GRI` cells, `BLL` layouts, fragment-library summaries, projected fragment zones, viewer-local height cues, landed brick-index probe overlays, and landed `BRK` swatch previews as the baseline runtime inputs.

- Use the right pair for the right kind of evidence.
  - Keep `2/2` as the explicit zero-fragment / zero-fragment-zone boundary.
  - Keep `11/10` as the explicit fragment-bearing interior pair; do not re-open pair discovery or guess same-index pairings.
  - Treat positive fragment behavior as already-evidenced at the metadata, viewer-projection, and swatch-preview level, but not yet as proof that full room-art rendering is ready.

- Add only the minimum viewer-local refinement needed beyond the landed fragment-focus callout layer for the checked-in fragment pair.
  - Treat the existing `drawBrickProbe` output, fixed-size actual swatches, and deterministic fragment-focus callout as completed evidence surfaces.
  - Prefer richer selected-cell detail, deterministic delta surfacing, or a tighter comparison panel over another new callout surface or more generic sparse sampling.
  - Promote only the minimum extra render-state or helper logic needed to make the checked-in pair's composition-versus-fragment differences easier to inspect from the already-decoded swatches.
  - Keep the result obviously pre-art and pre-gameplay: this is still a debug viewer and evidence path, not a production room renderer.

- Keep decoding canonical and presentation viewer-local.
  - Keep `game_data/background.zig` responsible for canonical background decoding and the landed `BRK` swatch evidence, not SDL-facing presentation policy.
  - Keep scene-bound projection and render-state helpers local to `viewer_shell.zig` unless a stronger stable seam becomes necessary.
  - Do not introduce `port/src/game_data/room.zig`, a compatibility facade, or a tool-driven runtime bootstrap.

- Keep the slice strictly interior-first and pre-gameplay.
  - Do not widen to exterior scene support, actor visuals, life binding, inventory/state mutation, or guessed room/background linking rules.
  - Do not treat `inspect-room`, `inspect-background`, or `inspect-scene` as runtime dependencies.
  - Do not add silent fallbacks when checked-in evidence is missing; fail fast and deepen probes instead.

- Add regression coverage for both boundaries.
  - Keep the current zero-fragment `2/2` assertions intact.
  - Keep the current positive `11/10` fragment-bearing assertions intact.
  - Add focused tests only for any new selected-cell detail helper, deterministic delta helper, comparison-panel helper, or viewer-local render-state derivation introduced by this slice.
  - Prefer deterministic structural assertions over screenshot goldens.

## Test Plan

Run the canonical validation commands from native PowerShell. If the Windows Zig/MSVC environment is not already loaded, run `.\scripts\dev-shell.ps1` from the repo root first, then `cd port`.

- `cd port && zig build test`
- `cd port && zig build tool -- inspect-background 2 --json`
  - Probe only: use this to cross-check the canonical zero-fragment background facts, not as a runtime dependency.
- `cd port && zig build tool -- inspect-background 10 --json`
  - Probe only: use this to cross-check the fragment-bearing background facts that feed the positive `11/10` room pair before promoting any `BRK`-backed preview surface.
- `cd port && zig build tool -- inspect-room 2 2 --json`
  - Probe only: use this to cross-check the paired zero-fragment interior metadata and keep the explicit zero-state boundary stable.
- `cd port && zig build tool -- inspect-room 11 10 --json`
  - Probe only: use this to cross-check the checked-in fragment-bearing interior pair, including the positive fragment-library counts and projected runtime fragment-zone surface.
- `cd port && zig build run -- --scene-entry 11 --background-entry 10`
  - Verify the window stays open until quit, the viewer still renders the landed height-aware composition path plus the existing synthetic brick probes, actual swatches, and fragment-focus callout, and the checked-in positive pair remains the runtime acceptance path for the new refinement.
- `cd port && zig build run -- --scene-entry 2 --background-entry 2`
  - Verify the zero-fragment boundary still reports no projected fragment zones and continues to act as the negative acceptance case.

## Assumptions

- `docs/phase0/golden_targets.md` still locks the canonical interior baseline as `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The checked-in fragment-bearing interior evidence pair remains `SCENE.HQR[11]` plus `LBA_BKG.HQR[10]`.
- The current extracted asset tree and repo-local Windows SDL2 layout remain the environment boundary for validation on this machine.
- The runtime should keep building on the landed viewer shell, viewer-local composition snapshot path, fragment-zone projection, and height-aware debug render instead of replacing them with a new bootstrap path.
- The current viewer brick patterns are still synthetic probes, but fixed-size actual `BRK` swatch previews and a deterministic fragment-focus callout are already landed beside them.
- A shared `game_data/room.zig` layer is still out of scope until stronger checked-in evidence proves it is needed.
- `LM_DEFAULT` and `LM_END_SWITCH` remain blocked, so this slice stays off the life-script path.
