# Platform Windows

## Purpose

Own the canonical host assumptions for end-to-end Zig build, test, and runtime verification.

## Invariants

- Treat Windows as the canonical runtime-validation host.
- Use the repo-local SDL2 layout under `vcpkg_installed/x64-windows`.
- Fail fast on missing SDL2 or missing canonical asset roots.

## Current Parity Status

- `zig build test`, `zig build tool`, and `zig build run` are validated through the Windows-first build graph.
- PowerShell helper scripts exist for environment setup and checks.
- A repo-local PowerShell wrapper plus Frida agent can attach to the original Windows `LBA2.EXE` for bounded life-interpreter probes.
- The build graph still hard-codes Windows SDL2 paths.

## Known Traps

- The runtime path is not host-agnostic today.
- Repo-local SDL2 wiring is a checked-in assumption, not an ambient PATH fallback.
- The bounded original-runtime Frida probe is not a general play harness. `scripts/trace-life.ps1 -Launch` now kills its spawned `LBA2.EXE` on exit unless `-KeepAlive` is set, and `-TimeoutSeconds` is the canonical fail-fast way to turn a no-hit wait into an explicit setup failure.
- `scripts/trace-life.ps1 -Mode TavernTrace` is the canonical Windows entrypoint for the raw Tavern trace. It defaults to a `60` second timeout, writes screenshots under `work/life_trace/shots/<run-id>/`, and fails the run if any required screenshot cannot be captured from the live `LBA2` window.

## Canonical Entry Points

- `port/build.zig`
- `scripts/check-env.ps1`
- `scripts/dev-shell.ps1`

## Important Files

- `port/README.md`
- `docs/PHASE1_IMPLEMENTATION_MEMO.md`
- `docs/LBA2_ZIG_PORT_PLAN.md`
- `scripts/trace-life.ps1`

## Test / Probe Commands

- `pwsh -File scripts/check-env.ps1`
- `pwsh -File scripts/dev-shell.ps1`
- `cd port && zig build test`
- `cd port && zig build run`

## Open Unknowns

- Whether host-agnostic build support is ever worth making a first-class goal.
- What future runtime dependencies, beyond SDL2, need explicit Windows packaging policy.
