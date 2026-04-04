# `DoLife` Static Dispatch Verification Report

## Scope

This report captures the Gate 1 `Ghidra` findings for the original Windows `LBA2.EXE` runtime and the follow-up adversarial verification passes run against those findings.

Target binary:

- `D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2.EXE`

Primary question:

- recover the original `DoLife` dispatch
- recover `DoFuncLife` and `DoTest`
- determine whether `0x74` (`LM_DEFAULT`) and `0x76` (`LM_END_SWITCH`) have explicit dispatch cases
- recover where the current object, `PtrLife`, current script pointer, and switch-cache state live

## Method

Static analysis used:

- headless `Ghidra` import and decompilation of `LBA2.EXE`
- focused function recovery for the interpreter and helper pair
- adversarial re-checks using three independent `$critical-sparring` subagent passes
- extra xref sweeps to challenge the claim that the recovered globals uniquely identify the life interpreter

Primary evidence artifacts:

- [DoLife_00420574_full.txt](/D:/repos/reverse/littlebigreversing/work/ghidra_projects/DoLife_00420574_full.txt)
- [DoFuncLife_0041F0A8_full.txt](/D:/repos/reverse/littlebigreversing/work/ghidra_projects/DoFuncLife_0041F0A8_full.txt)
- [DoTest_0041FE30_full.txt](/D:/repos/reverse/littlebigreversing/work/ghidra_projects/DoTest_0041FE30_full.txt)
- [xrefcheck.txt](/D:/repos/reverse/littlebigreversing/work/agent_reports/xrefcheck.txt)
- [extra_funcs.txt](/D:/repos/reverse/littlebigreversing/work/agent_reports/extra_funcs.txt)

## Verified Findings

### Interpreter and helper addresses

- `DoLife` dispatch function: `0x00420574`
- `DoLife` opcode switch loop entry: `0x004205BC`
- `DoFuncLife`: `0x0041F0A8`
- `DoTest`: `0x0041FE30`

Why these addresses are accepted:

- `0x00420574` computes `obj * 0x21B`, derives the current object from the object array, initializes the current script pointer from `PtrLife + OffsetLife`, and dispatches on `*PtrPrg++`
- `0x0041F0A8` consumes the current script pointer, resets the working type, switches on a nested function byte, and writes the computed value into the working compare/value slot
- `0x0041FE30` consumes the current script pointer, switches on the working type, and compares against the working compare/value slot

### `0x74` and `0x76` dispatch status

Verified from the recovered `DoLife` switch:

- `0x74` has no explicit `case`
- `0x76` has no explicit `case`

The recovered region shows:

- `case 0x73`
- `case 0x75`
- `case 0x77`

with no `case 0x74` or `case 0x76` in between.

### Current object and life-script state

The life interpreter addresses the current object record as:

- `0x0049A19C + obj * 0x21B`

Recovered storage used by the interpreter:

- life-interpreter current object record: `0x0049A19C + obj * 0x21B`
- `PtrLife`: `current + 0x1EE`
- absolute `PtrLife` field address: `0x0049A38A + obj * 0x21B`
- `OffsetLife`: `current + 0x1F2`
- absolute `OffsetLife` field address: `0x0049A38E + obj * 0x21B`
- current script pointer / `PtrPrg`: global `0x004976D0`
- working type / `TypeAnswer`: global `0x004976D4`
- working compare/value scratch / `Value`: global `0x00497D44`

### Switch-cache storage

Recovered per-object switch cache fields:

- cached switch selector / function id: `current + 0x20E`
- absolute selector field address: `0x0049A3AA + obj * 0x21B`
- cached switch type: `current + 0x20F`
- absolute type field address: `0x0049A3AB + obj * 0x21B`
- cached switch value: `current + 0x210`
- absolute value field address: `0x0049A3AC + obj * 0x21B`

These fields are written by the recovered `LM_SWITCH` path and read back by the recovered `LM_CASE` / `LM_OR_CASE` paths.

## Adversarial Verification Outcome

Three independent `$critical-sparring` subagent passes challenged the original claims.

Converged conclusions:

- the three function addresses are supported
- the `PtrLife`, `OffsetLife`, `PtrPrg`, `TypeAnswer`, `Value`, and `ExeSwitch` field locations are supported
- `0x74` and `0x76` are absent from the recovered `DoLife` switch

Useful corrections from the red-team passes:

- say `life-interpreter current-object base` instead of `canonical whole-program object-struct base`
- say "`0x74` and `0x76` have no explicit cases in recovered `DoLife`" instead of "`0x74` and `0x76` have no explicit handler anywhere in the runtime"

## Important Caveats

### Caveat 1: object-base wording

The static proof is strong that the life interpreter uses:

- `0x0049A19C + obj * 0x21B`

as the operational current-object record base.

What is not fully proven from this slice alone:

- that `0x0049A19C` is the absolute earliest byte of the whole `T_OBJET` layout used everywhere else in the program

This caveat does not weaken the recovered life offsets above.

### Caveat 2: `0x74` / `0x76` claim scope

The static proof is strong that:

- `0x74` and `0x76` have no explicit cases in recovered `DoLife`
- the red-team xref sweep found no alternate handler that obviously invalidates that conclusion

What is not fully proven by this static pass alone:

- that no secondary runtime path anywhere in the original executable can ever treat `0x74` or `0x76` specially

The current claim should therefore stay narrower than total runtime absence.

## Extra Xref Results

The adversarial xref sweep found extra functions touching the same globals:

- `0x004201A0`
- `0x004237E0`

Why they do not currently break the report:

- `0x004201A0` switches on an object state field and uses `PtrPrg` as input, but it is not the recovered main life opcode dispatcher
- `0x004237E0` appears to be a different interpreter family and does not expose a hidden `0x74` / `0x76` path in the recovered life-dispatch region

These functions are relevant as caution against overclaiming uniqueness from globals alone, not as counterevidence to the main address findings.

## Decision-Clean Summary

Strongly supported for debugger setup:

- `DoLife = 0x00420574`
- `DoFuncLife = 0x0041F0A8`
- `DoTest = 0x0041FE30`
- `PtrPrg = 0x004976D0`
- `TypeAnswer = 0x004976D4`
- `Value = 0x00497D44`
- `PtrLife = current + 0x1EE`
- `OffsetLife = current + 0x1F2`
- `ExeSwitch.Func = current + 0x20E`
- `ExeSwitch.TypeAnswer = current + 0x20F`
- `ExeSwitch.Value = current + 0x210`
- `0x74` and `0x76` are missing from recovered `DoLife`

Wording that should be preserved:

- "`0x74` and `0x76` have no explicit cases in recovered `DoLife`"
- "`0x0049A19C + obj * 0x21B` is the life-interpreter current-object record base"

Wording that should be avoided:

- "`0x74` and `0x76` have no explicit handler anywhere in reality"
- "`0x0049A19C` is the canonical whole-program object-struct base"

## Recommended Next Step

Do one dynamic falsification pass in `x64dbg`:

- break at `0x004205BC`
- use a scene/object known to contain `0x74` or `0x76`
- log the current opcode byte from `0x004976D0`
- confirm whether execution ever lands on `0x74` or `0x76`
- if it does, single-step to see whether bytes are consumed or a hidden branch target handles them

That is the smallest next probe that can materially reduce the remaining uncertainty.
