# Actor Link Gap Memo

## Scope

This memo records the current phase 0 gap for the player actor target in `SCENE.HQR[2]`.

## Gap

Phase 0 locks these facts:

- the target scene is `SCENE.HQR[2]`
- the player actor slot is `NUM_PERSO == 0`
- the hero block is stored before the non-hero object list in the classic scene loader

Phase 0 does **not** yet lock a direct hero body entry or hero animation entry for that scene target.

Current evidence shows that hero body selection flows through runtime logic such as `ChoiceHeroBody` and `InitBody`, not through a phase 0-proof scene-level binding. That means a direct `SCENE.HQR[2] -> BODY.HQR[x] / ANIM.HQR[y]` statement would still be a guess.

## Human Verification

Human verification is **not currently required** to keep moving.

- It does not block the phase 0 baseline.
- It does not need a human sign-off just to preserve the gap as unresolved.
- It should be resolved with stronger tool-backed evidence if the post-viewer gameplay/life slice or later runtime work actually depends on the exact body or animation linkage.

## What Is Needed Instead

The next step is deeper evidence gathering, not manual approval:

- inspect the `SCENE.HQR[2]` hero block more directly
- correlate that data with classic loader behavior in `DISKFUNC.CPP` and runtime body selection in `OBJECT.CPP`
- only promote a body or animation link once it is supported by asset-level or source-level proof

## Decision

Treat this as an explicit evidence gap.

Do not invent a body or animation mapping for the player actor in `SCENE.HQR[2]`, and do not wait for human verification unless later work uncovers conflicting evidence that needs adjudication.
