# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `port/src/runtime/world_query.zig` owns exact containing-zone queries over copied checked-in scene-zone bounds.
- `port/src/runtime/locomotion.zig` owns step/result policy and already carries runtime-owned zone membership on `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`.
- `port/src/runtime/session.zig` owns mutable hero world position only.
- `port/src/runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only.
- `port/src/app/viewer/render.zig` owns display only.
- `port/src/main.zig` owns input routing only.
- `port/src/app/viewer_shell_test.zig` and `port/src/app/viewer/render_test.zig` already pin the runtime-owned zero-fragment locomotion copy, but they do not yet require explicit zone-summary text.

Important facts:

- `19/19` remains the only supported positive runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- The baked `19/19` hero start is still diagnostically invalid: `probeHeroStart()` reports `mapped_cell_empty`, raw mapped cell `3/7`, and outside occupied bounds.
- The explicit `39/6` movement fixture is opt-in only.
- On the guarded zero-fragment path, containing-zone membership for seeded `39/6`, accepted south to `39/7`, and rejected west preserving `39/6` is currently the empty set.
- `port/src/runtime/locomotion_test.zig` already pins that empty-set runtime result. The gap is viewer copy and diagnostics, not missing runtime semantics.

The next slice is not new movement policy. The next slice is to make the runtime-owned containing-zone result visible and explicit in the existing viewer/HUD and stderr diagnostics, including the fact that the exact answer is currently `ZONES NONE`.

Implement a current-state slice that:

- keeps `runtime/world_query.zig` as the only owner of exact containing-zone queries
- keeps `runtime/locomotion.zig` as the only owner of step/result policy
- keeps `viewer_shell.zig` as the only place that formats the runtime-owned zone membership for HUD copy and stderr diagnostics
- surfaces runtime-owned containing-zone membership for:
  - seeded/admitted status
  - accepted movement
  - rejected movement that preserves the current admitted position
- makes the empty containing-zone set explicit as `ZONES NONE` instead of silently omitting it
- keeps raw invalid-start copy separate; do not invent zone output for the baked invalid origin path
- keeps `origin_invalid` rejection copy separate; do not pretend the baked invalid path has admitted-zone semantics
- keeps HUD and stderr summaries derived from the same runtime-owned zone set and ordering, while letting stderr stay structured via an explicit `zones=...` field
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
- no fallback "best zone" selection
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
  - or a stable exact list of scene-order zone indices derived directly from the runtime-owned containing-zone result
- threading the same exact zone-membership semantics through HUD text and `printLocomotionStatusDiagnostic` without forcing the same presentation string
- growing `ViewerLocomotionStatusDisplayBuffer` and the display line counts if needed
- touching `main.zig` only if compile fallout forces it; this slice should not move formatting or policy there
- keeping raw invalid start diagnostics separate; only seeded, accepted, and admitted-position rejected runtime statuses should carry the zone summary
- pinning the exact seeded/accepted/rejected copy in viewer-shell tests and render tests
- pinning stderr diagnostics in viewer-shell tests so the runtime-owned zone summary stays aligned with the HUD semantics and ordering
- keeping the explicit empty-set result visible in tests so future slices do not "improve" it by inventing semantics

Acceptance:

- viewer-shell tests prove the viewer consumes runtime-owned containing-zone results without reintroducing viewer-owned movement policy
- viewer-shell tests pin the exact seeded/accepted/rejected HUD copy and stderr diagnostics, including explicit `ZONES NONE` in the HUD path and explicit `zones=...` in stderr
- render tests prove the zero-fragment guarded path surfaces:
  - raw invalid start status
  - seeded admitted status with explicit `ZONES NONE`
  - accepted south step with explicit `ZONES NONE`
  - rejected west step with explicit `ZONES NONE`
- raw invalid start tests continue to prove the baked invalid-origin copy without any zone-summary line
- stderr locomotion diagnostics expose the same exact containing-zone summary for seeded, accepted, and admitted-position rejected runtime statuses
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
