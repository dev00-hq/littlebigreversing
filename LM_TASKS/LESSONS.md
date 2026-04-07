# Lessons Learned

## TavernTrace Lessons

- The first failure mode was not tracer instability. It was a save-shape mismatch. A stable tracer with the wrong fingerprint and wrong focus window can never succeed.
- TavernTrace originally had two independent stale assumptions:
  - the visible preset in `trace_life.py`
  - a separate hard-coded break-site assumption in `TavernTraceController`
  Updating only one of those is not a real retarget.
- `scripts/trace-life.ps1` was also forwarding generic basic-mode target flags even in Tavern mode. Wrapper-level defaults can silently override the intended canonical path.

## Evidence Lessons

- A live save can resume the hero deep inside a different switch-family window. Do not assume that a scene-level checked-in blob and a user save will line up on the same `PtrPrg` offsets.
- The correct live fingerprint for the exercised Tavern save is:
  - `PtrLife + 40 = 28 14 00 21 2F 00 23 0D 0E 00`
- The live stable repeating window discovered under the correct fingerprint is:
  - `4780 -> 0x71`
  - `4783 -> 0x73`
  - `4805 -> 0x75`
  - `4883 -> 0x76`
- The observed `BREAK` at `4805` computes target `103`. Do not assume the visible later `0x76` is the break target just because both appear in the same repeating loop.

## Process Lessons

- When a proof hypothesis is weak, the fastest next move is a discovery pass, not a second hard-coded retarget.
- The discovery pass should narrow to the most likely active window and record actual loop offsets before promoting any new canonical target.
- Let the save settle first. The stable repeating live loop already appeared after load; extra movement/talk added noise before we had the baseline pinned down.

## Tooling Lessons

- Frida pointer access in this workspace must use `NativePointer.read*()` methods.
- `readWindow()` was still using `Memory.readByteArray(...)` after the main pointer-read fixes. That meant the tracer could prove offsets/opcodes while still failing to capture the surrounding bytes.
- The host loop should stop cleanly when `LBA2.EXE` exits. Waiting for the full timeout after the game window is gone adds noise and turns a useful process-exit signal into a misleading screenshot failure.

## Cross-Repo Lessons

- `idajs` is useful for understanding why saves drift:
  - `OffsetLife` and `ExeSwitch` are persisted and restored
  - synthetic harnesses exist for isolated life-script experiments
- `lba2remake` is useful as a structural hypothesis source for opcode families and parser shape.
- Neither external repo is proof for the original runtime's exact live control flow. Use them to generate tests, not to bless semantics.

## Scene11Pair Lessons

- The first scene-11 blocker was UI-state ambiguity, not missing tracer plumbing.
  - OCR over captured frames proved `scene11-live-window-3.png` was still the Adeline splash.
  - After one no-Frida `Enter`, `scene11-nofrida-post-enter.png` showed the real main menu:
    - `Resume Game`
    - `New Game`
    - `Load Game`
    - `Options Menu`
    - `Quit`
  - After a second no-Frida `Enter`, `scene11-nofrida-step2.png` left that text-heavy menu and entered a mostly textless screen.
  - After a third no-Frida `Enter`, `scene11-nofrida-step3.png` returned to the main menu.

- The scene-11 structured tracer is working as designed.
  - Multiple runs reached:
    - `message = attached`
    - `message = waiting for the canonical scene-11 fingerprint`
    - `message = life trace agent loaded`
  - A no-fingerprint run is not enough evidence to blame the tracer. It can also mean the runtime never reached the intended scene-11 state.

- The direct `ArgV[1]` launch path with `scene11-pair.LBA` is still a real crash path.
  - Passing the staged save directly to `LBA2.EXE` on the command line still produced an `Application Error` window before the scene-11 fingerprint matched.
  - Treat command-line save launch as broken until a checked-in proof run says otherwise.

- Frida attach timing matters on the scene-11 lane.
  - With Frida attached before or across the later resume/load transition, `LBA2.EXE` hit a real `APPCRASH` with `0xc0000005`.
  - Windows logged that crash at `2026-04-07 02:03:49` local time for the first late-menu repro.
  - A later late-attach repro stayed alive long enough to surface `Application Error: ...\\LBA2.EXE` instead of exiting cleanly.
  - The matching no-Frida control path stayed alive through the same three `Enter` steps, so this is attach-sensitive behavior, not yet proof that the staged scene-11 save is intrinsically invalid.

- `current.lba` is disposable runtime state, not a stable alias for `scene11-pair.LBA`.
  - After staging `scene11-pair.LBA` into `current.lba`, later no-Frida resume experiments rewrote `current.lba` from the staged `9403`-byte scene-11 file to a live `22591`-byte runtime save.
  - Future scene-11 attempts must re-stage `current.lba` before each controlled run instead of assuming the earlier copy is still present.

- `Resume Game` is no longer safe shorthand for "load the staged scene-11 save".
  - The menu state is now mapped well enough to know when we are on the splash versus the main menu.
  - The scene-11 fingerprint still never matched on the stable late-attach runs.
  - That means the remaining uncertainty is runtime navigation and save ownership, not just breakpoint timing.

- The safest debugging rule discovered so far is:
  - navigate the fragile splash and menu transitions without Frida first
  - use OCR-backed screenshots to name the active UI state
  - attach Frida only after the risky transition is already stable
  - prefer proving explicit `Load Game` behavior over assuming `Resume Game` consumes `current.lba`

## Handoff Rule

- The next session should start from the discovery facts above, not from the obsolete `43 -> 46` plan and not from the later-invalid `621 -> 624` hypothesis.
