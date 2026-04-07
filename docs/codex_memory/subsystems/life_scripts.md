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
- `listDecodedInteriorSceneCandidates` proves there are `50` fully decoded interior candidates; the earliest canonical runtime candidate is `SCENE.HQR[19]` (`classic_loader_scene_number = 17`, `blob_count = 3`).
- `rankDecodedInteriorSceneCandidates` plus `rank-decoded-interior-candidates` rank those `50` candidates by `track_count`, `object_count`, `zone_count`, `blob_count`, and `scene_entry_index`; `219` is first and `19` is `49/50`.
- `triage-same-index-decoded-interior-candidates` reuses that ranking with `room_state`: `86/86` is the highest-ranked compatible pair above baseline; `187/187` is the first fragment-bearing compatible pair.
- Only `LM_DEFAULT` and `LM_END_SWITCH` are active unsupported real-asset blockers in the current archive.
- The guarded runtime/load seam still rejects `2/2`, `44/2`, and `11/10`, and both `inspect-room` and viewer startup report the first blocking opcode/id/offset before `ViewerUnsupportedSceneLife`.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- The switch-family source pass is complete for the current checked-in evidence; repeating it without new evidence is churn.
- Real asset `LM_BREAK` targets can land on the first byte after `LM_END_SWITCH`, so the classic `saute au END_SWITCH` comment is only a rough control-flow hint, not byte-level structural proof for `LM_END_SWITCH`.
- A useful viewer evidence pair is not automatically a guarded runtime-safe scene; `11/10` still crosses unsupported scene life and needs the test-only unchecked loader path for fragment evidence.
- A top-ranked decoded interior candidate is not automatically a guarded room/load candidate; `219/219` still fails `inspect-room` with `InvalidFragmentZoneBounds`, now with explicit per-zone diagnostics before the error.
- A compatible same-index candidate is not automatically fragment evidence; `86/86` clears only because it has zero fragments and zero GRM zones, so keep it distinct from fragment-bearing pairs such as `187/187`.
- Guarded negative-load diagnostics report the first blocking life blob only. For `11/10`, that is object `12` `LM_DEFAULT @ 38`, not the later object `18` `LM_END_SWITCH @ 84`.

## Canonical Entry Points

- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/life_audit.zig`
- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`

## Important Files

- `port/src/game_data/scene/tests/life_program_tests.zig`
- `port/src/game_data/scene/tests/life_audit_fast_tests.zig`
- `port/src/game_data/scene/tests/life_audit_all_scene_tests.zig`
- `port/src/tools/cli.zig`
- `tools/life_trace/trace_life.py`
- `tools/life_trace/agent.js`
- `scripts/trace-life.ps1`

## Test / Probe Commands

- `cd port && zig build tool -- audit-life-programs --json`
- `cd port && zig build tool -- audit-life-programs --json --all-scene-entries`
- `cd port && zig build tool -- triage-same-index-decoded-interior-candidates --json`
- `cd port && zig build test-fast`
- `cd port && zig build test-life-audit-all`
- `cd port && zig build test`

## Open Unknowns

- What the next bounded gameplay/runtime widening step should be on the supported `19/19` path without adding life execution.
- What minimum checked-in evidence would be strong enough to widen the supported decoder boundary beyond explicit rejection.
