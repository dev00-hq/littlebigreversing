# Frida Workflow For Gate 2

This note owns the bounded original-runtime proof path for the branch-A proof gate sprint.

It is not the repo's product plan, and it is not a generic Windows debugging guide.

## Scope

Current automation targets:

- original Windows `LBA2.EXE`
- `DoLife` entry `0x00420574`
- `DoLife` opcode-loop entry `0x004205BC`
- current `PtrPrg`, `TypeAnswer`, and `Value`
- per-object `PtrLife`, `OffsetLife`, and `ExeSwitch` cache
- `DoFuncLife` and `DoTest` entry observation on watched live paths
- live Tavern fingerprint validation at `PtrLife + 40`
- live scene-11 fingerprint validation at object `12` `PtrLife + 30`
- bounded screenshots keyed by host-minted event id
- one terminal verdict per lane

Current non-goals:

- widening the decoder or runtime boundary
- replacing the WinDbg MCP flow for Gate 3
- preserving stale live-save assumptions as compatibility defaults

## Canonical Structured Modes

### TavernTrace

- owner: hero object `0`
- fingerprint offset: `PtrLife + 40`
- fingerprint bytes:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- focus window:
  - `4780..4890`
- target:
  - `0x76 @ 4883`
- expected post-hit outcome:
  - `loop_reentry @ 4884`

### Scene11Pair

- fingerprint owner:
  - object `12`
- fingerprint offset:
  - `PtrLife + 30`
- fingerprint bytes:
  - `00 01 17 42 00 75 2D 00 74 17`
- primary target:
  - object `12`
  - `0x74 @ 38`
- comparison target:
  - object `18`
  - `0x76 @ 84`
- canonical staged save:
  - `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\scene11-pair.LBA`

The current presets in [trace_life.py](/D:/repos/reverse/littlebigreversing/tools/life_trace/trace_life.py) enforce those structured defaults.

## One-Time Setup

Canonical Frida source:

```powershell
D:\repos\reverse\frida
```

The tracer follows the local Frida skill contract:

- use the staged build from `D:\repos\reverse\frida\build\install-root\Program Files\Frida`
- do not rely on a user-site `pip install frida`
- prepend the staged `site-packages`, `bin`, and `lib\frida\x86_64` paths before importing `frida`

## Canonical Operator Runs

Attach to an already-running game:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode tavern-trace
py -3 .\tools\life_trace\trace_life.py --mode scene11-pair
```

Launch the canonical checked-in runtime under the tracer:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch
py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch
```

Use a fail-fast setup check first if needed:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 30
py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --timeout-sec 30
```

Leave the launched game alive for the debugger handoff only when that is the goal:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120 --keep-alive
py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --timeout-sec 120 --keep-alive
```

Passing `--launch` without a path defaults to the DLL-complete checked-in runtime under:

```text
work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE
```

In `tavern-trace` and `scene11-pair`, `--target-object`, `--target-opcode`, and `--target-offset` are rejected on purpose.

If the `frida-agent-cli` repo is elsewhere:

```powershell
py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --fra-repo-root D:\path\to\frida-agent-cli
```

If you need a non-structured bounded probe, use Basic mode instead:

```powershell
py -3 .\tools\life_trace\trace_life.py `
  --target-object 12 `
  --target-opcode 0x74 `
  --target-offset 38
```

## User Role During The Probe

### TavernTrace

1. load the canonical Tavern save
2. let the save settle before adding movement or extra interaction
3. stop once the tracer records the terminal Tavern verdict

### Scene11Pair

1. load the canonical scene-11 save
2. let it settle in the intended scene-11 state before extra interaction
3. keep the game responsive until the tracer records the fingerprint and the object-12/object-18 evidence pair

Important current fact:

- the staged `scene11-pair.LBA` launch path is wired, but a smoke run still timed out before the scene-11 fingerprint matched in [life-trace-20260407-011725.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260407-011725.jsonl)
- treat manual load-and-settle as required for `Scene11Pair` until a later proof run shows otherwise

## Output

The tracer writes JSONL under `work/life_trace/` and screenshots under `work/life_trace/shots/<run-id>/`.

Structured modes emit:

- `target_validation`
- `trace`
- `window_trace`
- `branch_trace`
- `screenshot`
- `screenshot_error`
- `do_life_return`
- `verdict`

`Scene11Pair` reuses the same event kinds and screenshot/verdict pattern as `TavernTrace`.

For scene-11 resolution events, the structured evidence bundle lands in `window_trace` or `do_life_return` with:

- `trace_role = primary`
- `trace_role = comparison`
- `ptr_prg_before`
- `byte_at_ptr_prg`
- `ptr_prg_after`
- `next_opcode`
- `post_hit_outcome`
- `working_type_answer_before` / `working_type_answer_after`
- `working_value_before` / `working_value_after`
- `exe_switch_before` / `exe_switch_after`
- `entered_do_func_life`
- `entered_do_test`

## Acceptance

### TavernTrace

- fingerprint match on hero object `0`
- bounded switch-window capture in `4780..4890`
- hero opcode fetch `0x76 @ 4883`
- explicit post-`0x76` `loop_reentry` at `4884`
- required screenshot set captured successfully
- terminal verdict `tavern_trace_complete`

### Scene11Pair

- scene-11 fingerprint match on object `12`
- one resolved primary hit for object `12` `0x74 @ 38`
- one resolved comparison hit for object `18` `0x76 @ 84`
- both hits capture the same before/after evidence bundle
- required screenshot set captured successfully
- terminal verdict `scene11_pair_complete`

## Follow-Up

If Gate 3 needs debugger attribution after a live proof lane is stable, hand the still-running process off to [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md).

Only extend the Frida tracer further if the WinDbg MCP pass proves that a missing hook is the narrowest blocker.
