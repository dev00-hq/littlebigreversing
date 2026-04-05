# Current Task

This LM collaboration follows [LM_TASKS/LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md).

## Gate

- Gate 2: deterministic repro setup

## Objective

Prepare one reproducible original-runtime entry path for the smallest decisive switch-family probe so Gate 3 can trace from `DoLife` without guesswork or scene-hunting churn.

## Collaboration Split

User first pass in the original game:

- prepare a reproducible path to the first probe target
- confirm how to identify the active owner in the debugger when the script tick runs
- verify the same script tick can be hit repeatedly without manual scene rediscovery

Codex follow-up after the first pass:

- keep the target set ordered by discriminating power
- turn your repro notes into the exact bounded Frida invocation plus the Gate 3 `x64dbg` breakpoint and logging sheet
- use the recovered Gate 1 addresses and offsets to define the smallest falsification trace

## Capture Checklist

Bring back these exact facts from the first pass:

- target scene and owner
- save file or exact steps to reach the target
- what in-game action causes the target life tick to run
- how to tell in the debugger that the owner is the intended one
- whether you can hit the same moment repeatedly after reload or a short loop

## Guardrails

- Start with the shortest decisive target: scene `5` hero.
- Keep the target set minimal and ordered: `5` hero, `11` object `12`, `11` object `18`, `2` hero, `44` only if needed.
- Use the repo-local bounded tracer for Gate 2 owner recognition and `PtrPrg` attribution before widening back into manual `x64dbg` work.
- Use original-runtime evidence first; `idajs` is only a last-mile setup aid if a natural repro is too noisy.
- Optimize for the smallest decisive findings, not exhaustive reverse engineering.
- Do not widen into runtime semantics claims yet; this gate is only about reliable entry to the trace.

## Acceptance

- we have one reproducible first probe target for scene `5` hero
- we know how to recognize the intended owner when `DoLife` runs
- the same script tick can be reached again without ad hoc exploration
- the next `x64dbg` trace can start from a known scene/owner pair without guessing
