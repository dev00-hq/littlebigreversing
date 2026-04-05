# WinDbg MCP Workflow For Gate 3

This note is the canonical Gate 3 debugger workflow for the original Windows `LBA2.EXE`.

Use it after the Frida-side Tavern proof is already stable.
Do not use it as a replacement for `scripts\trace-life.ps1`.

## Scope

Canonical role:

- keep Frida responsible for proving the live Tavern path first
- let the Codex app control WinDbg through the configured `windbg` MCP server
- run one WinDbg command per MCP call against an already-existing remote debug session
- keep task-specific probe commands in this note, not in helper scripts

Current non-goals:

- launching the game
- turning `LM_TASKS/` into the repo's product plan
- reviving `scripts\cdb-session.ps1` as the canonical Gate 3 owner
- inventing a second shell-managed reconnect path after the host-freeze evidence from 2026-04-05

## Current Validated Capabilities

The following are already validated on the real `LBA2.EXE` runtime:

- `open_windbg_remote(...)`
- `!wow64exts.sw`
- disassembly at `0x004205B0`
- `dd 0x004976D0 L1`
- `db poi(0x004976D0) L8`
- `qqd`

These facts are no longer hypotheses:

- the configured WinDbg MCP server can control the live remote session
- guest WoW x86 mode switching works
- read-only `DoLife` / `PtrPrg` inspection works
- clean detach returns the game to a responsive state

## Current Blocker

The unresolved problem is narrower than "debugger setup is broken".

Current blocker:

- a late attach to the standing-Tavern state has not yet produced a returning `g` on an armed `bp 0x004205BC` within the MCP timeout window

Current best interpretation:

- this is a timing or trigger-window problem
- it is not an MCP transport problem
- it is not a basic attach/read/detach problem

## Canonical Operator Flow

1. Start from the same live `LBA2.EXE` process that Frida already proved is on the Tavern path.
2. Bootstrap a WinDbg/CDB remote session outside Codex on that already-running process.
   Current rule: keep this step out-of-band until a stable non-freezing local attach method exists.
3. In Codex, use the configured `windbg` MCP server:
   - `open_windbg_remote`
   - `run_windbg_cmd`
   - `send_ctrl_break`
   - `close_windbg_remote`
4. Use one WinDbg command per `run_windbg_cmd` call.
5. Close the remote MCP session when the pass is done.

## Probe Anchors

Start from the checked-in static facts in [DoLife_Report.md](/D:/repos/reverse/littlebigreversing/LM_TASKS/DoLife_Report.md).

Current anchor values:

- `DoLife` entry: `0x00420574`
- opcode-loop site: `0x004205BC`
- `DoFuncLife`: `0x0041F0A8`
- `DoTest`: `0x0041FE30`
- `PtrPrg`: `0x004976D0`
- `TypeAnswer`: `0x004976D4`
- `Value`: `0x00497D44`

Live Tavern proof anchors:

- fingerprint at `PtrLife + 40`:
  - `28 14 00 21 2F 00 23 0D 0E 00`
- bounded window:
  - `4780..4890`
- target:
  - `0x76 @ 4883`
- post-target outcome:
  - `loop_reentry @ 4884`

## Minimal Attach Verification Sequence

Use this when the goal is to confirm attach/read/detach health only:

1. `open_windbg_remote(connection_string=...)`
2. `run_windbg_cmd(command="!wow64exts.sw")`
3. `run_windbg_cmd(command="u 0x004205B0 L10")`
4. `run_windbg_cmd(command="dd 0x004976D0 L1")`
5. `run_windbg_cmd(command="db poi(0x004976D0) L8")`
6. `run_windbg_cmd(command="qqd")`

## Breakpoint-Return Investigation Sequence

Use this only after the minimal attach verification still looks healthy:

1. `open_windbg_remote(connection_string=...)`
2. `run_windbg_cmd(command="!wow64exts.sw")`
3. `run_windbg_cmd(command="u 0x004205B0 L10")`
4. `run_windbg_cmd(command="dd 0x004976D0 L1")`
5. `run_windbg_cmd(command="db poi(0x004976D0) L8")`
6. `run_windbg_cmd(command="bp 0x004205BC")`
7. `run_windbg_cmd(command="g")`
8. If the target needs a fresh break-in, `send_ctrl_break(connection_string=...)`
9. `run_windbg_cmd(command="qqd")`

If `g` still does not return, change the live timing or trigger window before adding more debugger machinery.

## Operator Rules

- Treat the MCP server as the canonical Codex control surface for Gate 3.
- Do not use `scripts\cdb-session.ps1` as the active Gate 3 path.
- Do not send semicolon-joined WinDbg batches through shell reconnect clients.
- Do not rely on desktop screenshots as debugger-state proof.
- Keep Frida or the user responsible for getting the target into the right live state first.
- Prefer a different attach timing or in-game trigger over repeatedly reusing the same standing-Tavern breakpoint test.

## Acceptance

Gate 3 is wired correctly when all of these are true:

- Frida still proves the Tavern path first
- Codex can open the remote debugger session through the `windbg` MCP server
- one-command MCP calls return cleanly without leaving Codex at an interactive debugger prompt
- read-only probe output is captured through WinDbg command results
- clean detach is preserved with `qqd`

The remaining success condition for the next narrow pass is:

- either capture one attributed breakpoint return from the correct live trigger window
- or prove that a different attach timing is required before breakpoint-based attribution can succeed
