# Gate 2 Repro Sheet

This companion note turns the Gate 2 objective into one concrete first-pass probe for the original Windows runtime.

Use it with:

- [LM_CURRENT_TASK.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_CURRENT_TASK.md)
- [LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md)
- [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)

## Numbering Rule

Gate 2 target names in this repo use raw `SCENE.HQR` entry indices, not the classic loader scene number and not community walkthrough labels.

- `SCENE.HQR[5]` is the first target.
- `inspect-life-program --scene-entry 5` reports `classic_loader_scene_number = 3`.
- Keep those number spaces separate while you debug.

## Primary Probe

Start with raw scene entry `5`, owner `hero`.

Verified current-state facts:

- checked-in scene-table excerpts label `SCENE.HQR[5]` as `Citadel Island, Tavern`
- `inspect-life-program --scene-entry 5 --json` reports:
  - `owner_kind = hero`
  - `life_byte_length = 61`
  - `decoded_byte_length = 46`
  - unsupported opcode `LM_END_SWITCH` (`0x76`) at byte offset `46`
- the shortest decisive byte window is:

```text
offset 40: 21 30 00 75 2E 00 76 23
offset 48: 0C 09 00 64 3B 00 1B 01
```

Why this is first:

- it is the shortest verified `LM_END_SWITCH` hit in current checked-in assets
- the owner is the hero, so owner recognition is simpler than an object-scoped fallback
- the unsupported byte lands early enough in the life blob that scene rediscovery churn should stay low once a Tavern save exists

## Owner Recognition

Use these checks in order.

### Check 1: `DoLife` owner argument

At `DoLife` entry `0x00420574`, the intended owner is the hero pass.

Source-backed rule:

- `DoLife(U8 numobj)` uses `ptrobj = &ListObjet[numobj]`
- `NUM_PERSO` is hard-defined as `0`

Practical debugger meaning:

- the hero hit is the call where `numobj == 0`
- if you inspect the entry argument directly, the intended hit is the one with low-byte value `0`

### Check 2: current-object base

The life interpreter uses:

- current object base = `0x0049A19C + obj * 0x21B`

So the hero pass should line up with:

- current object base = `0x0049A19C`
- hero `PtrLife` field address = `0x0049A38A`
- hero `OffsetLife` field address = `0x0049A38E`

### Check 3: current script pointer at the target tick

At the opcode-loop breakpoint `0x004205BC`:

- current script pointer / `PtrPrg` global = `0x004976D0`
- intended target tick is the hit where the next opcode byte is `0x76`
- for scene `5` hero, the target pointer should equal `hero PtrLife + 46`

The cleanest sanity checks are:

- `byte [PtrPrg] == 0x76`
- `PtrPrg - hero PtrLife == 46`
- the nearby bytes end the switch-family window as `... 75 2E 00 76 ...`

## Runtime Anchors

Keep these values visible while preparing the first pass.

- `DoLife` entry: `0x00420574`
- `DoLife` opcode-loop entry: `0x004205BC`
- `DoFuncLife`: `0x0041F0A8`
- `DoTest`: `0x0041FE30`
- `PtrPrg`: `0x004976D0`
- `TypeAnswer`: `0x004976D4`
- `Value`: `0x00497D44`
- `ExeSwitch.Func`: `current + 0x20E`
- `ExeSwitch.TypeAnswer`: `current + 0x20F`
- `ExeSwitch.Value`: `current + 0x210`

For the hero pass specifically:

- hero current object base: `0x0049A19C`
- hero `PtrLife` field: `0x0049A38A`
- hero `OffsetLife` field: `0x0049A38E`
- hero `ExeSwitch.Func` field: `0x0049A3AA`
- hero `ExeSwitch.TypeAnswer` field: `0x0049A3AB`
- hero `ExeSwitch.Value` field: `0x0049A3AC`

## First-Pass Procedure

The repo does not currently contain a checked-in save near the target, so the first pass should create one.

Prefer the bounded Frida probe for owner recognition and `PtrPrg` attribution before widening into WinDbg attribution. Keep the Frida run alive, then hand off to the configured `windbg` MCP server for Gate 3 once the repro loop is stable.

Recommended first pass:

1. Reach the Tavern in the original Windows runtime and create a save inside raw scene `5`.
2. Reload that save once to confirm it is a stable entry path to the same Tavern scene.
3. Run the bounded tracer first:

```powershell
pwsh -File scripts\trace-life.ps1 -Launch -TimeoutSeconds 30
```

4. Load the Tavern save and perform the smallest action that makes the intended hero tick run.
5. Confirm whether the tracer records the hero-owned `0x76` hit without ad hoc wandering.
6. Move to WinDbg MCP only after the save plus action loop is repeatable:

```powershell
open_windbg_remote(connection_string=...)
run_windbg_cmd(command="bp 0x004205BC")
run_windbg_cmd(command="g")
```

The key behavioral question for the first pass is not deep semantics yet. It is only:

- what simple in-game action is enough to make the intended hero tick run again

Acceptable answers include:

- load the save and let one frame run
- load the save and take one short step
- enter the Tavern from a fixed exterior save

## Capture Sheet

Bring back these exact facts after the first pass.

- target scene and owner:
  - expected first answer: `SCENE.HQR[5]`, `hero`
- save file name or exact reproducible steps to reach the Tavern:
  - `TODO`
- in-game action that causes the intended life tick to run:
  - `TODO`
- debugger evidence that the owner is the intended one:
  - expected baseline: `DoLife` hero pass (`numobj == 0`) and `PtrPrg - hero PtrLife == 46`
  - actual first-pass confirmation: `TODO`
- whether the same moment can be hit again after reload or a short loop:
  - `TODO`

## Fallback Targets

Do not widen unless the Tavern probe is noisy or blocked.

Ordered fallback set:

1. raw scene `11`, object `12`
2. raw scene `11`, object `18`
3. raw scene `2`, hero
4. raw scene `44` only if ambiguity remains

Verified fallback tuples:

- raw scene `11`, object `12`
  - checked-in scene-table excerpts label `SCENE.HQR[11]` as `Citadel Island, Neighbor house`
  - unsupported opcode `LM_DEFAULT` (`0x74`) at offset `38`
  - byte window:

```text
offset 24: 75 2D 00 73 26 00 00 01
offset 32: 17 42 00 75 2D 00 74 17
offset 40: 37 00 75 2D 00 76 0C 09
```

- raw scene `11`, object `18`
  - same scene as above
  - unsupported opcode `LM_END_SWITCH` (`0x76`) at offset `84`
  - byte window:

```text
offset 72: 54 00 73 54 00 00 04 3A
offset 80: 17 75 54 00 76 33 01 82
offset 88: 04 01 17 00 00 0F 64 00
```

- raw scene `2`, hero
  - unsupported opcode `LM_DEFAULT` (`0x74`) at offset `170`
  - byte window:

```text
offset 160: 00 A7 00 25 08 2E 02 75
offset 168: C8 00 74 0C 25 03 02 00
offset 176: 04 C5 00 0C 0F 01 00 00
```

## Stop Condition

Gate 2 is ready to hand off to Gate 3 once you can answer all of these for raw scene `5` hero:

- which save or route reaches the Tavern reproducibly
- which simple action causes the intended hero tick to run
- how you can recognize the hero-owned hit in the debugger without guessing
- whether the same hit comes back after reload or a short repeatable loop
