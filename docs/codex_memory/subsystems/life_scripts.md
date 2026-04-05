# Life Scripts

## Purpose

Own the offline life-program decoder boundary, the canonical audit surface for unsupported real-asset life opcodes, and the scene-level branch-B validation used by the current runtime/load seam.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.

## Current Parity Status

- `life_program.zig` is an unwired structural decoder.
- `life_audit.zig` plus `audit-life-programs` is the canonical blocker report and scene-level validation surface.
- `tools/life_trace/` plus `scripts/trace-life.ps1` provide the bounded original-runtime probe for `DoLife` owner and `PtrPrg` attribution without manual register inspection.
- `scripts/trace-life.ps1 -Mode TavernTrace` is the canonical scene-5 probe: it gates on the hero-life fingerprint, hooks the `LM_SWITCH` / `LM_CASE` / `LM_OR_CASE` / `LM_BREAK` paths in the original runtime, captures bounded Tavern screenshots by host-minted event id, and emits a single terminal verdict.
- The current canonical Tavern live-save proof is: fingerprint match at `PtrLife + 40` -> `0x76 @ 4883` -> bounded `loop_reentry` at `4884`; byte-window capture is restored, and `LM_BREAK` remains supporting evidence instead of a required proof gate.
- `listDecodedInteriorSceneCandidates` currently proves there are `50` fully-decoded interior candidates; the earliest canonical runtime candidate is `SCENE.HQR[19]` (`classic_loader_scene_number = 17`, `blob_count = 3`).
- Only `LM_DEFAULT` and `LM_END_SWITCH` are active unsupported real-asset blockers in the current archive.
- The guarded runtime/load seam rejects unsupported scene life before later interior/exterior widening; `2/2`, `44/2`, and `11/10` are negative guarded load cases, with `11/10` preserved only on explicit test-only evidence paths.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- The switch-family source pass is complete for the current checked-in evidence; repeating it without new evidence is churn.
- Real asset `LM_BREAK` targets can land on the first byte after `LM_END_SWITCH`, so the classic `saute au END_SWITCH` comment is only a rough control-flow hint, not byte-level structural proof for `LM_END_SWITCH`.
- A useful viewer evidence pair is not automatically a guarded runtime-safe scene; `11/10` still crosses unsupported scene life and now requires the test-only unchecked loader path for fragment evidence coverage.
- TavernTrace screenshot capture is part of the acceptance artifact, not optional decoration. A missing required screenshot is a terminal tracer failure, not a warning.

## Canonical Entry Points

- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/life_audit.zig`
- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`

## Important Files

- `port/src/game_data/scene/tests/life_program_tests.zig`
- `port/src/game_data/scene/tests/life_audit_tests.zig`
- `port/src/tools/cli.zig`
- `tools/life_trace/trace_life.py`
- `tools/life_trace/agent.js`
- `scripts/trace-life.ps1`

## Test / Probe Commands

- `cd port && zig build tool -- audit-life-programs --json`
- `cd port && zig build tool -- audit-life-programs --json --all-scene-entries`
- `cd port && zig build test`

## Open Unknowns

- What the next bounded gameplay/runtime widening step should be on the supported `19/19` path without adding life execution.
- What minimum checked-in evidence would be strong enough to widen the supported decoder boundary beyond explicit rejection.
