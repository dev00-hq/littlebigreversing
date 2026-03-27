# Next Step: Data-Backed Interior Viewer Shell

## Summary

`inspect-scene`, `inspect-background`, and `inspect-room` are already live, asset-backed, and validated on the current workspace. The old prompt is stale because it still asks for the room-pair stitch that now exists in the tool layer.

Life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, so the next bounded slice should stay on the viewer-prep path: replace the SDL smoke app with a data-backed interior viewer shell for the locked pair `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` without widening into gameplay, exterior loading, or speculative runtime binding.

Keep the canonical data sources as `port/src/game_data/scene.zig` and `port/src/game_data/background.zig`. Do not introduce a new long-lived `game_data/room.zig` handoff layer, and do not make the runtime depend on the tool CLI as its data path.

## Key Changes

- Replace the smoke-app startup path with a data-backed interior load.
  - Extend `zig build run -- --scene-entry <scene-entry> --background-entry <background-entry>`.
  - Keep the acceptance path explicit as `zig build run -- --scene-entry 2 --background-entry 2`; do not invent a general scene-to-background mapping layer from incomplete evidence.
  - Load the scene and background through the existing public facades, then fail fast if the requested scene is not interior or if the background entry is invalid.

- Add a narrow viewer-local room snapshot for the canonical pair.
  - Keep any composition struct local to the app or immediate viewer-prep code instead of promoting a new shared `game_data` surface.
  - Treat `inspect-room` as an already-implemented baseline and cross-check, not as the runtime implementation itself.
  - Surface the loaded facts already proven by the inspectors in startup diagnostics and the window title: scene kind, classic loader scene number, hero start, object/zone/track counts, background remapped cube index, `GRI`/`GRM`/`BLL` linkage, used-block summary, and `64 x 64` column-table metadata.

- Replace the one-shot delay with a minimal viewer shell.
  - Keep the SDL window open with a real quit path instead of a timed smoke-window exit.
  - It is acceptable for the visual output to remain placeholder-only in this slice; the goal is to prove that the runtime boots against real room metadata rather than a blind SDL smoke test.
  - Keep the runtime surface narrow and fail-fast if canonical assets are missing or unsupported.

- Keep the slice strictly pre-render and pre-gameplay.
  - Do not add room rasterization, brick decoding, mask generation, actor visuals, camera controls, or `GRM` redraw behavior in this slice.
  - Do not guess hero `BODY.HQR` / `ANIM.HQR` bindings from `SCENE.HQR[2]`.
  - Do not revisit scene-surface life integration; raw life bytes stay canonical until the switch-family blocker changes explicitly.

- Add regression coverage for the runtime-backed load boundary.
  - Add asset-backed tests for the new viewer-local load helper so `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` remain aligned with the current golden target when loaded for the app path.
  - Keep the existing standalone `inspect-scene`, `inspect-background`, and `inspect-room` coverage intact; the new tests should prove the runtime entry boundary, not replace the underlying subsystem tests.

## Test Plan

- `zig build test`
- `zig build run -- --scene-entry 2 --background-entry 2`
- `zig build tool -- inspect-room 2 2 --json`

## Assumptions

- `docs/phase0/golden_targets.md` still locks the canonical interior pair as `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The current extracted asset tree and repo-local Windows SDL2 layout remain the environment boundary for validation on this machine.
- `inspect-room` remains the baseline composition surface, but the runtime must load scene and background metadata through the canonical facades rather than shelling out to the tool.
- A general scene-to-background mapping surface is still out of scope until stronger checked-in evidence exists.
- `LM_DEFAULT` and `LM_END_SWITCH` remain blocked, so this slice stays off the life-script path.
