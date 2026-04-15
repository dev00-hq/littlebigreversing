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
- `zig build tool -- inspect-life-catalog --json` is the canonical machine-readable structural catalog for `LM_*`, `LF_*`, `LT_*`, and life return-type layout, and it is sourced from the production decoder enums in `life_program.zig`.
- Guarded `19/19` object `2` now has a stateful runtime-backed later reward loop with bounded magic bonus emission.
- `tools/life_trace/trace_life.py` is the shared original-runtime entrypoint, and `capture_sendell_ball.py` owns staged room-`36` runs.
- Run bundles live under `work/life_trace/runs/<run-id>/`; Scene11 and Sendell write `*_summary.json`.
- `tavern-trace` is the canonical Tavern proof lane.
- `scene11-pair` uses one-shot `cdb-agent --pid --wow64` reads.
- Controlled runs use `current.lba` plus `SHOOT/`, stage one extra save, load it, then delete it.
- `work/saves/save_profiles.json` is the canonical save-generation manifest.
- The current Sendell proof is a lightning-to-dialog/story-state lane in room `36`, not a generic pickup-extra surface.
- The canonical Sendell direct fields are `MagicLevel`, `MagicPoint`, and `ListVarGame[FLAG_BOULE_SENDELL]` in `sendell_summary.json`.

## Known Traps

- Do not reuse the old guarded-unsupported-life mental model for `2/2` or `11/10`; those pairs now decode and load through the guarded seam.
- Keep the Tavern hot path slim. Re-adding rich loop-time reads can bring back intermittent `Application Error` crashes.
- Tavern proves live behavior; Scene11 proves ownership through a debugger snapshot.
- The stable Scene11 result is a mismatch, not a startup failure.
- Scene11 runtime-owner discovery is state-sensitive; the useful discriminator is non-null `global_ptr_prg`.
- Do not ask for arbitrary "Scene11" or "Sendell" saves; use `work/saves/save_profiles.json`.
- `trace_life.py --launch` hard-kills pre-existing `LBA2.EXE` and `cdb.exe` before owned runs.
- On Sendell's Ball, behavior and inventory menus are hold surfaces; tap input can leave the screenshot in-room.
- On the Sendell lane, `DAT_00499E96` is a two-byte pre-base; `ListVarGame[0]` starts at `0x00499E98`.

## Canonical Entry Points

- `tools/life_trace/trace_life.py`
- `tools/life_trace/capture_sendell_ball.py`
- `tools/life_trace/scenes/registry.py`
- `tools/life_trace/scenes/scene11.py`
- `tools/life_trace/scenes/tavern.py`
- `port/src/game_data/scene/life_audit.zig`

## Important Files

- `work/saves/save_profiles.json`

## Test / Probe Commands

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-life-catalog --json`
- `py -3 .\tools\life_trace\trace_life.py --mode tavern-trace --launch --timeout-sec 120`
- `py -3 .\tools\life_trace\capture_sendell_ball.py --run-id sendell-full-summary-<date>`

## Open Unknowns

- Whether `CurrentDial` should be the next canonical direct-read field on the Sendell lane now that `MagicLevel`, `MagicPoint`, and `ListVarGame[FLAG_BOULE_SENDELL]` are captured directly.
- When guarded `19/19` object `2` should move beyond bounded bonus-event emission into live `cdb-agent` parity work for extra motion, pickup, UI, and save/load behavior.
