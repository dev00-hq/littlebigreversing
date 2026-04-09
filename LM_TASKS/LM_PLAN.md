# LM Investigation Workflow

This note owns the proof-only `LM_DEFAULT` / `LM_END_SWITCH` investigation workflow inside `LM_TASKS/`.

It does not own the repo's product direction, parity target, or supported runtime boundary.
Those remain canonical in:

- [project_brief.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/project_brief.md)
- [current_focus.md](/D:/repos/reverse/littlebigreversing/docs/codex_memory/current_focus.md)

## Scope

- run a branch-A proof gate sprint, not decoder or runtime widening
- preserve one canonical Tavern lane for `LM_END_SWITCH` debugger rehearsal
- add one canonical scene-11 pair lane for `LM_DEFAULT` plus same-scene `LM_END_SWITCH`
- keep all active handoff state in `LM_TASKS/` until the proof outcome is known

## Current Sprint Status

- The repo's guarded decoder/runtime boundary stays closed for switch-family life.
- Gate 1 static dispatch proof is complete.
- Gate 2 live Tavern proof is complete.
- Gate 3 WinDbg MCP attach, x86-mode switch, read-only probing, and clean detach are complete.
- The current sprint reopens Phase 4 as an evidence gate:
  - keep Tavern `0x76 @ 4883` as the first live attribution lane
  - add scene 11 object `12` `0x74 @ 38` as the primary `LM_DEFAULT` lane
  - add scene 11 object `18` `0x76 @ 84` as the same-scene `LM_END_SWITCH` comparison lane
- `tools/life_trace/trace_life.py` now exposes `scene11-pair` as the canonical structured entrypoint.
- The canonical scene-11 save is staged at:
  - `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\scene11-pair.LBA`
- Automatic spawn with that staged save still timed out before the scene-11 fingerprint matched in:
  - [life-trace-20260407-011725.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260407-011725.jsonl)
- Current interpretation:
  - launch-time `ArgV[1]` is not enough by itself
  - the scene-11 lane still requires a manual load-and-settle step before attribution

## Canonical Lanes

### Lane A: Tavern `LM_END_SWITCH` Baseline

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

### Lane B: Scene 11 Pair

- canonical source save:
  - `work\idajs_samples_save_map.jsonl` entry `S8741.LBA`
- canonical staged runtime save:
  - `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\scene11-pair.LBA`
- primary fingerprint owner:
  - object `12`
- primary fingerprint offset:
  - `PtrLife + 30`
- primary fingerprint bytes:
  - `00 01 17 42 00 75 2D 00 74 17`
- primary target:
  - object `12`
  - `0x74 @ 38`
- same-scene comparison target:
  - object `18`
  - `0x76 @ 84`

## Required Evidence Bundle

For every attributed live hit, capture:

- direct fetch from the live `DoLife` loop
- `PtrPrg` before the hit
- byte at `PtrPrg`
- `PtrPrg` after the hit
- next visible opcode or immediate post-hit control-flow result
- `TypeAnswer` before and after
- `Value` before and after
- `ExeSwitch` before and after
- whether `DoFuncLife` or `DoTest` were entered on that observed path

`Scene11Pair` now records that bundle in structured `window_trace` or `do_life_return` events tagged with:

- `trace_role = primary`
- `trace_role = comparison`

## Current-State Workflow

1. Static interpreter anchor:
   - use [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
2. Live Frida proof lanes:
   - use [FRIDA_GATE2_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/FRIDA_GATE2_WORKFLOW.md)
3. WinDbg MCP attribution after the live lane is ready:
   - use [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md)
4. Active handoff and artifact list:
   - use [LM_CURRENT_TASK.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_CURRENT_TASK.md)
5. Disproven assumptions and process traps:
   - use [LESSONS.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LESSONS.md)

## Operator Rules

- Keep this sprint proof-only.
- Do not widen the decoder or runtime boundary in the same effort.
- Do not update `docs/codex_memory/` or the roadmap until the proof outcome is known.
- Keep WinDbg MCP as the only Codex debugger control surface.
- Do not revive x64dbg or shell-managed `cdb` as a second canonical path.
- Attach WinDbg before the live trigger window; do not keep retrying the late standing-state Tavern attach as if it were the canonical shape.
- Do not silently switch the primary `LM_DEFAULT` target away from the scene-11 pair.

## Exit Condition

The sprint ends with a decision memo, not interpreter code.

Reopen branch A only if live evidence answers all four questions coherently for both opcodes:

1. Is the opcode fetched directly in the live `DoLife` loop?
2. Does it consume zero bytes or additional operands?
3. Does it rely on `DoFuncLife`, `DoTest`, or `ExeSwitch` state changes?
4. What is the immediate post-opcode control-flow result?
