# Life Scripts

## Purpose

Own the offline life-program decoder boundary, unsupported-opcode audit surface, and the original-runtime proof lane.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is the canonical blocker report and scene-level validation surface.
- `tavern-trace` and `scene11-pair` now use `frida-agent-cli`; `basic` is the direct-Frida fallback.
- `tools/life_trace/trace_life.py` is a thin facade; add scenes through `tools/life_trace/scenes/registry.py`.
- `tools/life_trace/trace_life.py` now writes run bundles under `work/life_trace/runs/<run-id>/` with `manifest.json`, `raw.jsonl`, `enriched.jsonl`, and `screenshots/`.
- `tools/life_trace/agent.js` is assembled from tracked scene fragments; let scenes own hook topology when live proof is sensitive to wrappers.
- `scene11-pair` now treats `work/ghidra_projects/callsites/lm_helper_callsites.jsonl` as a required static artifact and emits additive `helper_callsite` evidence that the host enriches by `(callee_name, caller_static_rel)`.
- `listDecodedInteriorSceneCandidates` confirms `50` decoded interior candidates; the earliest runtime candidate is `SCENE.HQR[19]`.
- Only `LM_DEFAULT` and `LM_END_SWITCH` are active unsupported real-asset blockers in the current archive.
- The guarded runtime/load seam still rejects `2/2`, `44/2`, and `11/10`; both `inspect-room` and viewer startup report the first blocking opcode/id/offset.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- The switch-family source pass is complete for the current checked-in evidence; repeating it without new evidence is churn.
- Real asset `LM_BREAK` targets can land on the first byte after `LM_END_SWITCH`, so the classic `saute au END_SWITCH` comment is only a rough control-flow hint, not byte-level structural proof for `LM_END_SWITCH`.
- A useful viewer evidence pair is not automatically guarded-runtime safe; `11/10` still needs the test-only unchecked loader path for fragment evidence.
- `219/219` is still not a guarded room/load candidate; `inspect-room` fails with `InvalidFragmentZoneBounds`.
- `86/86` is only a zero-fragment/zero-GRM compatible pass; keep it distinct from fragment-bearing pairs like `187/187`.
- Guarded negative-load diagnostics report only the first blocking blob. For `11/10`, that is object `12` `LM_DEFAULT @ 38`, not object `18` `LM_END_SWITCH @ 84`.
- On the original-runtime proof lane, use `--fra-repo-root` for both structured modes; `basic` alone still uses `--frida-repo-root`.
- Owned structured `--launch` runs fall back from `fra target terminate` to a direct kill after a short grace window; a leftover `LBA2.EXE` is abnormal.
- A structured Tavern run can still finish and then time out on `fra target terminate`; if daemon health is clean right after and the target lands in `terminated`, treat that as teardown noise.
- Keep the Tavern late-attach hot path slim. Re-adding `ptr_window`, `working_*`, or `exe_switch` reads can bring back intermittent `Application Error` crashes.
- The `agent.js` split is only safe when live Tavern still reaches `tavern_trace_complete`; the generic `DoLife` loop wrapper regressed the post-`0x76` proof until Tavern owned its own hook install.
- `raw.jsonl` is the runtime-truth stream and `enriched.jsonl` is the host-analysis companion. If helper attribution looks wrong, inspect `raw.jsonl` before treating the joined fields in `enriched.jsonl` as a runtime regression.

## Canonical Entry Points

- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/life_audit.zig`
- `docs/PHASE2_LIFE_PROGRAM_EVIDENCE.md`

## Important Files

- `tools/life_trace/trace_life.py`
- `tools/life_trace/scenes/registry.py`
- `tools/life_trace/agent/scene_tavern.js`

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
