# Gate 2 Repro Sheet

This note captures the resolved Gate 2 repro facts for the live Tavern baseline.

It preserves the evidence that actually survived contact with the original runtime.

## Numbering Rule

Gate 2 names in this repo use raw `SCENE.HQR` entry indices, not classic loader scene numbers and not community walkthrough labels.

- `SCENE.HQR[5]` is the checked-in Tavern evidence surface.
- `inspect-life-program --scene-entry 5` reports `classic_loader_scene_number = 3`.
- Keep those number spaces separate.

## Two Evidence Layers

### Checked-in offline evidence

From `inspect-life-program --scene-entry 5 --json`:

- owner kind: `hero`
- life byte length: `61`
- decoded byte length: `46`
- unsupported opcode: `LM_END_SWITCH` (`0x76`) at byte offset `46`
- shortest decisive byte window:

```text
offset 40: 21 30 00 75 2E 00 76 23
offset 48: 0C 09 00 64 3B 00 1B 01
```

That evidence still matters for offline decoder work.

### Current live Tavern proof path

From the proved live Tavern save:

- owner: hero object `0`
- `OffsetLife = 47`
- fingerprint at `PtrLife + 40`:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- repeating hero window:
  - `0x71 @ 4780`
  - `0x73 @ 4783`
  - `0x75 @ 4805`
  - `0x76 @ 4883`
  - `0x37 @ 4884`
- terminal outcome:
  - `post_076_outcome = loop_reentry`
  - `result = tavern_trace_complete`

The live workflow is now centered on that proof path, not on the offline offset-`46` blob.

## Owner Recognition

Use these checks in order.

### Check 1: `DoLife` owner argument

At `DoLife` entry `0x00420574`, the intended owner is the hero pass.

Source-backed rule:

- `DoLife(U8 numobj)` uses `ptrobj = &ListObjet[numobj]`
- `NUM_PERSO` is hard-defined as `0`

Practical debugger meaning:

- the hero hit is the call where `numobj == 0`

### Check 2: current-object base

The life interpreter uses:

- current object base = `0x0049A19C + obj * 0x21B`

So the hero pass lines up with:

- current object base = `0x0049A19C`
- hero `PtrLife` field address = `0x0049A38A`
- hero `OffsetLife` field address = `0x0049A38E`

### Check 3: current script pointer on the live proof tick

At the opcode-loop breakpoint `0x004205BC`:

- current script pointer / `PtrPrg` global = `0x004976D0`
- the current live proof tick is the hit where:
  - `byte [PtrPrg] == 0x76`
  - `PtrPrg - PtrLife == 4883`
  - the bounded nearby bytes match the proved live window rather than the old offset-`46` blob

## Current Operator Procedure

1. Run the bounded tracer:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120
```

2. Load the same live Tavern save used for the proof artifacts.
3. Let the save settle before adding movement or talk input.
4. Confirm the fingerprint match at `PtrLife + 40`.
5. Confirm the proof path reaches `0x76 @ 4883` and `loop_reentry @ 4884`.
6. Only if Gate 3 attribution is the next goal, rerun with `--keep-alive` and hand off to [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md).

## Resolved Capture Sheet

- target scene and owner:
  - checked-in evidence surface: `SCENE.HQR[5]`, `hero`
  - current live proof owner: hero object `0`
- save name:
  - not checked into the repo
- repeatable trigger:
  - load the same live Tavern save and let it settle first
- debugger recognition:
  - `DoLife` hero pass
  - fingerprint match at `PtrLife + 40`
  - `PtrPrg - PtrLife == 4883`
  - `byte [PtrPrg] == 0x76`
- repeatability evidence:
  - [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl)
  - [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl)

## Historical Evidence Surfaces

Keep these as offline evidence targets, not as current live operator defaults:

1. raw scene `11`, object `12`
   - unsupported opcode `LM_DEFAULT` (`0x74`) at offset `38`
2. raw scene `11`, object `18`
   - unsupported opcode `LM_END_SWITCH` (`0x76`) at offset `84`
3. raw scene `2`, hero
   - unsupported opcode `LM_DEFAULT` (`0x74`) at offset `170`
4. raw scene `44`
   - only if a future prompt explicitly reopens that noisy path
