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

## Handoff Rule

- The next session should start from the discovery facts above, not from the obsolete `43 -> 46` plan and not from the later-invalid `621 -> 624` hypothesis.
