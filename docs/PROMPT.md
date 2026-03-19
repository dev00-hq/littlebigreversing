# Next Action: Typed `SCENE.HQR` Zone Semantics

## Summary

- The repo is in a good place for a narrow Phase 2 step: `zig build test` passes, the Phase 1 workspace is stable, and the current typed scene loader already covers scene/object/zone/track/patch structure.
- The best next slice is to turn zone records from mostly raw fields into source-backed typed semantics, because the classic loader already normalizes zone behavior at load time and the verified scenes (`2`, `4`, `5`) exercise useful zone types without forcing script decoding.
- Do **not** expand into track or life bytecode in this slice. Do **not** treat the exterior-target indexing mismatch as resolved here.
- `SCENE.HQR[4]` may still be inspected as a regression scene, but it is **not** the canonical basis for exterior-specific semantics until the scene-number versus HQR-entry mapping is reconciled.

## Implementation Changes

- In `port/src/game_data/scene.zig`, make `SceneZone` the canonical typed zone model:
  - Keep bounds (`x0..z1`) and `num`.
  - Replace `info0..info7` fields with `raw_info: [8]i32`.
  - Add `zone_type: ZoneType`.
  - Add `semantics: ZoneSemantics`, where semantics are the canonical interpreted meaning of the zone.
  - Keep the boundary explicit:
    - `raw_info` is the unmodified scene payload.
    - `semantics` is derived from classic source-backed interpretation paths.
    - keep `raw_info` available even when a zone gets typed semantics; some source-backed control fields still belong in raw storage until their meaning is strong enough to promote cleanly.
    - only immediate load-time initialization from `LoadScene` belongs in the semantic view as initial state.
    - later runtime mutation remains out of `SceneZone`.
- Introduce an explicit helper boundary inside the parser, such as `decodeZone(raw_zone, cube_mode)`, so raw-byte parsing and semantic mapping are testable separately.
- Define `ZoneType` as the classic source-backed set:
  - `change_cube = 0`
  - `camera = 1`
  - `scenario = 2`
  - `grm = 3`
  - `giver = 4`
  - `message = 5`
  - `ladder = 6`
  - `escalator = 7`
  - `hit = 8`
  - `rail = 9`
  - Any other value fails decoding with an explicit `UnsupportedSceneZoneType`.
- Define `ZoneSemantics` as a tagged union with these normalized payloads:
  - `change_cube`: destination cube, destination placement x/y/z inputs, yaw, `test_brick`, `dont_readjust_twinsen`, `initially_on`
    - preserve `raw_info[4]` as the source-backed change-cube control selector used by `LM_SET_CHANGE_CUBE` unless stronger evidence in the same change justifies a stable field name
  - `camera`: anchor/start-cube x/y/z, exterior-only camera params (`alpha`, `beta`, `gamma`, `distance`), `initially_on`, `obligatory`
  - `scenario`: no extra typed fields beyond `num`
  - `grm`: `grm_index`, `initially_on`
    - do **not** invent a redraw-state field; keep any remaining load-time scratch meaning in `raw_info`
  - `giver`: bonus kind, quantity, `already_taken = false`
  - `message`: dialog id (`num`), optional linked camera zone id, facing direction enum
  - `ladder`: `enabled_on_load`
  - `escalator`: `enabled`, direction enum
  - `hit`: damage, cooldown raw value, `initial_timer = 0`
  - `rail`: `switch_state_on_load`
- Interpret semantics from classic source in two explicit layers:
  - load-time initialization from `LoadScene` in `DISKFUNC.CPP`
  - runtime meaning from the relevant zone handlers in `OBJECT.CPP`, `EXTRA.CPP`, `GERELIFE.CPP`, `GRILLE.CPP`, and wagon logic where applicable
- Do not guess fields that are not source-backed.
- If unsupported message or escalator direction encodings are rejected, document that as the repo's fail-fast policy boundary rather than as a claim about original classic behavior.
- Update `port/src/tools/cli.zig`:
  - JSON output for `inspect-scene` should emit `zone_type`, `raw_info`, and `semantics` for every zone.
  - Freeze the `semantics` JSON shape as an object with a required `kind` string plus variant-specific fields. Do **not** flatten the union into the parent zone object and do **not** rely on Zig's implicit union serialization.
  - Text output should print zone type names plus a compact semantic summary instead of only `type_id` and bounds.
  - Text mode must at least include `zone_type`, `num`, bounds, and one variant-specific summary field group.
- Keep tracks and life scripts opaque:
  - No bytecode parsing.
  - No new script-specific CLI yet.
- After implementation, refresh repo memory:
  - update `docs/codex_memory/handoff.md`
  - append `task_log.jsonl`
  - append `decision_log.jsonl` if the zone model boundary is finalized
  - run `python3 tools/codex_memory.py validate`

## Public Interfaces / Types

- `SceneZone` changes shape and becomes a typed zone record instead of a raw `info0..info7` bag.
- `SceneZone`, `ZoneType`, `ZoneSemantics`, and small supporting enums should be exported through `port/src/root.zig` if scene data is already re-exported there.
- `inspect-scene --json` output changes:
  - remove `type_id`
  - add `zone_type`
  - add `raw_info`
  - add `semantics`
  - `semantics` must always be an object of the form `{ "kind": "<zone-type>", ...variant fields... }`

## Test Plan

- Keep `zig build test` as the main gate.
- Add synthetic parser tests for each zone type’s semantic mapping, especially:
  - `change_cube` bit normalization from raw `info5/info6/info7`
  - preservation of the source-backed change-cube control selector in `raw_info[4]`
  - `camera` flag normalization
  - `grm`, `giver`, `ladder`, `hit`, and `rail` load-time initialization
  - explicit failure on unsupported zone type
  - explicit failure on unsupported message/escalator direction values if the decoder chooses the repo's fail-fast policy for those encodings
- Add asset-backed assertions for current verified scenes:
  - scene `2`: `change_cube`, `scenario`, `giver`, and `message` semantics decode as expected
  - scene `4`: `camera`, `change_cube`, `scenario`, `giver`, and `message` semantics stay internally consistent, but do **not** assert exterior-only semantics or optional camera params from this target yet
  - scene `5`: repeated `giver` zones plus `change_cube`/`scenario` stay aligned as a non-golden regression target, not as a locked phase 0 golden target
  - implement scene `5` regression coverage through a direct `SCENE.HQR` path or a scene-specific helper, not by expanding the locked phase 0 `fixture_targets` set
- Re-run:
  - `zig build test`
  - `zig build tool -- inspect-scene 2 --json`
  - `zig build tool -- inspect-scene 4 --json`
  - `zig build tool -- inspect-scene 5 --json`

## Assumptions And Defaults

- The next slice stays inside scene-zone semantics only; script blobs remain opaque by design.
- The `SCENE.HQR[4]` exterior/cube-indexing mismatch is still an evidence issue and should be called out in docs, not “fixed” by guessing in code.
- `SCENE.HQR[5]` is useful for regression coverage in this slice, but it is not part of the locked phase 0 golden target set unless that decision is made explicitly elsewhere.
- Fail fast on unsupported zone types or malformed semantic encodings instead of adding unknown-mode fallbacks.
- Preserve the current `ISSUES.md` change; append only if this work uncovers a new reusable trap.
