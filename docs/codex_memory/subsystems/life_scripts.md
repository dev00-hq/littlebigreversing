# Life Scripts

## Purpose

Own the offline life-program decoder boundary, the audit surface for unsupported real-asset life opcodes, and the scene-level branch-B validation used by the current runtime/load seam.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.

## Current Parity Status

- `life_program.zig` is an unwired structural decoder.
- `life_audit.zig` plus `audit-life-programs` is the canonical blocker report and scene-level validation surface.
- `tavern-trace` and `scene11-pair` now use `frida-agent-cli`; `basic` is the direct-Frida fallback.
- `listDecodedInteriorSceneCandidates` confirms `50` decoded interior candidates; the earliest runtime candidate is `SCENE.HQR[19]`.
- `rankDecodedInteriorSceneCandidates` ranks `219` first and `19` at `49/50`.
- `triage-same-index-decoded-interior-candidates` puts `86/86` highest above baseline; `187/187` is the first fragment-bearing compatible pair.
- Only `LM_DEFAULT` and `LM_END_SWITCH` are active unsupported real-asset blockers in the current archive.
- The guarded runtime/load seam still rejects `2/2`, `44/2`, and `11/10`; both `inspect-room` and viewer startup report the first blocking opcode/id/offset before `ViewerUnsupportedSceneLife`.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- The switch-family source pass is complete for the current checked-in evidence; repeating it without new evidence is churn.
- Real asset `LM_BREAK` targets can land on the first byte after `LM_END_SWITCH`, so the classic `saute au END_SWITCH` comment is only a rough control-flow hint, not byte-level structural proof for `LM_END_SWITCH`.
- A useful viewer evidence pair is not automatically guarded-runtime safe; `11/10` still needs the test-only unchecked loader path for fragment evidence.
- `219/219` is still not a guarded room/load candidate; `inspect-room` fails with `InvalidFragmentZoneBounds`.
- `86/86` is only a zero-fragment/zero-GRM compatible pass; keep it distinct from fragment-bearing pairs like `187/187`.
- Guarded negative-load diagnostics report the first blocking life blob only. For `11/10`, that is object `12` `LM_DEFAULT @ 38`, not the later object `18` `LM_END_SWITCH @ 84`.
- On the original-runtime proof lane, use `--fra-repo-root` with both structured modes; `basic` is the only mode that still uses `--frida-repo-root`.
- On the structured `fra` proof lane, spawned `LBA2.EXE` teardown can lag behind tracer return even without `--keep-alive`; recheck after a short delay before assuming cleanup failed.
- On the Tavern late-attach proof lane, keep the hot-path probe slim. Re-adding `ptr_window`, `working_*`, or `exe_switch` reads can bring back intermittent `Application Error` crashes after the fingerprint match.

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
