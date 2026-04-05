# Frida Workflow For Gate 2

This note owns the bounded original-runtime proof path for the live Tavern baseline.

It is not the repo's product plan, and it is not a generic Windows debugging guide.

## Scope

Current automation target:

- original Windows `LBA2.EXE`
- `DoLife` entry `0x00420574`
- `DoLife` opcode-loop entry `0x004205BC`
- `LM_SWITCH` / `LM_CASE` / `LM_OR_CASE` / `LM_BREAK` hooks from the recovered `DoLife` switch-family sites
- current `PtrPrg`, `TypeAnswer`, and `Value`
- per-object `PtrLife`, `OffsetLife`, and `ExeSwitch` cache
- live Tavern fingerprint validation at `PtrLife + 40`
- bounded Tavern screenshots keyed by host-minted event id
- one terminal Tavern verdict

Current non-goals:

- widening the decoder or runtime boundary
- replacing the WinDbg MCP flow for Gate 3
- preserving stale live-save assumptions as compatibility defaults

## Current Canonical Tavern Baseline

The operator-default TavernTrace target is the proved live save, not the earlier checked-in scene-5 blob.

Current live facts:

- owner: hero object `0`
- fingerprint offset: `PtrLife + 40`
- fingerprint bytes:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- bounded focus window:
  - `4780..4890`
- target fetch:
  - `0x76 @ 4883`
- bounded post-target outcome:
  - `0x37 @ 4884`
  - `post_076_outcome = loop_reentry`
- supporting evidence only:
  - `LM_BREAK @ 4805`
  - `computed_target_offset = 103`

The current TavernTrace preset in [trace_life.py](/D:/repos/reverse/littlebigreversing/tools/life_trace/trace_life.py) already enforces that baseline.

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
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace
```

Launch the canonical checked-in runtime under the tracer:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch
```

Use a fail-fast setup check first if needed:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 30
```

Use the more forgiving proven run when you want the full live proof:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120
```

Leave the launched game alive for the debugger handoff only when that is the goal:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120 -KeepAlive
```

That launch path defaults to the DLL-complete checked-in runtime under:

```text
work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE
```

In TavernTrace mode, `-TargetObject`, `-TargetOpcode`, and `-TargetOffset` are rejected on purpose.

If the staged Frida repo is elsewhere:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -FridaRepoRoot D:\path\to\frida
```

If you need a non-Tavern bounded probe, use Basic mode instead:

```powershell
pwsh -File scripts\trace-life.ps1 `
  -TargetObject 12 `
  -TargetOpcode 0x74 `
  -TargetOffset 38
```

## User Role During The Probe

The user only needs to:

1. load the same live Tavern save used for the proof path
2. let the save settle before adding movement or extra interaction
3. stop once the tracer records the terminal Tavern verdict

No manual register inspection is required.

## Output

The tracer writes JSONL under `work/life_trace/` and Tavern screenshots under `work/life_trace/shots/<run-id>/`.

TavernTrace emits:

- `target_validation`
- `window_trace`
- `branch_trace`
- `screenshot`
- `screenshot_error`
- `do_life_return`
- `verdict`

The canonical success path is:

- fingerprint match on hero object `0`
- bounded switch-window capture in `4780..4890`
- hero opcode fetch `0x76 @ 4883`
- explicit post-`0x76` `loop_reentry` at `4884`
- required screenshot set captured successfully
- terminal verdict `tavern_trace_complete`

## Historical Context That Still Matters

The earlier checked-in scene-5 hero blob is still useful offline evidence:

- it reaches unsupported `LM_END_SWITCH` at byte offset `46`
- it still matters for decoder audit and offline evidence review

It is not the current live Tavern operator default.

## Follow-Up

If Gate 3 needs debugger attribution after the live proof is stable, hand the still-running process off to [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md).

Only extend the Frida tracer further if the WinDbg MCP pass proves that a missing hook is the narrowest blocker.
