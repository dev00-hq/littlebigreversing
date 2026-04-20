# Platform Windows

## Purpose

Own the canonical host assumptions for end-to-end Zig build, test, and runtime verification.

## Invariants

- Treat Windows as the canonical runtime-validation host.
- Use the repo-local SDL2 layout under `vcpkg_installed/x64-windows`.
- Fail fast on missing SDL2 or missing canonical asset roots.

## Current Parity Status

- `zig build test`, `zig build tool`, and `zig build run` are validated through the Windows-first build graph.
- The build graph also exposes `zig build test-fast`, `zig build test-life-audit-all`, and `zig build stage-viewer`.
- `zig build test-fast` plus targeted tool probes are the slice loop; `scripts/verify_viewer.py --fast` is the broader staged-binary pass, and bare `scripts/verify_viewer.py` is the milestone gate.
- Original-runtime trace/debugger helpers still exist for evidence work but are not part of the default port pickup path; use `docs/codex_memory/subsystems/life_scripts.md` for Tavern, Scene11, Frida, or `cdb-agent`.

## Known Traps

- The runtime path is not host-agnostic today.
- Repo-local SDL2 wiring is a checked-in assumption, not an ambient PATH fallback.
- Run canonical Zig validation from native PowerShell via `py -3 .\scripts\dev-shell.py`; Bash helpers are for inspection only.
- `zig build ... | Out-String` can misreport success as exit code `-1`; use `scripts/dev-shell.py exec` or `scripts/verify_viewer.py` when exit status matters.
- Prefer targeted tool probes first, `zig build test-fast` for shared runtime/viewer changes, `scripts/verify_viewer.py --fast` for staged-binary checks, and bare `scripts/verify_viewer.py` only for milestone closeout.
- Original-runtime probes are evidence helpers, not default canonical memory pickup.
- In `.codex/worktrees/...`, original-runtime helpers may still need binaries from `D:\repos\reverse\littlebigreversing\work\...`.
- The checked-in Ghidra project under `.codex/worktrees/...` is not a stable `ghb` target; if it reports `project locked` or `Path element starting with ':' is not permitted`, relaunch against a disposable project outside the worktree.
- Interrupted viewer launches can leave `port/zig-out/bin/lba2.exe` locked and cause `AccessDenied` on the next install step; clear the stale `lba2.exe` process before blaming the code.
- On this host, original `LBA2.EXE` stability depends on the external DxWnd runtime at `C:\Users\sebam\DxWnd.reloaded\build\dxwnd.exe`. The custom repo target in `dxwnd.ini` can hang in `DDRAW`/`dxwnd`/`apphelp` surface creation, while disabling DxWnd entirely exits when gameplay surfaces initialize. The built-in `Little Big Adventure 2 (Windows patch)` template is more startup-stable, but its `winver0=1` path can still crash with a privileged-instruction dialog: `0x0045BFAE` is `MOV EAX, CR0` inside `FUN_0045BD62`.
- The current best-known repo-local DxWnd candidate is `tools/life_trace/profiles/lba2_built_in_flag_core_candidate.dxw`: built-in template base, `winver0=0`, stable custom flag core (`flag0`, `flagg0`, `flagh0`, `flagi0`), and the windowed presentation cluster (`flagj0`, `flagk0`, `dflag0`, `initresw0`, `initresh0`, `slowratio0`, `scanline0`) plus the `[window]` section. A direct-save room-36 smoke on `2026-04-20` kept it alive and windowed for 30 seconds at `816x639` with no `Application Error` dialog.

## Canonical Entry Points

- `port/build.zig`
- `scripts/check-env.py`
- `scripts/dev-shell.py`

## Important Files

- `port/README.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `scripts/verify_viewer.py`

## Test / Probe Commands

- `py -3 scripts/check-env.py`
- `py -3 scripts/dev-shell.py shell`
- `py -3 scripts/dev-shell.py exec --cwd port -- zig build test-fast`
- `py -3 .\scripts\verify_viewer.py --fast`
- `py -3 scripts/dev-shell.py exec --cwd port -- zig build test`
- `py -3 .\scripts\verify_viewer.py`

## Open Unknowns

- Whether host-agnostic build support is ever worth making a first-class goal.
- What future runtime dependencies, beyond SDL2, need explicit Windows packaging policy.
