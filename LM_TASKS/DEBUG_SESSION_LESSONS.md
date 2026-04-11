# Debug Session Lessons

This note is the operator-facing handoff for the original Windows `LBA2.EXE` debug session.

It is not the product plan and it is not a proof memo about life semantics.
Its job is simpler:

- how to launch the game safely
- how to stage the save safely
- how to drive the front-end without losing the session
- when to attach Frida
- when to attach WinDbg
- what traps already cost time

## Canonical Runtime Paths

Executable:

```text
D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE
```

Runtime save directory:

```text
D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE
```

Canonical staged scene-11 save:

```text
D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\scene11-pair.LBA
```

## Why `scene11-pair.LBA` Was Chosen

The staged runtime save was not chosen by guesswork or by the filename alone.

The provenance chain is:

1. `work\idajs_samples_save_map.jsonl` contains source save `S8741.LBA`.
2. That record says:
   - `raw_scene_entry_index = 11`
   - `save_name = 02-voisin`
   - `scene_lookup.scene_name = Neighbour's House`
3. The task docs promoted that source save into the runtime lane:
   - `LM_TASKS\LM_PLAN.md`
   - `LM_TASKS\LM_CURRENT_TASK.md`
4. The `Scene11Pair` preset in `tools\life_trace\trace_life.py` then hardcoded the staged runtime path:
   - `...\SAVE\scene11-pair.LBA`

There is also a direct file-shape cross-check:

- `S8741.LBA` in the `idajs` save map is `9403` bytes
- `scene11-pair.LBA` in the runtime `SAVE` folder is also `9403` bytes
- the staged file begins with the same `save_name` bytes for `02-voisin`

So the working assumption was:

- `scene11-pair.LBA` is the staged runtime copy of mapped source save `S8741.LBA`

## Scene Numbering Lesson

Be careful with the phrase "scene 11".

In this lane, "scene 11" came from:

- `raw_scene_entry_index = 11`

It did **not** come from:

- `scene_lookup.scene_id = 11`

For `S8741.LBA`, the mapped semantic scene id is actually:

- `scene_id = 9`

with scene name:

- `Neighbour's House`

Operational rule:

- when talking about these staged saves, say whether you mean:
  - raw save-map scene entry index
  - or semantic mapped scene id

Do not collapse those into one number.

## First Rule: Separate Control Navigation From Instrumentation

For the scene-11 lane, the front-end navigation is fragile enough that it should be treated as its own phase.

Proven safer split:

1. Launch and drive the game without Frida through the fragile splash and early menu transitions.
2. Capture the screen after each meaningful input.
3. Attach `Scene11Pair` only after the runtime is already in a stable post-menu state.
4. Only after Frida proves the lane should WinDbg attach.

What did not work reliably:

- attaching Frida too early and then driving the resume/load transition
- assuming a command-line save path would load the scene directly
- assuming `Resume Game` was consuming the staged `current.lba` exactly as expected

## Launch Lessons

### Safe launch path

Use a normal launch with the executable directory as the working directory.

```powershell
$lbaDir = 'D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2'
Start-Process -FilePath (Join-Path $lbaDir 'LBA2.EXE') -WorkingDirectory $lbaDir
```

This path was stable in control runs.

### Unsafe launch path

Do not currently rely on:

```text
LBA2.EXE <full-path-to-scene11-pair.LBA>
```

Observed result:

- `LBA2.EXE` can surface `Application Error` before the scene-11 fingerprint ever matches

Treat direct `ArgV[1]` save launch as broken until a checked-in proof run says otherwise.

## Save Staging Lessons

### `current.lba` is not stable

`current.lba` is live runtime state.
If you copy `scene11-pair.LBA` into `current.lba`, later no-Frida resume tests can rewrite it immediately.

Operational rule:

1. Re-stage `current.lba` before each controlled repro.
2. Do not assume the previous run left it intact.

Canonical restage pattern:

```powershell
$saveDir = 'D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE'
Copy-Item (Join-Path $saveDir 'scene11-pair.LBA') (Join-Path $saveDir 'current.lba') -Force
```

If you care about preserving the live slot first:

```powershell
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item (Join-Path $saveDir 'current.lba') (Join-Path $saveDir "current.pre-scene11-$timestamp.lba")
Copy-Item (Join-Path $saveDir 'scene11-pair.LBA') (Join-Path $saveDir 'current.lba') -Force
```

## Front-End Driving Lessons

### Proven screen progression

These are the states we actually proved with captured screenshots plus OCR:

1. Initial visible state:
   - Adeline splash
   - confirmed from `scene11-live-window-3.png`
2. One `Enter` from the splash:
   - real main menu
   - confirmed from `scene11-nofrida-post-enter.png`
3. Text seen on that menu:
   - `Resume Game`
   - `New Game`
   - `Load Game`
   - `Options Menu`
   - `Quit`
4. A second `Enter` from that state:
   - leaves the text-heavy main menu and enters a mostly textless intermediate screen
   - confirmed from `scene11-nofrida-step2.png`
5. A third `Enter` from there in the no-Frida control run:
   - returned to the main menu
   - confirmed from `scene11-nofrida-step3.png`

Important limit:

- we proved the screen progression
- we did not yet prove the exact semantic meaning of that intermediate screen

So treat the visual state as proven, but treat the menu semantics as still under investigation.

### Load-menu progression now proved

Later `2026-04-10` no-Frida discovery runs tightened the menu semantics further:

1. From the main menu, `Down`, `Down`, `Enter` opens `Load game`.
2. The `Load game` screen currently opens with `AUTOSAVE` selected.
3. The staged `current.lba` slot is `CURRENT`, which is four `Up` inputs away from that default selection.
4. Selecting `CURRENT` loads the same bar-like room reproducibly in no-Frida control runs.

Operational rule:

- treat `Load Game -> CURRENT` as the canonical scene-11 bootstrap path
- do not reopen `Resume Game` guesses unless a new checked-in run proves that path changed

### Safe input style

Do this:

- send one input at a time
- wait a couple of seconds after each input
- capture the window after each input
- only continue if the process is still responsive

Do not do this:

- burst `Enter`, `Esc`, and mouse clicks in one loop
- assume the input landed where you thought it did
- keep sending keys after the window title changes to `Application Error`

## Screenshot Lessons

Window capture was much more reliable than trying to infer state from guesswork.

Useful local capture pattern:

```powershell
@'
from pathlib import Path
import sys
sys.path.insert(0, r'D:\repos\reverse\littlebigreversing\tools\life_trace')
from trace_life import WindowCapture
cap = WindowCapture()
cap.capture(<PID>, Path(r'D:\repos\reverse\littlebigreversing\work\life_trace\shot.png'))
'@ | python -
```

Use that after each important input when debugging the front-end.

## OCR Lessons

OCR was the fastest way to stop guessing what screen we were on.

What it proved:

- the early screen really was the Adeline splash
- the later screen really was the main menu
- the main menu text was readable and stable

Operational use:

- if the current state is ambiguous, capture first
- OCR the capture
- only then choose the next input

That is better than memorizing a guessed menu flow.

## Frida Attach Lessons

### What worked

- attaching `Scene11Pair` to an already-running process after the game was stable
- seeing the expected startup events:
  - `attached`
  - `waiting for the canonical scene-11 fingerprint`
  - `life trace agent loaded`

### What did not work

- attaching Frida before or across the fragile later resume/load transition

Observed failure:

- `LBA2.EXE` hit `APPCRASH` / `Application Error` during the late transition when Frida was already attached

Matching control result:

- the same three-step no-Frida path stayed alive
- a later no-Frida `Load Game -> CURRENT` control also stayed alive for at least `65` seconds in the loaded bar room

Operational rule:

- for scene-11, navigate first
- attach later

Additional current-state note:

- even after `trace_life.py --mode scene11-pair --launch` adopted the canonical `Load Game -> CURRENT` bootstrap on `2026-04-10`, the late-attach run still timed out before fingerprint and surfaced `Application Error` in that same loaded room
- treat the remaining blocker as an attach-sensitive boundary or stale-fingerprint question, not as menu ambiguity

Do not treat early attach as the default path on this lane.

## WinDbg Lessons

WinDbg is not the first tool in the sequence.

Recommended order:

1. no-Frida control navigation
2. late Frida attach
3. only after a stable live lane is proved, attach WinDbg

Why:

- WinDbg is useful for attribution
- it is not useful if the front-end state is still uncertain
- attaching the debugger before the lane is real just compounds ambiguity

## PowerShell Lessons

Do not use PowerShell's built-in `$PID` variable for the target process id.

Use names like:

- `$targetPid`
- `$lbaPid`

Why:

- assigning to `$PID` silently targets the shell process instead of the game
- we hit this exact trap while trying to send keys and capture the real window

## Recommended Operator Recipe

For the current scene-11 investigations, use this order:

1. Close other fullscreen games and leave the machine free.
2. Re-stage `current.lba` from `scene11-pair.LBA`.
3. Launch `LBA2.EXE` normally.
4. Wait until the `LBA2` window is present and responsive.
5. Drive the splash and menu one input at a time.
6. Capture after each step.
7. Use OCR if the state is ambiguous.
8. Do not attach Frida until the fragile front-end transition is over.
9. Attach `Scene11Pair` to the already-running process.
10. Only if that live lane is stable, hand off to WinDbg MCP.

## Current Do-Not-Assume List

Do not assume:

- `ArgV[1]` save launch is safe
- `current.lba` still contains the staged save from the previous run
- `Resume Game` equals "load the staged scene-11 bytes"
- a no-fingerprint structured run means the tracer is broken
- the second post-menu screen has already been semantically identified
- early Frida attach is neutral on the scene-11 path

## Best Current Summary

The debug session is easiest to manage when treated as two separate problems:

- front-end state control
- instrumentation

The front-end should be driven slowly and observed directly.
The instrumentation should be attached after the front-end has reached a stable state.

That is the main operational lesson from this session.
