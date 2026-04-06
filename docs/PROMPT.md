# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current repo state:

- `port/src/runtime/world_query.zig` already owns the guarded `19/19` pure move/query surface:
  - baked `19/19` hero-start probing and diagnostics
  - cardinal move-option evaluation for admitted hero positions
  - exact containing-zone queries over copied checked-in scene-zone bounds
- `port/src/runtime/locomotion.zig` already owns the guarded runtime locomotion seam:
  - current-position status for the explicit admitted fixture path
  - non-mutating invalid-origin rejection from the baked raw start
  - one-cell accepted/rejected step results
  - session mutation only on allowed movement
- `port/src/runtime/session.zig` still owns mutable hero world position only.
- `port/src/runtime/room_state.zig` still owns the guarded room/load seam plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` and `port/src/main.zig` now consume runtime-owned locomotion results instead of owning step policy.

Important current-state facts:

- `19/19` is still the only positive guarded runtime/load pair.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- the baked `19/19` hero start remains diagnostically invalid:
  - `probeHeroStart()` reports `mapped_cell_empty`
  - raw mapped cell `3/7`
  - outside occupied bounds
- the explicit `39/6` movement fixture is still opt-in only
- the exact containing-zone result for:
  - seeded `39/6`
  - accepted seeded south step to `39/7`
  - rejected seeded west step preserving `39/6`
  is currently the empty set on the checked-in guarded runtime path

The next slice is not more movement policy. The next slice is to make the runtime-owned containing-zone result visible and explicit in the existing diagnostics path, including the fact that the exact answer is currently “none”.

Implement a current-state slice that:

- keeps `runtime/world_query.zig` as the only owner of exact containing-zone queries
- keeps `runtime/locomotion.zig` as the only owner of step/result policy
- updates `viewer_shell.zig` formatting and diagnostics so runtime-owned containing-zone membership is surfaced for:
  - seeded/admitted status
  - accepted movement
  - rejected movement that preserves the current admitted position
- makes the empty containing-zone set explicit in viewer/HUD copy and stderr diagnostics instead of silently omitting it
- keeps `main.zig` as input routing only
- keeps any new formatting logic viewer-local; do not push presentation policy back into runtime

Keep ownership hard-cut and explicit:

- `world_query.zig`: pure guarded room query/evaluation owner
- `locomotion.zig`: runtime step/result owner
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, and explicit fixture seeding only
- `render.zig`: display only
- `main.zig`: input routing only

Keep the implementation honest about scope:

- no new movement rules
- no new current-zone heuristics
- no fallback “best zone” selection
- no coordinate remapping to force a non-empty zone answer
- no life execution
- no scene transitions
- no object AI
- no inventory/state systems
- no combat
- no track execution
- no new input-repeat system
- no auto-seeding
- no unchecked room path added to the public runtime seam

Useful work in scope includes:

- adding a compact viewer-local formatter for containing-zone membership that can print either:
  - `ZONES NONE`
  - or a stable exact list derived directly from the runtime-owned containing-zone result
- extending stderr locomotion diagnostics so they expose the same exact zone-membership summary the HUD surfaces
- pinning the exact seeded/accepted/rejected copy in viewer tests and render tests
- keeping the explicit empty-set result visible in tests so future slices do not “improve” it by inventing semantics

Acceptance:

- viewer-shell tests prove the viewer consumes runtime-owned containing-zone results without reintroducing viewer-owned movement policy
- render tests prove the zero-fragment guarded path surfaces:
  - raw invalid start status
  - seeded admitted status with explicit empty containing-zone copy
  - accepted south step with explicit empty containing-zone copy
  - rejected west step with explicit empty containing-zone copy
- stderr locomotion diagnostics expose the exact containing-zone summary for seeded, accepted, and rejected runtime statuses
- `world_query.zig` remains the canonical pure move/query surface
- `locomotion.zig` remains the canonical runtime step/result seam
- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
