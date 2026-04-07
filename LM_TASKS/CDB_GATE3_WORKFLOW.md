# WinDbg MCP Workflow For Gate 3

This note is the canonical Gate 3 debugger workflow for the branch-A proof gate sprint on the original Windows `LBA2.EXE`.

Use it after the Frida-side lane is already live.
Do not use it as a replacement for `scripts\trace-life.ps1`.

## Scope

Canonical role:

- keep Frida responsible for getting the process into the right live lane first
- let the Codex app control WinDbg through the configured `windbg` MCP server
- run one WinDbg command per MCP call against an already-existing remote debug session
- standardize the attach timing around pre-window attribution instead of late standing-state attach

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

- a late attach to the already-settled Tavern standing state has not yet produced a returning `g` on an armed breakpoint within the MCP timeout window

Current best interpretation:

- this is a timing or trigger-window problem
- it is not an MCP transport problem
- it is not a basic attach/read/detach problem

## Canonical Operator Flow

1. Start from a Frida-proved live process.
2. For this sprint, attach before the live trigger window is missed:
   - Frida launches with `-KeepAlive`
   - the user loads the canonical save and lets it settle
   - WinDbg attaches before the trigger input or animation window that should hit the target opcode
3. Bootstrap a WinDbg/CDB remote session outside Codex on that already-running process.
4. In Codex, use the configured `windbg` MCP server:
   - `open_windbg_remote`
   - `run_windbg_cmd`
   - `send_ctrl_break`
   - `close_windbg_remote`
5. Use one WinDbg command per `run_windbg_cmd` call.
6. Close the remote MCP session when the pass is done.

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

Live lane anchors:

- Tavern baseline:
  - fingerprint `PtrLife + 40`
  - target `0x76 @ 4883`
  - post-target `loop_reentry @ 4884`
- scene-11 pair:
  - fingerprint on object `12` `PtrLife + 30`
  - primary target object `12` `0x74 @ 38`
  - comparison target object `18` `0x76 @ 84`

## Minimal Attach Verification Sequence

Use this when the goal is to confirm attach/read/detach health only:

1. `open_windbg_remote(connection_string=...)`
2. `run_windbg_cmd(command="!wow64exts.sw")`
3. `run_windbg_cmd(command="u 0x00420574 L20")`
4. `run_windbg_cmd(command="u 0x004205BC L20")`
5. `run_windbg_cmd(command="dd 0x004976D0 L1")`
6. `run_windbg_cmd(command="dd 0x004976D4 L1")`
7. `run_windbg_cmd(command="dd 0x00497D44 L1")`
8. `run_windbg_cmd(command="db poi(0x004976D0) L8")`
9. `run_windbg_cmd(command="qqd")`

## Breakpoint Attribution Sequence

Use this only after the minimal attach verification still looks healthy and the target is already in the correct live lane:

1. `open_windbg_remote(connection_string=...)`
2. `run_windbg_cmd(command="!wow64exts.sw")`
3. `run_windbg_cmd(command="u 0x00420574 L20")`
4. `run_windbg_cmd(command="u 0x004205BC L20")`
5. `run_windbg_cmd(command="dd 0x004976D0 L1")`
6. `run_windbg_cmd(command="dd 0x004976D4 L1")`
7. `run_windbg_cmd(command="dd 0x00497D44 L1")`
8. `run_windbg_cmd(command="bp 0x00420574")`
9. `run_windbg_cmd(command="bp 0x004205BC")`
10. `run_windbg_cmd(command="g")`
11. If the target needs a fresh break-in, `send_ctrl_break(connection_string=...)`
12. `run_windbg_cmd(command="qqd")`

Important current rule:

- arm `0x00420574` first and `0x004205BC` second
- do this before the lane-specific trigger window, not after the process has already parked in a stale settled state

If `g` still does not return, change the live timing or trigger window before adding more debugger machinery.

## Operator Rules

- Treat the MCP server as the canonical Codex control surface for Gate 3.
- Do not use `scripts\cdb-session.ps1` as the active Gate 3 path.
- Do not send semicolon-joined WinDbg batches through shell reconnect clients.
- Do not rely on desktop screenshots as debugger-state proof.
- Keep Frida or the user responsible for getting the target into the right live state first.
- Prefer a different attach timing or in-game trigger over repeatedly reusing the same standing-Tavern breakpoint test.
- Keep this sprint proof-only:
  - no x64dbg fallback
  - no shell-managed `cdb` recovery loop
  - no interpreter implementation in the same pass

## Acceptance

Gate 3 is wired correctly when all of these are true:

- Frida still proves the lane first
- Codex can open the remote debugger session through the `windbg` MCP server
- one-command MCP calls return cleanly without leaving Codex at an interactive debugger prompt
- read-only probe output is captured through WinDbg command results
- clean detach is preserved with `qqd`

The remaining success condition for this sprint is:

- either capture at least one attributed breakpoint return from each intended live lane
- or prove concretely that a different attach timing is required before breakpoint-based attribution can succeed
