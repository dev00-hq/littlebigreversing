# Unresolved Gaps

Phase 0 keeps these open as explicit evidence gaps instead of filling them with guesses.

## Current Gaps

- actor target: the player actor slot in `SCENE.HQR[2]` is fixed to slot `0`, but no direct hero body or animation entry is proven from the scene payload yet
- exterior target: `SCENE.HQR[4]` is locked, but the exact phase 1 scene-to-island asset linkage still needs a tighter evidence path into the relevant `.ILE` and `.OBL` payloads
- dialog target: the English voice entry is locked, but the exact `TEXT.HQR` subtitle pairing remains provisional

## Phase 1 Replan Gate Inputs

Before expanding past `Foundation + asset CLI`, the next gate should answer:

- which golden targets remain strong enough to keep unchanged
- which evidence facts are still provisional and need deeper tooling before runtime work
- which unresolved subsystem gaps would block the first implementation spec if left unresolved

If any of those answers change a golden target, the replacement must land with explicit evidence and a replan record.
