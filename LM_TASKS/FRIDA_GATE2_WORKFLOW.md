# Frida Workflow For Gate 2

This note replaces the manual "watch the CPU/registers in `x64dbg`" part of Gate 2 with a bounded runtime probe.

The user still drives the game to the right moment. The repo-local tracer handles the `DoLife` / `PtrPrg` inspection automatically.

## Scope

Current automation target:

- original Windows `LBA2.EXE`
- `DoLife` entry `0x00420574`
- `DoLife` opcode-loop entry `0x004205BC`
- current `PtrPrg`, `TypeAnswer`, `Value`
- per-object `PtrLife`, `OffsetLife`, and `ExeSwitch` cache

Current non-goals:

- full single-step replacement for `x64dbg`
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

These values are the defaults in `scripts/trace-life.ps1`.

## Run It

Attach to an already-running game:

```powershell
pwsh -File scripts\trace-life.ps1
```

Or launch the canonical checked-in Windows executable under the tracer:

```powershell
pwsh -File scripts\trace-life.ps1 -Launch
```

For a fail-fast bounded run while you validate the setup:

```powershell
pwsh -File scripts\trace-life.ps1 -Launch -TimeoutSeconds 30
```

That launch path defaults to the DLL-complete checked-in runtime under `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE`.

Spawned `LBA2.EXE` instances are now cleaned up by default when the tracer exits. Use `-KeepAlive` only when you intentionally want to leave the game running for manual follow-up after attach/resume.

If the staged Frida repo is somewhere else:

```powershell
pwsh -File scripts\trace-life.ps1 -FridaRepoRoot D:\path\to\frida
```

If you need a different bounded target:

```powershell
pwsh -File scripts\trace-life.ps1 `
  -TargetObject 12 `
  -TargetOpcode 0x74 `
  -TargetOffset 38
```

To capture every `DoLife` loop hit instead of only matching rows:

```powershell
pwsh -File scripts\trace-life.ps1 -LogAll -MaxHits 200
```

To keep the launched game alive after a successful or timed-out probe:

```powershell
pwsh -File scripts\trace-life.ps1 -Launch -KeepAlive
```

## User Role During The Probe

The user only needs to:

1. move the game to the target scene or save
2. perform the in-game action that causes the life tick
3. stop once the tracer records the bounded hit

No manual register inspection is required.

## Output

The tracer writes JSONL under `work/life_trace/`.

Each matching trace row includes:

- owner kind and object index
- current-object base
- `PtrLife`
- `OffsetLife`
- current `PtrPrg`
- `PtrPrg - PtrLife`
- opcode byte
- surrounding bytes around `PtrPrg`
- current `TypeAnswer`
- current `Value`
- cached `ExeSwitch` fields

That is enough to automate the old Gate 2 owner-recognition checks:

- hero hit: `object_index == 0`
- target opcode: `opcode_hex == 0x76`
- expected offset: `ptr_prg_offset == 46`

## Follow-Up

If Gate 3 needs more than bounded opcode-loop attribution, extend this tracer with additional hooks for:

- the `LM_SWITCH` write path
- `CASE` / `OR_CASE` jump assignment
- `BREAK` jump assignment
- any code that clears or overwrites the cached switch state
