# Current Task

This LM collaboration follows [LM_TASKS/LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md).

## Gate

- Gate 1: static dispatch proof in `Ghidra`

## Objective

Get the minimum original-runtime structural evidence needed to decide whether `LM_DEFAULT` (`0x74`) and `LM_END_SWITCH` (`0x76`) require decoder recognition before we touch the Zig decoder boundary.

## Collaboration Split

User first pass in `Ghidra`:

- locate the original `DoLife` dispatch
- locate `DoFuncLife` and `DoTest`
- identify whether `0x74` and `0x76` have explicit dispatch cases
- find the current-object field/path, `PtrLife`, the current script pointer or offset, and the cached switch value/type storage

Codex follow-up after the first pass:

- map your findings against the checked-in opcode grammar and real-asset blocker set
- turn the addresses/offsets into a debugger probe sheet for Gate 2 and Gate 3
- keep the next questions falsification-oriented instead of widening scope

## Capture Checklist

Bring back these exact facts from the first pass:

- dispatch function address
- `DoFuncLife` address
- `DoTest` address
- whether `0x74` has an explicit handler or case target
- whether `0x76` has an explicit handler or case target
- address or struct offset for current object ownership
- address or struct offset for `PtrLife`
- address or struct offset for the current script pointer or program counter
- address or struct offset for cached switch value
- address or struct offset for cached switch type or state discriminator

## Guardrails

- Keep this gate decoder-proof only; do not assume runtime semantics from names or comments.
- Use original-runtime evidence first; `lba2remake` remains hypothesis material only.
- Optimize for the smallest decisive findings, not exhaustive reverse engineering.
- Do not reopen the Zig decoder boundary until byte width and control-flow role are evidenced.

## Acceptance

- we have one unambiguous dispatch site to trace from
- we know whether `0x74` and `0x76` are explicit dispatch cases
- we know where the active object, life base pointer, current script pointer, and switch cache live
- the next `x64dbg` probe can be defined without guessing
