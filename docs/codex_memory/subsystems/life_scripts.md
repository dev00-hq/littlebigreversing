# Life Scripts

## Purpose

Own the offline life-program decoder boundary and the canonical audit surface for unsupported real-asset life opcodes.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.

## Current Parity Status

- `life_program.zig` is an unwired structural decoder.
- `life_audit.zig` plus `audit-life-programs` is the canonical blocker report.
- Only `LM_DEFAULT` and `LM_END_SWITCH` are active unsupported real-asset blockers in the current archive.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- The switch-family source pass is complete for the current checked-in evidence; repeating it without new evidence is churn.

## Canonical Entry Points

- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/life_audit.zig`
- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`

## Important Files

- `port/src/game_data/scene/tests/life_program_tests.zig`
- `port/src/game_data/scene/tests/life_audit_tests.zig`
- `port/src/tools/cli.zig`

## Test / Probe Commands

- `cd port && zig build tool -- audit-life-programs --json`
- `cd port && zig build tool -- audit-life-programs --json --all-scene-entries`
- `cd port && zig build test`

## Open Unknowns

- Whether future product boundaries will reject unsupported switch-family opcodes instead of decoding them.
- What minimum checked-in evidence would be strong enough to widen the supported decoder boundary.
