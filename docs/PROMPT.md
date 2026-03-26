# Next Step: Canonical Interior Pair Stitch

## Summary

`inspect-scene` and `inspect-background` are already live, asset-backed, and validated on the current workspace. The old prompt is stale because it still asks for the interior background decoder and CLI that now exist.

Life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, so the next bounded slice should stay on the viewer-prep path: compose the locked interior pair `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` into one explicit inspection surface without widening into rendering, exterior loading, or gameplay.

Keep the canonical data sources as `port/src/game_data/scene.zig` and `port/src/game_data/background.zig`. Do not introduce a new long-lived `game_data/room.zig` handoff layer just to stitch them together.

## Key Changes

- Add a narrow room-pair inspection surface in the tool layer.
  - Add `zig build tool -- inspect-room <scene-entry> <background-entry> [--json]`.
  - Use the existing `scene` and `background` public facades directly; keep any composition struct local to the tool or the immediate viewer-prep code.
  - Treat the two indices as explicit inputs for now. Do not invent a general scene-to-background mapping layer from incomplete evidence.

- Make the canonical interior pair executable as one metadata snapshot.
  - For the locked target, the acceptance path is `inspect-room 2 2`.
  - Emit the scene-side facts already proven by `inspect-scene` alongside the background-side facts already proven by `inspect-background`: scene kind, classic loader scene number, hero start, object/zone/track counts, background remapped cube index, `GRI`/`GRM`/`BLL` linkage, used-block summary, and `64 x 64` column-table metadata.
  - Fail fast if the requested scene is not an interior scene or if the requested background entry is invalid.

- Keep the slice strictly metadata-only.
  - Do not add SDL rendering, room rasterization, brick decoding, mask generation, or `GRM` redraw behavior in this slice.
  - Do not guess hero `BODY.HQR` / `ANIM.HQR` bindings from `SCENE.HQR[2]`.
  - Do not revisit scene-surface life integration; raw life bytes stay canonical until the switch-family blocker changes explicitly.

- Add regression coverage for the explicit pair stitch.
  - Add asset-backed tests that load `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]` together and assert the stitched output remains aligned with the current golden target.
  - Keep the existing standalone `inspect-scene` and `inspect-background` coverage intact; the new tests should prove composition, not replace the underlying subsystem tests.

## Test Plan

- `zig build test`
- `zig build tool -- inspect-room 2 2 --json`
- `zig build tool -- inspect-scene 2 --json`
- `zig build tool -- inspect-background 2 --json`

## Assumptions

- `docs/phase0/golden_targets.md` still locks the canonical interior pair as `SCENE.HQR[2]` plus `LBA_BKG.HQR[2]`.
- The current extracted asset tree and repo-local Windows SDL2 layout remain the environment boundary for validation on this machine.
- A general scene-to-background mapping surface is still out of scope until stronger checked-in evidence exists.
- `LM_DEFAULT` and `LM_END_SWITCH` remain blocked, so this slice stays off the life-script path.
