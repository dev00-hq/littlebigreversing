# LM Investigation Workflow

This note owns the `LM_DEFAULT` / `LM_END_SWITCH` investigation workflow inside `LM_TASKS/`.

It does not own the repo's product direction, parity target, or supported runtime boundary.
Those remain canonical in:

- [project_brief.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/project_brief.md)
- [current_focus.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/current_focus.md)

## Scope

- preserve evidence-backed findings from the original Windows runtime
- keep one current-state operator workflow for the live Tavern proof and debugger handoff
- preserve static interpreter facts that still matter for future evidence passes
- keep historical evidence available without letting stale assumptions become operator defaults again

## Current Status

- The repo's guarded decoder/runtime boundary stays closed for switch-family life.
- Current product policy is still to reject `LM_DEFAULT` and `LM_END_SWITCH` unless new checked-in primary-source evidence changes that decision.
- Gate 1 static dispatch proof is complete.
- Gate 2 live Tavern repro proof is complete.
- Gate 3 WinDbg MCP attach, x86-mode switch, read-only probing, and clean detach are complete.
- The remaining Gate 3 blocker is a late-attach timing/state problem: `g` on an armed `0x004205BC` breakpoint has not yet returned within the MCP timeout from the standing-Tavern state.

## Current-State Workflow

1. Static interpreter anchor:
   - use [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
2. Live repro proof on the original runtime:
   - use [FRIDA_GATE2_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/FRIDA_GATE2_WORKFLOW.md)
3. Post-proof debugger attribution:
   - use [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md)
4. Active handoff and artifact list:
   - use [LM_CURRENT_TASK.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_CURRENT_TASK.md)
5. Disproven assumptions and process traps:
   - use [LESSONS.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LESSONS.md)

## Evidence-Backed Facts That Stay Canonical Here

- `DoLife = 0x00420574`
- `DoFuncLife = 0x0041F0A8`
- `DoTest = 0x0041FE30`
- `PtrPrg = 0x004976D0`
- recovered `DoLife` has explicit `0x73`, `0x75`, and `0x77` cases, but no explicit `0x74` or `0x76` cases
- the current live Tavern save fingerprint at `PtrLife + 40` is:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- the current live repeating hero window is:
  - `0x71 @ 4780`
  - `0x73 @ 4783`
  - `0x75 @ 4805`
  - `0x76 @ 4883`
  - `0x37 @ 4884` with `post_076_outcome = loop_reentry`
- `break_jump 4805 -> 103` is real runtime evidence, but it is not the proof gate for the visible later `0x76`
- WinDbg MCP can now:
  - open the remote session
  - switch to guest WoW x86 mode
  - disassemble the `DoLife` loop
  - read `PtrPrg`
  - detach cleanly with `qqd`

## Operator Rules

- Do not treat this folder as the repo's product roadmap.
- Do not reopen the decoder boundary or runtime semantics from `LM_TASKS/` notes alone.
- Keep one live Tavern baseline only:
  - fingerprint at `PtrLife + 40`
  - focus window `4780..4890`
  - target `0x76 @ 4883`
  - bounded `loop_reentry @ 4884`
- Do not revive the stale live-save assumptions:
  - checked-in scene-5 `0x76 @ 46`
  - `LM_BREAK 43 -> 46` as a required proof gate
  - `621 -> 624`
- Keep the debugger flow attach-only from Codex:
  - Frida or the user gets the game into the correct live state first
  - WinDbg MCP performs attribution after that

## Historical Evidence That Still Matters

- The checked-in offline scene-5 hero life blob still hits `LM_END_SWITCH` at byte offset `46`.
- Scene `11` object `12`, scene `11` object `18`, and scene `2` hero still matter as checked-in evidence surfaces for unsupported switch-family life.
- Those facts remain useful for offline audit and future evidence review, but they are not the current live Tavern operator defaults.

## Recommended Next Decision

- Keep `LM_TASKS/` focused on evidence capture and debugger workflow.
- Keep product-boundary decisions in `docs/codex_memory/`.
- If a future prompt wants decoder widening, require new checked-in primary-source evidence first instead of treating the current LM notes as an implicit approval path.
