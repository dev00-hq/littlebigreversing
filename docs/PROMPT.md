# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- Phase 4 branch A is now the current path. `LM_DEFAULT` and `LM_END_SWITCH` are structurally supported in the offline decoder as one-byte markers.
- `zig build tool -- audit-life-programs --json --all-scene-entries` now audits all `3109` life blobs with `unsupported_blob_count = 0`.
- The guarded room/load set is widened: `19/19`, `2/2`, and `11/10` are positive `inspect-room` and viewer-launch cases.
- `44/2` is no longer a life blocker. It remains a guarded negative because it is exterior and fails with `ViewerSceneMustBeInterior`.
- The widened guarded startup set is still diagnostics-first, but it is no longer opaque:
  - `19/19` currently reports `best_alt_mapping=dense_swapped_axes_64`
  - `2/2` currently reports `best_alt_mapping=swapped_axes_512_control`
  - `11/10` currently reports `best_alt_mapping=none`
- `rank-decoded-interior-candidates --json` now reports `147` fully decoded interior candidates, `101` as the top-ranked interior, `11` as rank `15`, and baseline `19` as `146/147`.
- Same-index fragment-zone triage is still explicit: `86/86` is the highest-ranked compatible pair above baseline, and `187/187` is the first fragment-bearing compatible pair.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.

Next slice:

- Keep the widened Branch-A decoder and guarded room/load set stable.
- Choose one narrow post-Branch-A runtime-facing follow-up from the differentiated start diagnostics instead of reopening switch-family proof:
  1. either test whether one of the current `best_alt_mapping` hints deserves promotion into a controlled runtime hypothesis,
  2. or pick the next guarded-positive room/load pair only after justifying it against the current `19/19`, `2/2`, and `11/10` diagnostics.
- Preserve `44/2` as the explicit exterior rejection and `219/219` as the invalid-fragment-bounds blocker.
- Do not reintroduce unsupported-life fail-fast paths for `2/2` or `11/10`.
- Do not widen into full gameplay or scene transitions in the same slice.

Hard-cut ownership:

- `life_program.zig`: canonical owner of structural life decoding
- `life_audit.zig`: canonical owner of offline all-scene life inventory and ranking
- `runtime/room_state.zig`: canonical owner of guarded room/load admission and failure reasons
- `tools/cli.zig`: canonical owner of `inspect-room` and ranking/triage surfaces
- `scripts/verify_viewer.py`: canonical Windows acceptance gate
- `viewer_shell.zig`, `render.zig`, `main.zig`, and locomotion/runtime gameplay code: unchanged unless a tiny plumbing change is required by the chosen slice

Acceptance:

- The widened Branch-A boundary stays explicit in code, tests, and docs.
- `19/19`, `2/2`, and `11/10` remain guarded-positive `inspect-room` / viewer-launch cases.
- `44/2` remains a guarded `ViewerSceneMustBeInterior` failure.
- The next runtime-facing step is framed in terms of post-Branch-A admission/diagnostics, not unsupported switch-family life.

Validation:

- From native PowerShell, prefer:
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build stage-viewer`
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- audit-life-programs --json --scene-entry 2 --scene-entry 5 --scene-entry 11 --scene-entry 44`
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- audit-life-programs --json --all-scene-entries`
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 2 2 --json`
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 11 10 --json`
  - `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build tool -- inspect-room 44 2 --json`
  - `py -3 .\scripts\verify_viewer.py --fast`
  - `py -3 .\scripts\verify_viewer.py`
