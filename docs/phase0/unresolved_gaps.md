# Unresolved Gaps

Phase 0 keeps these open as explicit evidence gaps instead of filling them with guesses.

## Current Gaps

- actor target: the player actor slot in `SCENE.HQR[2]` is fixed to slot `0`, but no direct hero body or animation entry is proven from the scene payload yet
- exterior numbering: the classic loader uses `LoadScene(numscene + 1)` while `inspect-scene` takes raw HQR entry indices; keep those two number spaces explicit and do not reintroduce the old `SCENE.HQR[4]` exterior misclassification
- scene-5 regression: `SCENE.HQR[5]` is useful for zone-semantics regression checks, but it is not part of the locked phase 0 golden target set yet
- dialog target: the English voice entry is locked, but the exact `TEXT.HQR` subtitle pairing remains provisional
- quest-state target: the house key and cellar transition are promoted, but the exact magic ball pickup mutation, Sendell portrait clue, dialogue/flag surface, and true New Game state equivalence are not yet part of the locked runtime contract

## Next Strategic Gate Inputs

Before widening from the validated viewer-prep runtime path into scene-surface life integration or gameplay work, the next gate should answer:

- which golden targets remain strong enough to keep unchanged
- which evidence facts are still provisional and need deeper tooling before runtime work
- which unresolved subsystem gaps would block the first implementation spec if left unresolved

If any of those answers change a golden target, the replacement must land with explicit evidence and a replan record.
