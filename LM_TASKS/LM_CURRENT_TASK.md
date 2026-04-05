# Current Task

This LM collaboration follows [LM_TASKS/LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md).

## Gate

- Gate 2: deterministic repro setup

## Objective

Lock the repo-local Tavern trace onto the user's actual live save and keep a single canonical proof path for future scene-5 runtime evidence.

Primary entrypoint:

- `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120`

## What Landed

The deterministic repro setup is now working on the live Tavern save.

Verified current-state behavior:

- `tools/life_trace/trace_life.py` now treats `0x76 @ 4883` as the canonical Tavern target, not the obsolete `624` hypothesis.
- The Tavern controller no longer requires `LM_BREAK` to prove the later visible `0x76`; `LM_BREAK` stays captured as observational evidence only.
- `tools/life_trace/agent.js` `readWindow()` now uses a pointer byte-window read, so `window_trace.ptr_window.bytes_hex` is populated again.
- The canonical launch command completed successfully against the live Tavern save:
  - `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120`
- The first proof-success artifact is:
  - [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl)

## Verified Runtime Facts

The current live Tavern save does execute the hero switch-family path, and the fingerprint gate now matches.

From the successful proof run in [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl):

- hero `object_index = 0`
- `OffsetLife = 47`
- bytes at `PtrLife + 40`:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- `target_validation` matches that fingerprint successfully
- the active repeating hero window is:
  - `0x71` at offset `4780`
  - `0x73` at offset `4783`
  - `0x75` at offset `4805`
  - `0x76` at offset `4883`
  - then `0x37` at offset `4884` with `post_076_outcome = loop_reentry`
- the observed `break_jump` at `4805` still computes target offset `103`
- byte-window capture is restored; example live windows now include:
  - `4780`: `00 00 09 1f 0b 00 82 00 71 0b 06 73 1c 00 00 00 0c`
  - `4883`: `00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09`
- the terminal verdict is:
  - `result = tavern_trace_complete`
  - `reason = captured Tavern proof through loop_reentry`
  - `required_screenshots_complete = true`

## Current Status

Gate 2's Tavern deterministic repro objective is satisfied.

Canonical Tavern proof path:

- fingerprint match at `PtrLife + 40`
- bounded switch-window capture in `4780..4890`
- target fetch `0x76 @ 4883`
- bounded post-target outcome `loop_reentry` at `4884`
- required screenshot set captured successfully

Important interpretation rule:

- keep `break_jump 4805 -> 103` as runtime evidence, but do not require it as the proof gate for the visible later `0x76`

## Collaboration Split

Codex next session:

- reuse [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl) and its screenshot set as the canonical Tavern acceptance artifact
- decide whether downstream docs should describe the proof as:
  - the full observed cluster `4780 -> 4783 -> 4805 -> 4883 -> 4884`
  - or the smaller canonical gate `4883 -> 4884` with earlier offsets treated as supporting evidence
- keep future Tavern work loop-only unless a later prompt explicitly widens scope

## Immediate Next Step

Recommended path:

1. Treat the current Tavern tracer as canonical for the live save and avoid further semantic widening inside Gate 2.

If another live verification is needed:

1. Re-run:
   - `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120`
2. Load the same Tavern save and let it settle before adding movement.
3. Compare against:
   - fingerprint bytes `28 14 00 21 2F 00 23 0D 0E 00`
   - target `0x76 @ 4883`
   - follow-up `loop_reentry @ 4884`
   - `result = tavern_trace_complete`

## Guardrails

- Keep Tavern mode loop-only unless a later pass proves that loop-only is insufficient.
- Do not switch back to `Memory.read*()` in Frida JS for pointer reads or byte windows; use pointer methods.
- Do not keep two Tavern presets. Pick one canonical current-state preset for the live save being used.
- Do not reintroduce the obsolete `40..48` or `621 -> 624` assumptions as compatibility paths.
- Do not turn `break_jump 4805 -> 103` back into a required proof gate unless new checked-in evidence proves it is necessary.
- Do not widen into unsupported life-decoder semantics claims; this work is still runtime trace setup, not parity widening.

## Useful Artifacts

- first successful fingerprint-matched discovery run:
  - [life-trace-20260405-010429.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-010429.jsonl)
- first successful canonical proof run:
  - [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl)
- earlier live-save fingerprint match with excessive branch spam:
  - [life-trace-20260405-005345.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-005345.jsonl)
- stable but preset-mismatched Tavern run:
  - [life-trace-20260405-001633.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-001633.jsonl)
- latest typed handoff record:
  - [task_events.jsonl](/D:/repos/reverse/littlebigreversing/docs/codex_memory/task_events.jsonl)
- static interpreter reference:
  - [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
