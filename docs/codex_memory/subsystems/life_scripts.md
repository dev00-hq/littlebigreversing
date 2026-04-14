# Life Scripts

## Purpose

Own the offline life-program decoder boundary and the original-runtime evidence lanes.

## Invariants

- Keep life decoding offline until current real assets are structurally supported or deliberately rejected.
- Treat raw `life_bytes` as the canonical scene-model surface.
- Use `GERELIFE.CPP` plus checked-in evidence, not header names alone, for decoder layout claims.
- Keep the outer harness shared and lane policy explicit; do not force one inner proof seam across every scene.

## Current Parity Status

- `life_audit.zig` plus `audit-life-programs` is now the canonical zero-unsupported structural inventory, not a switch-family blocker report.
- `LM_DEFAULT` and `LM_END_SWITCH` are currently supported in the offline decoder as one-byte structural markers.
- `tools/life_trace/trace_life.py` is the entrypoint for original-runtime evidence.
- `trace_life.py` writes run bundles under `work/life_trace/runs/<run-id>/`; `scene11-pair` also writes `scene11_summary.json`.
- `tavern-trace` is the canonical live Frida/FRA behavior-proof lane.
- `scene11-pair` is the canonical debugger-backed Scene11 lane through `cdb-agent`.
- `scene11-pair` is back on one-shot local `cdb-agent --pid --wow64` reads; the adapter now handles Store `cdb.exe` and prompt-prefixed rows correctly.
- The canonical runtime `SAVE` folder is `current.lba` plus `SHOOT/`; controlled runs stage one extra save, load it, then delete it.
- `work/saves/save_profiles.json` is the canonical save-generation manifest, and proof saves stay untrusted until Codex checks the loaded-scene screenshot against the profile cues.

## Known Traps

- `COMMON.H` names more `LM_*` ids than `GERELIFE.CPP` handles.
- Do not reuse the old guarded-unsupported-life mental model for `2/2` or `11/10`; those pairs now decode and load through the guarded seam.
- The current structural proof for the switch-family boundary is narrower than “full semantics.” The raw one-client `cdb` logs prove that `LM_DEFAULT` and `LM_END_SWITCH` fetch as one-byte markers; they do not, by themselves, prove full gameplay behavior for every switch-family path.
- Keep the Tavern hot path slim. Re-adding rich loop-time reads can bring back intermittent `Application Error` crashes.
- Tavern proves live behavior; Scene11 proves ownership/mismatch through a debugger snapshot.
- The stable Scene11 result is a mismatch, not a startup failure: `S8741.LBA` loads, objects `12` and `18` can be null, and live object `2` can expose `LM_DEFAULT` plus `LM_END_SWITCH`.
- Scene11 runtime-owner discovery is state-sensitive; the useful discriminator is non-null `global_ptr_prg`.
- Do not ask for arbitrary "Scene11" saves; use `work/saves/save_profiles.json`.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe` before owned runs and fails fast on `Application Error`.
- The canonical Scene11 debugger lane uses one-shot `cdb-agent --pid` reads only.
- Raw one-client `cdb` is still the Branch A stepping tool only; keep canonical Scene11 snapshots on `cdb-agent --pid`, and keep detached `cdb-agent` sessions single-client/manual.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/scenes/registry.py`
- `tools/life_trace/scenes/scene11.py`
- `tools/life_trace/scenes/tavern.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 .\tools\codex_memory.py validate`
- `py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120`
- `py -3 .\tools\life_trace\trace_life.py --mode scene11-pair --launch --launch-save .\work\saves\neighbor-house.LBA --timeout-sec 120`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- audit-life-programs --json --scene-entry 11`

## Open Unknowns

- Which post-Branch-A runtime/gameplay slice should become the next canonical widening target now that the decoder no longer rejects `LM_DEFAULT` / `LM_END_SWITCH`.
