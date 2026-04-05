# Frida Workflow For Gate 2

This note replaces the manual "watch the CPU/registers in a GUI debugger" part of Gate 2 with a bounded runtime probe.

The user still drives the game to the right moment. The repo-local tracer handles the `DoLife` / `PtrPrg` inspection, Tavern gating, screenshot capture, and terminal verdict automatically.

## Scope

Current automation target:

- original Windows `LBA2.EXE`
- `DoLife` entry `0x00420574`
- `DoLife` opcode-loop entry `0x004205BC`
- `LM_SWITCH` / `LM_CASE` / `LM_OR_CASE` / `LM_BREAK` branch hooks from the recovered `DoLife` switch sites
- current `PtrPrg`, `TypeAnswer`, `Value`
- per-object `PtrLife`, `OffsetLife`, and `ExeSwitch` cache
- Tavern fingerprint validation at `PtrLife + 40`
- bounded Tavern screenshots correlated by tracer-minted event id
- one terminal Tavern verdict

Current non-goals:

- full Gate 3 WinDbg attribution
- generic Windows debugging for unrelated subsystems
- proof of `CASE` / `OR_CASE` / `BREAK` jump-target semantics beyond the bounded capture below

## One-Time Setup

Canonical Frida source:

```powershell
D:\repos\reverse\frida
```

The repo-local tracer now follows the local Frida skill contract:

- use the staged build from `D:\repos\reverse\frida\build\install-root\Program Files\Frida`
- do not rely on a user-site `pip install frida`
- prepend the staged `site-packages`, `bin`, and `lib\frida\x86_64` paths before importing `frida`

## Canonical First Probe

The first automated probe still matches the existing Gate 2 target:

- raw scene entry `5`
- owner `hero`
- expected opcode `0x76`
- expected `PtrPrg - PtrLife == 46`

These values are the Tavern defaults behind `scripts/trace-life.ps1 -Mode TavernTrace`.

## Run It

Attach to an already-running game:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace
```

Or launch the canonical checked-in Windows executable under the tracer:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch
```

For a fail-fast bounded run while you validate the setup:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 30
```

That launch path defaults to the DLL-complete checked-in runtime under `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE`.

Spawned `LBA2.EXE` instances are now cleaned up by default when the tracer exits. Use `-KeepAlive` only when you intentionally want to leave the game running for manual follow-up after attach/resume.
In TavernTrace mode, `-TargetObject`, `-TargetOpcode`, and `-TargetOffset` are rejected because the mode is intentionally Tavern-specific.

If the staged Frida repo is somewhere else:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -FridaRepoRoot D:\path\to\frida
```

If you need a different bounded target, stay in the generic mode:

```powershell
pwsh -File scripts\trace-life.ps1 `
  -TargetObject 12 `
  -TargetOpcode 0x74 `
  -TargetOffset 38
```

To capture every `DoLife` loop hit instead of only matching rows:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -LogAll
```

To keep the launched game alive after a successful or timed-out probe:

```powershell
pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -KeepAlive
```

## User Role During The Probe

The user only needs to:

1. move the game to the target scene or save
2. perform the in-game action that causes the life tick
3. stop once the tracer records the Tavern verdict

No manual register inspection is required.

## Output

The tracer writes JSONL under `work/life_trace/` and Tavern screenshots under `work/life_trace/shots/<run-id>/`.

TavernTrace now emits:

- `target_validation`
- `window_trace`
- `branch_trace`
- `screenshot`
- `screenshot_error`
- `do_life_return`
- `verdict`

The canonical success path is:

- fingerprint match on hero object `0`
- `LM_BREAK` at offset `43` targeting offset `46`
- hero opcode fetch `0x76` at offset `46`
- explicit post-`0x76` outcome
- four bounded screenshots, each keyed by the same event id as the proof event it documents
- terminal verdict `tavern_trace_complete`

## Follow-Up

If Gate 3 needs more than bounded opcode-loop attribution, hand the live process off to [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md) and keep this tracer scoped to bounded repro proof. Only extend the tracer further if the WinDbg MCP pass proves that a missing Frida hook is the narrowest blocker.

If a later prompt still needs more Frida-side detail, extend this tracer with additional hooks for:

- the `LM_SWITCH` write path
- `CASE` / `OR_CASE` jump assignment
- `BREAK` jump assignment
- any code that clears or overwrites the cached switch state
