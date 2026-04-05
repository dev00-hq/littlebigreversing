# Current Task

This LM collaboration follows [LM_TASKS/LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md).

## Gate

- Gate 3: attribution-first WinDbg MCP tracing

## Objective

Keep the live Tavern Frida proof path canonical and use the configured WinDbg MCP server on that same runtime path for the first post-Frida attribution pass.

Primary entrypoint:

- `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120 -KeepAlive`
- then control an existing WinDbg remote session through the configured `windbg` MCP server

## What Landed

The deterministic repro setup is now working on the live Tavern save, and the debugger handoff has been retargeted from the repo-local wrapper to the Codex WinDbg MCP server.

Verified current-state behavior:

- `tools/life_trace/trace_life.py` now treats `0x76 @ 4883` as the canonical Tavern target, not the obsolete `624` hypothesis.
- The Tavern controller no longer requires `LM_BREAK` to prove the later visible `0x76`; `LM_BREAK` stays captured as observational evidence only.
- `tools/life_trace/agent.js` `readWindow()` now uses a pointer byte-window read, so `window_trace.ptr_window.bytes_hex` is populated again.
- The canonical launch command completed successfully against the live Tavern save:
  - `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120`
- The current proof-success artifact is:
  - [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl)
- The Codex app now has a configured `windbg` MCP server backed by `mcp-windbg`.
- The repo-local `scripts/cdb-session.ps1` wrapper remains in the tree as a failed experiment, not as the canonical Gate 3 owner.
- The first live WinDbg MCP pass against the real `LBA2.EXE` is now validated end-to-end for attach, x86 mode switch, code disassembly, pointer reads, and clean detach.
- A fresh-process launch-and-attach pass is now validated too: launch `LBA2.EXE`, attach remote `cdb`, switch to WoW x86 mode through MCP, read `DoLife`, read `PtrPrg`, and detach back to a responsive game.

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
Gate 3's first Frida proof on the current live Tavern save is captured.
Gate 3's first live WinDbg MCP attach on the current Tavern runtime is captured.
Gate 3 now pivots to WinDbg MCP control over an existing remote session; the old shell-managed detached `cdb` wrapper is no longer canonical after host-freeze evidence on 2026-04-05.

Canonical Tavern proof path:

- fingerprint match at `PtrLife + 40`
- bounded switch-window capture in `4780..4890`
- target fetch `0x76 @ 4883`
- bounded post-target outcome `loop_reentry` at `4884`
- required screenshot set captured successfully

Important interpretation rule:

- keep `break_jump 4805 -> 103` as runtime evidence, but do not require it as the proof gate for the visible later `0x76`

Latest live MCP facts:

- `open_windbg_remote(connection_string="tcp:Port=5023,Server=127.0.0.1,Password=test")` succeeded against the real `LBA2.EXE`
- `!wow64exts.sw` succeeded and exposed the live x86 `LBA2` image
- `u 0x004205B0 L10` disassembled the checked-in `DoLife` loop and confirmed `004205bc 8b15d0764900`
- `dd 0x004976D0 L1` returned `032f3572`
- `db poi(0x004976D0) L8` returned `00 03 00 00 00 1e 00 2f`
- `bp 0x004205BC` armed successfully, but `g` did not return within the MCP tool timeout window
- `qqd` detached and exited the live server successfully; `LBA2.EXE` returned to `Responding = True`
- a follow-up live session with one-shot logging breakpoints showed no hits at `0x004205BC` and no hardware watchpoint hits on `PtrPrg = 0x004976D0` during two separate 30-second resumed windows
- `!runaway` still showed real CPU time advancing while resumed, so the failure is not just a dead-stopped process
- after the resumed windows, thread instruction pointers were parked in `wow64cpu` / `ntdll` break states rather than an obvious `LBA2` code frame
- a fresh launch on PID `3824` also attached cleanly on `tcp:Port=5025,Server=127.0.0.1,Password=test`
- on that fresh launch, `u 0x004205B0 L10` again showed the expected `DoLife` loop and `dd 0x004976D0 L1` returned `00000000` before the scene logic had advanced
- `qqd` detached successfully again and returned the fresh-launch game to `Responding = True`

## Collaboration Split

Codex next session:

- reuse [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl) and its screenshot set as the canonical Tavern acceptance artifact
- leave the Frida-launched Tavern runtime alive with `-KeepAlive`, then open the debugger through the configured `windbg` MCP server
- reuse the validated live MCP sequence:
  - `open_windbg_remote`
  - `run_windbg_cmd("!wow64exts.sw")`
  - `run_windbg_cmd("bp 0x004205BC")`
  - `run_windbg_cmd("u 0x004205B0 L10")`
  - `run_windbg_cmd("dd 0x004976D0 L1")`
  - `run_windbg_cmd("db poi(0x004976D0) L8")`
  - `run_windbg_cmd("qqd")`
- treat the remaining blocker as a late-attach timing/state problem, not as an MCP transport problem
- investigate whether the next proof should attach earlier, break on a broader `DoLife` entry site, or use a different in-game trigger window before the post-settle standing state
- keep future Tavern work loop-only unless a later prompt explicitly widens scope beyond the current attribution pass

## Immediate Next Step

Recommended path:

1. Re-run the canonical Tavern tracer with `-KeepAlive` so the live process stays available for debugger attach.
2. Start or obtain a WinDbg/CDB remote session on that already-running `LBA2.EXE`.
3. Open that session through the `windbg` MCP server and switch to guest WoW mode.
4. Reuse the validated read-only MCP probes first, then isolate why `g` does not stop back on the armed `0x004205BC` breakpoint within the tool timeout.

Canonical command sequence:

1. Re-run:
   - `pwsh -File scripts\trace-life.ps1 -Mode TavernTrace -Launch -TimeoutSeconds 120 -KeepAlive`
2. Load the same Tavern save and let it settle before adding movement.
3. Bootstrap a WinDbg/CDB remote session out-of-band on the already-running process.
4. In Codex, call:
   - `open_windbg_remote(connection_string=...)`
5. Run one command per MCP call:
   - `run_windbg_cmd(command="!wow64exts.sw")`
   - `run_windbg_cmd(command="bp 0x004205BC")`
   - `run_windbg_cmd(command="u 0x004205B0 L10")`
   - `run_windbg_cmd(command="dd 0x004976D0 L1")`
   - `run_windbg_cmd(command="db poi(0x004976D0) L8")`
   - only then retry `run_windbg_cmd(command="g")`
   - if `g` still times out, prefer a different attach timing or broader trigger over repeatedly reusing the same standing-Tavern state
6. Compare against:
   - fingerprint bytes `28 14 00 21 2F 00 23 0D 0E 00`
   - target `0x76 @ 4883`
   - follow-up `loop_reentry @ 4884`
   - `result = tavern_trace_complete`

## Guardrails

- Keep Tavern mode loop-only unless a later pass proves that loop-only is insufficient.
- Keep WinDbg attach-only. Frida or the user gets the process into the right live state first.
- Do not return to shell-managed reconnect clients as the canonical path. Use the `windbg` MCP server once a remote session exists.
- Use one WinDbg command per MCP call instead of semicolon-joined shell batches.
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
- current live-save proof run after the cue/save recovery:
  - [life-trace-20260405-033836.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-033836.jsonl)
- live WinDbg MCP server log for the first real `LBA2.EXE` attach:
  - [mcp-live-lba2-cdb.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-live-lba2-cdb.log)
- live WinDbg MCP log for the resumed-breakpoint investigation:
  - [mcp-live-lba2-breakpoint-test.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-live-lba2-breakpoint-test.log)
- live WinDbg MCP log for the fresh launch-and-attach verification:
  - [mcp-final-launch-attach.log](/D:/repos/reverse/littlebigreversing/work/windbg/mcp-final-launch-attach.log)
- earlier live-save fingerprint match with excessive branch spam:
  - [life-trace-20260405-005345.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-005345.jsonl)
- stable but preset-mismatched Tavern run:
  - [life-trace-20260405-001633.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/life-trace-20260405-001633.jsonl)
- latest typed handoff record:
  - [task_events.jsonl](/D:/repos/reverse/littlebigreversing/docs/codex_memory/task_events.jsonl)
- static interpreter reference:
  - [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)
- Gate 3 debugger workflow:
  - [CDB_GATE3_WORKFLOW.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/CDB_GATE3_WORKFLOW.md)
