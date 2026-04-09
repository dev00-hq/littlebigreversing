# Current Task

This file is the live handoff for the LM investigation stream.

It follows the workflow in [LM_TASKS/LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md), but it does not replace the repo's canonical product plan in `docs/codex_memory/`.

## Gate

- Gate 3: branch-A proof-gate attribution with Frida plus WinDbg MCP

## Objective

Pause non-essential widening and end this sprint with a decision memo, not interpreter code.

Current live goal:

- keep the proved Tavern lane as the canonical `LM_END_SWITCH` debugger baseline
- add the scene-11 pair lane for object `12` `LM_DEFAULT` and object `18` `LM_END_SWITCH`
- attribute both lanes with pre-window WinDbg attach rather than late standing-state attach

Primary entrypoints:

- `py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120 --keep-alive`
- `py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --timeout-sec 120 --keep-alive`
- then control an existing WinDbg remote session through the configured `windbg` MCP server

## What Landed

The proof-gate sprint plumbing is now in the tree.

Verified current-state behavior:

- `tools/life_trace/trace_life.py` now owns the canonical operator entrypoint for both structured modes.
- `--mode tavern-trace` now uses `frida-agent-cli` as its canonical Frida control plane via `--fra-repo-root` and the repo-local `.venv` launcher.
- `--mode scene11-pair` now also uses `frida-agent-cli` as its canonical Frida control plane via `--fra-repo-root`.
- `--mode basic` remains the only direct-Frida fallback path and the only mode that still accepts `--frida-repo-root`.
- `tools/life_trace/trace_life.py` accepts `--mode scene11-pair`.
- structured modes reject explicit `--target-object`, `--target-opcode`, and `--target-offset` overrides in the Python CLI.
- `trace_life.py` now passes comparison-target metadata through to the Frida agent.
- `tools/life_trace/agent.js` now fingerprints scene 11 object `12`, tracks resolved primary/comparison hits, and records the before/after evidence bundle for each live hit.
- the canonical scene-11 runtime save is staged at:
  - `work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\SAVE\scene11-pair.LBA`
- `trace_life.py` now owns the default checked-in launch path and JSONL output path for both structured modes.

## Verified Runtime Facts

### Tavern baseline

From the successful proof run in [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl):

- hero `object_index = 0`
- `OffsetLife = 47`
- bytes at `PtrLife + 40`:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- the active repeating hero window is:
  - `0x71 @ 4780`
  - `0x73 @ 4783`
  - `0x75 @ 4805`
  - `0x76 @ 4883`
  - then `0x37 @ 4884` with `post_076_outcome = loop_reentry`
- the terminal verdict is:
  - `result = tavern_trace_complete`
  - `required_screenshots_complete = true`

### Scene-11 pair baseline

From offline scene inspection and the landed `Scene11Pair` preset:

- canonical source save in `work\idajs_samples_save_map.jsonl` is `S8741.LBA`
- scene-11 primary fingerprint owner is object `12`
- bytes at object `12` `PtrLife + 30`:
  - `00 01 17 42 00 75 2D 00 74 17`
- primary target:
  - object `12`
  - `0x74 @ 38`
- same-scene comparison target:
  - object `18`
  - `0x76 @ 84`

From the first staged-save smoke run in [life-trace-20260407-011725.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260407-011725.jsonl):

- spawn used:
  - `launch_save = ...\SAVE\scene11-pair.LBA`
- the tracer attached and resumed cleanly
- the game window was capturable
- the run still ended with:
  - `result = timed_out_before_fingerprint`
- current interpretation:
  - staged save launch is wired
  - automatic spawn alone is not yet enough to reach the canonical scene-11 live fingerprint
  - manual scene load and settle are still required

## Current Status

- Gate 2's Tavern deterministic repro objective is satisfied.
- Gate 3's first live WinDbg MCP attach on the Tavern runtime is still validated for attach, x86 mode switch, read-only probing, and clean detach.
- The proof-gate sprint is now split across two live lanes:
  - Tavern for `LM_END_SWITCH` baseline
  - scene 11 pair for `LM_DEFAULT` plus same-scene `LM_END_SWITCH`
- The remaining blocker is not tooling availability.
  - it is still live timing and attribution:
  - attach early enough for WinDbg
  - reach the correct manual scene-11 settled state for Frida

## Collaboration Split

Codex next session:

- reuse [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl) as the canonical Tavern acceptance artifact
- reuse [life-trace-20260407-011725.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260407-011725.jsonl) as proof that staged scene-11 spawn still needs a manual load/settle step
- leave the Frida-launched process alive with `--keep-alive`, then open the debugger through the configured `windbg` MCP server
- attach before the trigger window and arm:
  - `bp 0x00420574`
  - then `bp 0x004205BC`
- collect the next live pass on:
  - Tavern `0x76 @ 4883`
  - scene 11 object `12` `0x74 @ 38`
  - scene 11 object `18` `0x76 @ 84`

## Immediate Next Step

Recommended path:

1. Re-run `scene11-pair` with `--keep-alive`.
2. Manually load the canonical scene-11 save and let it settle in the intended live state.
3. Wait for Frida to record the scene-11 fingerprint and the object-12 primary hit.
4. Keep the process alive for WinDbg attach before the comparison trigger window is missed.
5. Reuse the validated read-only MCP probes first, then arm `0x00420574` and `0x004205BC` in that order.

Canonical command sequence:

1. Re-run:
   - `py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --timeout-sec 120 --keep-alive`
2. Manually load:
   - `scene11-pair.LBA`
3. Let the lane settle before further interaction.
4. Bootstrap a WinDbg/CDB remote session out-of-band on that already-running process.
5. In Codex, call:
   - `open_windbg_remote(connection_string=...)`
6. Run one command per MCP call:
   - `run_windbg_cmd(command="!wow64exts.sw")`
   - `run_windbg_cmd(command="u 0x00420574 L20")`
   - `run_windbg_cmd(command="u 0x004205BC L20")`
   - `run_windbg_cmd(command="dd 0x004976D0 L1")`
   - `run_windbg_cmd(command="dd 0x004976D4 L1")`
   - `run_windbg_cmd(command="dd 0x00497D44 L1")`
   - `run_windbg_cmd(command="bp 0x00420574")`
   - `run_windbg_cmd(command="bp 0x004205BC")`
   - only then retry `run_windbg_cmd(command="g")`

## Guardrails

- Keep this sprint proof-only.
- Keep WinDbg attach-only. Frida or the user gets the process into the right live state first.
- Do not return to shell-managed reconnect clients as the canonical path. Use the `windbg` MCP server once a remote session exists.
- Use one WinDbg command per MCP call instead of semicolon-joined shell batches.
- Do not switch back to `Memory.read*()` in Frida JS for pointer reads or byte windows; use pointer methods.
- Do not reintroduce obsolete scene-5 or `621 -> 624` assumptions as compatibility paths.
- Do not widen into unsupported life-decoder semantics claims; this work is still proof-gate setup.

## Useful Artifacts

- first successful canonical Tavern proof run:
  - [life-trace-20260405-011732.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-011732.jsonl)
- current live Tavern proof artifact:
  - [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl)
- first staged scene-11 smoke run:
  - [life-trace-20260407-011725.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260407-011725.jsonl)
- live WinDbg MCP server log for the first real `LBA2.EXE` attach:
  - [mcp-live-lba2-cdb.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-live-lba2-cdb.log)
- live WinDbg MCP log for the resumed-breakpoint investigation:
  - [mcp-live-lba2-breakpoint-test.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-live-lba2-breakpoint-test.log)
- live WinDbg MCP log for the fresh launch-and-attach verification:
  - [mcp-final-launch-attach.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-final-launch-attach.log)
- static interpreter reference:
  - [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
- Gate 3 debugger workflow:
  - [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md)
