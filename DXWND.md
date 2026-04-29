# DxWnd LBA2 hang investigation

Date: 2026-04-28

Status: operationally solved, not causally proven.

The current working DxWnd profile is the `no_aeroboost` variant derived from
`tools/life_trace/profiles/lba2_built_in_flag_core_candidate.dxw`. It differs
from the previous candidate only by clearing bit `0x80` from `flagj0`:

```ini
flagj0=4096
```

The failed candidate used:

```ini
flagj0=4224
```

Everything else in the controlled run was kept the same, including
`tflag0=6211`, `winver0=0`, and the direct-save launch path.

## Problem

LBA2 would start successfully through DxWnd and run for a while, then the game
window would hang. The hang looked like a gameplay/save issue at first because
it happened during active testing, but live process evidence showed a Windows
graphics-wrapper failure pattern instead:

- `LBA2.EXE` stopped responding.
- `dxwnd.exe` stayed responsive.
- The process remained alive, so this was a deadlock/hang rather than an
  immediate crash.
- The failure reproduced after restoring the previously suspected stable
  `tflag0=6211` profile value.

This means `tflag0=6211` was necessary to restore one known-good historical
profile shape, but it was not sufficient to prevent the later hang.

## Evidence

The controlled failed run is under:

```text
work/forensics/dxwnd_matrix_20260428_keepopen/candidate
```

Key captured files:

```text
work/forensics/dxwnd_matrix_20260428_keepopen/candidate/observed_hang_now_process_snapshot.json
work/forensics/dxwnd_matrix_20260428_keepopen/candidate/observed_hang_now_profile_fields.txt
work/forensics/dxwnd_matrix_20260428_keepopen/candidate/observed_hang_now_dxwnd_game_log_tail.txt
work/forensics/dxwnd_matrix_20260428_keepopen/candidate/observed_hang_now_cdb_wow64_stack_2032.txt
```

The process snapshot showed:

```text
dxwnd.exe  responding=true
LBA2.EXE   responding=false
```

The loaded profile at the time of the hang was verified as the candidate:

```ini
debug=1
flag0=673185826
flagg0=1207959552
flagh0=20
flagi0=134217732
flagj0=4224
flagk0=65536
tflag0=6211
dflag0=0
winver0=0
initresw0=800
initresh0=600
slowratio0=2
scanline0=0
```

The non-invasive CDB WoW64 stack put the main thread in DirectDraw surface
creation through DxWnd and the Windows apphelp DWM compatibility hook:

```text
DDRAW!AllocAligned
DDRAW!HELAllocateSurfaceSysMem
DDRAW!myCreateSurface
DDRAW!DdCreateSurface
DDRAW!createSurface
DDRAW!createAndLinkSurfaces
DDRAW!InternalCreateSurface
DDRAW!DD_CreateSurface4_Main
DDRAW!DD_CreateSurface
apphelp!DWM8AND16BitCOMHook_IDirectDraw2_CreateSurface
dxwnd+0xe45d
dxwnd+0x803b
dxwnd!GetThreadStartAddress+0x1710b
dxwnd+0x84b3
AMDXN32...
```

The DxWnd log tail from the game directory showed repeated primary-surface
lock/unlock traffic and a 640x480 32-bit system-memory offscreen surface:

```text
Lock(2): lpdds=654940(PRIM) flags=1(DDLOCK_WAIT)
Unlock(2): lpdds=654940(PRIM)
GetSurfaceDesc(2): ... Width=640 Height=480 Pitch=2560
Caps=840(DDSCAPS_OFFSCREENPLAIN+SYSTEMMEMORY) ... BPP=32
```

This matches the earlier DxWnd failure family: DirectDraw, DxWnd, apphelp, and
the AMD 32-bit driver are in the hot path. It does not look like an LBA2
gameplay-logic failure.

## Source check

The original LBA2 code path around the old stack addresses did not point to a
gameplay system recreating surfaces directly. Ghidra/source-side inspection
mapped the nearby LBA2 frames to the normal DirectDraw primary-surface
lock/unlock/render path:

```text
0x0045BAE8: return from IDirectDrawSurface::Lock
0x0045BB69: return from IDirectDrawSurface::Unlock
```

The normal game loop repeatedly locks/unlocks the primary surface and copies
dirty regions. Scene/menu/load/audio activity can change timing and make the
bug easier to hit, but the captured hang is in DirectDraw surface allocation
under DxWnd/apphelp/AMD, not in the gameplay save state itself.

## Apparent solution

Run the `no_aeroboost` profile variant:

```ini
flagj0=4096
```

The stable trial is under:

```text
work/forensics/dxwnd_matrix_20260428_keepopen/no_aeroboost
```

Key files:

```text
work/forensics/dxwnd_matrix_20260428_keepopen/no_aeroboost/profile_fields.txt
work/forensics/dxwnd_matrix_20260428_keepopen/no_aeroboost/kept_open_process_snapshot.json
work/forensics/dxwnd_matrix_20260428_keepopen/no_aeroboost/startup.json
```

Observed loaded values:

```ini
debug=1
flag0=673185826
flagg0=1207959552
flagh0=20
flagi0=134217732
flagj0=4096
flagk0=65536
tflag0=6211
dflag0=0
winver0=0
initresw0=800
initresh0=600
slowratio0=2
scanline0=0
```

This run stayed responsive during manual live testing after the candidate had
reproduced the hang. Treat this as solved for day-to-day work, but not proven:
we have one strong A/B observation, not enough repetitions to claim the exact
DxWnd bit is the sole cause.

## How to reproduce the proof loop

Use the repo-local runner:

```powershell
$root = 'D:\repos\reverse\littlebigreversing\work\forensics\dxwnd_matrix_20260428_keepopen'

py -3 work\forensics\run_dxwnd_trial.py `
  --variant no_aeroboost `
  --save work\saves\01-tralu-main.LBA `
  --out-root $root `
  --duration-sec 75 `
  --poll-sec 5 `
  --keep-open
```

If the game hangs again, do not immediately kill it. Capture the same evidence
set first:

```powershell
$out = 'D:\repos\reverse\littlebigreversing\work\forensics\dxwnd_matrix_20260428_keepopen\no_aeroboost'
$targetPid = (Get-Process LBA2 -ErrorAction Stop).Id
$cdb = 'C:\Program Files\WindowsApps\Microsoft.WinDbg_1.2603.20001.0_x64__8wekyb3d8bbwe\amd64\cdb.exe'

Get-Process dxwnd,LBA2 -ErrorAction SilentlyContinue |
  Select-Object ProcessName,Id,Responding,CPU,StartTime,Path |
  ConvertTo-Json -Depth 3 |
  Set-Content -Encoding UTF8 (Join-Path $out 'observed_hang_process_snapshot.json')

Select-String -Path 'C:\Users\sebam\DxWnd.reloaded\build\dxwnd.ini' `
  -Pattern '^(debug|tflag0|winver0|flag0|flagg0|flagh0|flagi0|flagj0|flagk0|dflag0|initresw0|initresh0|slowratio0|scanline0)=' |
  ForEach-Object { $_.Line } |
  Set-Content -Encoding ASCII (Join-Path $out 'observed_hang_profile_fields.txt')

Get-Content 'D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\dxwnd.log' -Tail 400 |
  Set-Content -Encoding UTF8 (Join-Path $out 'observed_hang_dxwnd_game_log_tail.txt')

& $cdb -pv -p $targetPid -c ".load wow64exts; !wow64exts.sw; ~* kb; !runaway; lm; q" *>
  (Join-Path $out "observed_hang_cdb_wow64_stack_$targetPid.txt")
```

## Current recommendation

Use `flagj0=4096` as the canonical local DxWnd setting for LBA2 testing unless
new evidence disproves it. Do not revert to the candidate `flagj0=4224` profile
for normal gameplay testing; keep it only as a known failing comparison case.

Keep `winver0=0`. The built-in template path with `winver0=1` is separately
associated with a privileged-instruction crash at `0x0045BFAE`.
