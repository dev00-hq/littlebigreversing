# Life Scripts

## Purpose

Own the offline life-program decoder boundary, unsupported-opcode audit surface, and the original-runtime evidence lanes.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.
- Keep the outer harness shared and lane policy explicit; do not force one inner proof seam across every scene.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is the canonical offline blocker report.
- `tools/life_trace/trace_life.py` is the operator entrypoint for original-runtime evidence.
- `trace_life.py` writes run bundles under `work/life_trace/runs/<run-id>/` with `manifest.json`, `raw.jsonl`, `enriched.jsonl`, and `screenshots/`.
- `tavern-trace` is the canonical live Frida/FRA behavior-proof lane.
- `scene11-pair` is the canonical debugger-backed Scene11 lane and now reads memory through `cdb-agent`.
- `scene11-live-pair` exists only as a non-canonical challenger.
- The canonical runtime `SAVE` folder is `current.lba` plus `SHOOT/`; controlled runs stage one extra save from `work/saves`, load it through the sole visible `Load Game` slot, then delete it.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` actually handles.
- Guarded negative-load diagnostics report only the first blocking blob; for `11/10`, that is object `12` `LM_DEFAULT @ 38`, not object `18` `LM_END_SWITCH @ 84`.
- Keep the Tavern hot path slim. Re-adding rich loop-time reads can bring back intermittent `Application Error` crashes.
- `scene11-pair` and Tavern do not share one canonical inner proof model. Tavern proves live behavior; Scene11 currently proves ownership/mismatch through a debugger snapshot.
- The current Scene11 result is a stable mismatch, not a startup failure: the loaded `S8741.LBA` room is reproducible, canonical objects `12` and `18` are null, and runtime discovery can surface `LM_DEFAULT` and `LM_END_SWITCH` on live object `2`.
- That Scene11 runtime-owner discovery is state-sensitive. The useful discriminator on the current save is whether the snapshot catches non-null `global_ptr_prg`.
- `scene11-live-pair` is still experimental. Fresh owned runs can still fail immediately after attach with `scene11_live_pair_application_error`, so do not promote it from one-off successes.
- `trace_life.py --launch` now hard-kills any pre-existing `LBA2.EXE` and `cdb.exe` before owned runs and fails fast on the `Application Error` dialog title. Treat that as launcher policy, not as advice for manual sessions.
- `raw.jsonl` is runtime truth and `enriched.jsonl` is host analysis. If attribution or snapshot interpretation looks wrong, inspect `raw.jsonl` first.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/scenes/registry.py`
- `tools/life_trace/scenes/scene11.py`
- `tools/life_trace/scenes/tavern.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `tools/life_trace/life_trace_debugger.py`
- `tools/life_trace/life_trace_runtime.py`
- `tools/life_trace/agent/scene_tavern.js`
- `tools/test_life_trace.py`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`
- `py -3 -m unittest tools.test_life_trace`
- `py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120`
- `py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --timeout-sec 120`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- audit-life-programs --json --scene-entry 11`

## Open Unknowns

- Whether a second independent Scene11 save repeats the live object-`2` ownership result strongly enough to change the runtime proof contract.
- What minimum checked-in evidence would justify widening the supported life boundary beyond explicit rejection.
