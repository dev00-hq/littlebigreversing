# Life Scripts

## Purpose

Own the offline life-program decoder boundary, unsupported-opcode audit surface, and the original-runtime proof lane.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is the canonical blocker report and scene-level validation surface.
- `tavern-trace` uses `frida-agent-cli`, `scene11-pair` now uses a debugger-owned `cdb` snapshot lane, and `basic` remains the direct-Frida fallback.
- `tools/life_trace/trace_life.py` is a thin facade; add scenes through `tools/life_trace/scenes/registry.py`.
- `tools/life_trace/trace_life.py` now writes run bundles under `work/life_trace/runs/<run-id>/` with `manifest.json`, `raw.jsonl`, `enriched.jsonl`, and `screenshots/`.
- `tools/life_trace/agent.js` is assembled from tracked scene fragments for the Frida-backed lanes only; let Tavern own hook topology when live proof is sensitive to wrappers.
- `scene11-pair --launch` is now the canonical debugger-owned Scene11 lane: keep `SAVE` at `current.lba` plus `SHOOT/`, stage exactly one extra `.lba` from `work/saves`, drive `Load Game` on the sole visible slot, wait for the room to settle, and then capture a `cdb` snapshot plus screenshots into the run bundle.
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
- On the original-runtime proof lane, `--fra-repo-root` is now Tavern-only; `scene11-pair` is debugger-backed and takes an optional `--cdb-path`, while `basic` alone still uses `--frida-repo-root`.
- Owned structured `--launch` runs fall back from `fra target terminate` to a direct kill after a short grace window; a leftover `LBA2.EXE` is abnormal.
- A structured Tavern run can still finish and then time out on `fra target terminate`; if daemon health is clean right after and the target lands in `terminated`, treat that as teardown noise.
- Keep the Tavern late-attach hot path slim. Re-adding `ptr_window`, `working_*`, or `exe_switch` reads can bring back intermittent `Application Error` crashes.
- The `agent.js` split is only safe when live Tavern still reaches `tavern_trace_complete`; the generic `DoLife` loop wrapper regressed the post-`0x76` proof until Tavern owned its own hook install.
- `raw.jsonl` is the runtime-truth stream and `enriched.jsonl` is the host-analysis companion. If helper attribution looks wrong, inspect `raw.jsonl` before treating the joined fields in `enriched.jsonl` as a runtime regression.
- The canonical runtime `SAVE` folder is now `current.lba` plus `SHOOT/` only. For controlled Tavern and Scene11 launches, stage one extra save from `work/saves`, load it through the sole visible `Load Game` slot, and then delete it after the run.
- On `2026-04-11`, a no-Frida single-slot `Load Game` control run proved `S8741.LBA` stays responsive in Scene11 for at least 30 seconds after load. Treat later freezes as probe-boundary evidence first, not as proof that the save failed to load.
- The current Scene11 freeze story is narrower and more state-sensitive than the older notes suggested. The `2026-04-11` runs did freeze around the generic live seam, but the `2026-04-13` direct-Frida retries under the corrected mounted-ISO `Load Game` path kept both a bare `DoLifeEntry` hook and a `DoLifeEntry` hook with `PtrLife` / `OffsetLife` snapshots responsive for 40 seconds: [summary.json](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/scene11-seam-probes-20260413/summary.json).
- The safe seams we have now are: no-op late attach, bare `DoLifeLoop`, paused one-shot `cdb` reads, and minimal `DoLifeEntry` probes. What is still unproven is the full generic Scene11 live seam with broader hook composition or hot-path loop-state reads. Keep that distinction explicit.
- The two inner proof models crossed successfully on `2026-04-13`, but only as bounded experiments. A Tavern-style slim live loop seam worked on Scene11 and captured repeated object-`2` `0x76 @ 103` hits in [scene11_tavern_style_loop_only.json](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/scene11-seam-probes-20260413/scene11_tavern_style_loop_only.json). A Scene11-style `cdb` snapshot worked on Tavern and captured matching fingerprint bytes plus a matching `0x76` target byte in [tavern_scene11_style_snapshot.json](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/scene11-seam-probes-20260413/tavern_scene11_style_snapshot.json).
- Keep the outer harness unified and the inner seams split. The cross-model success proves portability, not that one canonical inner proof model should replace Tavern’s live behavior proof or Scene11’s snapshot ownership proof.
- The canonical `scene11-pair` lane is no longer the Frida helper/callsite path. On `2026-04-13`, once the ISO mount was corrected, the debugger-owned snapshot lane launched, loaded `S8741.LBA`, captured screenshots of the real Neighbour's House room, read memory through `cdb`, and exited cleanly. The current blocker is now a static-vs-runtime identity mismatch, not startup: canonical objects `12` and `18` were null, but the built-in discovery scan found live object `2` carrying `LM_DEFAULT (0x74)` at offset `96` and `LM_END_SWITCH (0x76)` at offset `103`.
- A clean repeat on the same `S8741.LBA` save reproduced the loaded Neighbour's House room and the null canonical objects, but it fell back to `scene11_primary_ptr_life_missing` without rediscovering object `2`. Treat the object-`2` windows as an interesting live lead, not as the new proof contract, until a second independent Scene11 save or state repeats the same owner.
- A second clean repeat on the same `S8741.LBA` save then reproduced the object-`2` windows and `scene11_static_runtime_mismatch` again. Across the three current live runs, the useful discriminator is `global_ptr_prg`: when the snapshot catches a non-null `PtrPrg`, the built-in discovery scan finds `LM_DEFAULT` and `LM_END_SWITCH` on live object `2`; when `PtrPrg` is still `0`, the lane falls back to `scene11_primary_ptr_life_missing`. Keep the proof contract explicit, but treat runtime-owner discovery as state-sensitive rather than purely non-repeatable.
- The first full Scene11 challenger built on the Tavern-style slim live loop seam did prove both required unsupported offsets on live object `2`, but the clean-process repeat on `2026-04-13` regressed into the same null-read `Application Error` dialog instead of finalizing. Only the loaded/final screenshots were preserved in [scene11_tavern_style_full_lane_repeat2_loaded.png](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/scene11-seam-probes-20260413/scene11_tavern_style_full_lane_repeat2_loaded.png) and [scene11_tavern_style_full_lane_repeat2_final.png](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/scene11-seam-probes-20260413/scene11_tavern_style_full_lane_repeat2_final.png). Do not replace the debugger-owned Scene11 lane with that challenger until it repeats cleanly.
- The canonical Tavern live owner still reproves cleanly after the failed Scene11 challenger repeat. The clean-process rerun at [life-trace-20260413-013205/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-013205/enriched.jsonl) again reached `tavern_trace_complete`, so the shared single-slot `Load Game` harness remains sound and the instability currently belongs to the Scene11 slim-live challenger.
- `trace_life.py --launch` now owns preflight cleanup in code: it hard-kills any pre-existing `LBA2.EXE` and `cdb.exe` before starting an owned run. Treat that as current-state launcher policy, not as a hint for manual sessions.
- The owned runtime loops now fail fast on the `Application Error` window title instead of hanging through timeouts. This shipped with focused unit coverage in [test_life_trace.py](/D:/repos/reverse/littlebigreversing/tools/test_life_trace.py) and a full suite pass of `py -3 -m unittest tools.test_life_trace`.
- After that runtime hygiene change, both canonical live lanes were revalidated: Tavern still completed `tavern_trace_complete` in [life-trace-20260413-014226/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-014226/enriched.jsonl), and Scene11 still completed the debugger-owned mismatch lane in [life-trace-20260413-014318/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-014318/enriched.jsonl).
- There is now one explicit non-canonical Scene11 challenger mode in the repo: `scene11-live-pair`. It is direct-Frida-backed, reuses the Scene11 load/save bootstrap, and tries to prove the live object-`2` pair by observing `LM_DEFAULT@96` and `LM_END_SWITCH@103` on the same thread.
- Switching `scene11-live-pair` from FRA to a repo-owned direct-Frida structured backend did not clear the crash boundary. Even after adding three pre-attach settle polls and deferring the `loaded_scene` screenshot, two fresh owned runs still failed immediately after attach with `scene11_live_pair_application_error` in [life-trace-20260413-021607/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-021607/enriched.jsonl) and [life-trace-20260413-021934/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-021934/enriched.jsonl). Treat that as current checked-in evidence that the Scene11 live challenger is still not promotable.
- The canonical Tavern owner still clearly needs its current live behavior-proof contract. A fresh rerun after the failed direct-Frida Scene11 challenger attempts still completed `tavern_trace_complete` in [life-trace-20260413-022253/enriched.jsonl](/D:/repos/reverse/littlebigreversing/work/life_trace/runs/life-trace-20260413-022253/enriched.jsonl), including fingerprint match, `0x76 @ 4883`, and post-`0x76` `loop_reentry @ 4884`. Keep Tavern on the current live lane instead of weakening it toward a snapshot-style proof.

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
