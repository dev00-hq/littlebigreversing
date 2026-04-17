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
- `zig build test-fast` plus targeted tool probes are the slice-grade loop; `scripts/verify_viewer.py --fast` is the broader staged-binary pass, and bare `scripts/verify_viewer.py` is the milestone acceptance gate.
- `scripts/verify_viewer.py` keeps expected-failure CLI probes on the pass path while preserving the raw rejection lines needed by its assertions.
- Python helper scripts now own the canonical environment setup and checks.
- Repo-relative script paths stay canonical; `pyproject.toml` entrypoints remain optional scaffolding.
- Original-runtime trace/debugger helpers still exist for evidence work but are not part of the default port pickup path; use `docs/codex_memory/subsystems/life_scripts.md` for Tavern, Scene11, Frida, or `cdb-agent`.

## Known Traps

- The runtime path is not host-agnostic today.
- Repo-local SDL2 wiring is a checked-in assumption, not an ambient PATH fallback.
- Canonical Zig validation should run from native PowerShell through `py -3 .\scripts\dev-shell.py`; use Bash helpers for inspection, not as the default build wrapper.
- In native PowerShell, piping `zig build ...` through `Out-String` can turn a successful build into an observed exit code of `-1`, and ad hoc native-command capture can still rewrap raw stderr; keep `scripts/verify_viewer.py` plus `scripts/dev-shell.py exec` as the canonical scripted path when exit status matters.
- Even `zig build test-fast` can be too slow for always-on validation. For slice work, prefer the smallest targeted `zig build tool -- ...` probes, add `zig build test-fast` for shared runtime/viewer changes, use `scripts/verify_viewer.py --fast` for staged-binary checks, and reserve bare `scripts/verify_viewer.py` for milestone closeout.
- Original-runtime probes and debugger runbooks are supporting evidence work, not default canonical memory pickup. Do not treat `LM_TASKS/` or older shell-managed debugger wrappers as execution owners for the port path.
- In a `.codex/worktrees/...` checkout, original-runtime helpers may need binaries from `D:\repos\reverse\littlebigreversing\work\...`; do not assume extracted runtime assets are mirrored under the current worktree's `work/` tree.
- The checked-in Ghidra project under `.codex/worktrees/...` is not a stable automation target for `ghb` on this setup. If Ghidra reports `project locked` or `Path element starting with ':' is not permitted`, relaunch against a disposable project outside the Codex worktree instead of retrying the locked one.
- Interrupted viewer launches can leave `port/zig-out/bin/lba2.exe` locked and cause `AccessDenied` on the next install step; clear the stale `lba2.exe` process before blaming the code.

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
