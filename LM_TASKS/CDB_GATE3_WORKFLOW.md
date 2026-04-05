# WinDbg MCP Workflow For Gate 3

This note is the canonical Gate 3 debugger workflow for the original Windows `LBA2.EXE`.

Use it after the Frida-side repro loop is already stable. Do not use it as a replacement for `scripts\trace-life.ps1`.

Use it with:

- [LM_PLAN.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/LM_PLAN.md)
- [GATE2_REPRO_SHEET.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/GATE2_REPRO_SHEET.md)
- [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md)

## Scope

Canonical role:

- keep Frida responsible for proving the live Tavern repro path first
- let the Codex app control WinDbg through the configured `windbg` MCP server
- run one WinDbg command per MCP call against an already-existing remote debug session
- keep task-specific probe commands in this note, not in helper scripts

Current non-goals:

- launching the game
- using `scripts\cdb-session.ps1` as the canonical Gate 3 owner
- inventing a second local attach workflow after the host-freeze evidence from 2026-04-05

## Canonical Operator Flow

1. Start from the same live `LBA2.EXE` process that Frida already proved is on the Tavern repro path.
2. Bootstrap a WinDbg/CDB remote session outside Codex on that already-running process.
   Current rule: keep this step out-of-band until a stable non-freezing local attach method exists.
3. In the Codex app, use the configured `windbg` MCP server to control that remote session:
   - `open_windbg_remote`
   - `run_windbg_cmd`
   - `send_ctrl_break`
   - `close_windbg_remote`
4. Use one WinDbg command per `run_windbg_cmd` call.
5. Close the remote MCP session when the pass is done.

## Operator Rules

- Treat the MCP server as the canonical Codex control surface for Gate 3.
- Do not use `scripts\cdb-session.ps1` as the active Gate 3 path. That wrapper is now historical/experimental only after host freezes reproduced on both `LBA2.EXE` and a disposable console target.
- Do not send semicolon-joined WinDbg command batches through ad hoc shell clients.
- Do not rely on desktop screenshots as debugger-state proof. The bounded Frida screenshots stay useful for the repro loop, but debugger-state evidence must come from WinDbg command output.
- Keep Frida or the user responsible for getting the target into the right live state first. The MCP layer is for attribution after the repro is proven.

## Current Probe Sheet

Start from the current checked-in `DoLife` addresses in [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md).

Current anchor values:

- `DoLife` entry: `0x00420574`
- opcode-loop site: `0x004205BC`
- `DoFuncLife`: `0x0041F0A8`
- `DoTest`: `0x0041FE30`
- `PtrPrg`: `0x004976D0`
- `TypeAnswer`: `0x004976D4`
- `Value`: `0x00497D44`

Useful first-pass WinDbg commands:

- `bp 0x004205BC`
- `g`
- `dd 0x004976D0 L1`
- `db poi(0x004976D0) L8`
- `r`
- `kb`

Recommended first MCP sequence after the remote session is open:

1. `open_windbg_remote(connection_string=...)`
2. `run_windbg_cmd(command="bp 0x004205BC")`
3. `run_windbg_cmd(command="g")`
4. If the target is running and you need a fresh break-in, `send_ctrl_break(connection_string=...)`
5. `run_windbg_cmd(command="dd 0x004976D0 L1")`
6. `run_windbg_cmd(command="db poi(0x004976D0) L8")`
7. `run_windbg_cmd(command="r")`
8. `run_windbg_cmd(command="kb")`
9. `close_windbg_remote(connection_string=...)`

## Acceptance

Gate 3 is wired correctly when all of these are true:

- Frida still proves the Tavern path first
- Codex can open the remote debugger session through the `windbg` MCP server
- one-command MCP calls return cleanly without leaving Codex at an interactive debugger prompt
- the opcode-loop probe output is captured through WinDbg command results, not shell-managed remote clients
