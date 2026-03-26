# Platform Linux

## Purpose

Capture the current Linux Bash boundary so repo analysis work does not overclaim support for the canonical port runtime workflow.

## Invariants

- Treat Linux Bash as analysis/docs/source-work only for now.
- Do not present Linux as a supported end-to-end `zig build` or `zig build run` host until the build graph changes deliberately.
- Prefer Bash-native repo inspection tools when the host is actually Bash.

## Current Parity Status

- Linux Bash is suitable for documentation work, search, and memory/tooling maintenance.
- The checked-in runtime build graph is still Windows-first.
- No separate Linux runtime packaging path exists.

## Known Traps

- The shell-detection snippet in `AGENTS.md` is misleading when run literally from Bash.
- Existing helper scripts and SDL2 wiring target Windows, not a Linux-native toolchain layout.

## Canonical Entry Points

- `AGENTS.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `port/build.zig`

## Important Files

- `docs/PHASE1_IMPLEMENTATION_MEMO.md`
- `scripts/check-env.ps1`
- `scripts/dev-shell.ps1`

## Test / Probe Commands

- `bash -lc "python3 tools/codex_memory.py validate"`
- `bash -lc "rg --files"`

## Open Unknowns

- Whether Linux should ever move from analysis host to supported runtime host.
- Which build/dependency changes would be required before that claim is honest.
