# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `port/src/runtime/world_query.zig` owns exact containing-zone queries and exact move-target evaluation, including raw mapped target cells and `MoveTargetStatus`.
- `port/src/runtime/locomotion.zig` owns step/result policy and already carries runtime-owned zone membership on `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`.
- `port/src/runtime/session.zig` owns mutable hero world position only.
- `port/src/runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already formats the runtime-owned zone set as either `ZONES NONE` or a stable scene-order list, and it currently formats admitted-path move options from direction plus `MoveTargetStatus` only.
- `port/src/app/viewer/render.zig` owns display only.
- `port/src/main.zig` owns input routing only.
- `port/src/app/viewer_shell_test.zig`, `port/src/app/viewer/render_test.zig`, and `port/src/runtime/locomotion_test.zig` already pin the current zero-fragment contract, including explicit `ZONES NONE` / `zones=none` behavior and the separation between raw invalid-start copy and admitted-position movement semantics.

Important facts:

- `19/19` remains the only supported positive runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- The baked `19/19` hero start is still diagnostically invalid: `probeHeroStart()` reports `mapped_cell_empty`, raw mapped cell `3/7`, and outside occupied bounds.
- The explicit `39/6` movement fixture is opt-in only.
- On the guarded zero-fragment path, containing-zone membership for seeded `39/6`, accepted south to `39/7`, and rejected west preserving `39/6` is currently the empty set.
- The landed zone-summary contract is the baseline, not the next task.
- The live runtime already computes the next useful evidence cue: exact raw target-cell mapping for each admitted-path cardinal option. The current locomotion seam drops that detail when it collapses move options down to direction plus status.

The next slice is not new movement policy, not a new zone heuristic, and not a second presentation path. The next slice is to thread runtime-owned admitted-path target-cell evidence through the guarded `19/19` locomotion seam and make that evidence visible in existing viewer HUD and stderr diagnostics without reintroducing viewer-owned move evaluation.

Implement a current-state slice that:

- keeps `runtime/world_query.zig` as the only owner of move-target evaluation, including exact raw target-cell mapping
- keeps `runtime/locomotion.zig` as the only owner of step/result policy and admitted-path move-option packaging
- expands the admitted-path move-option payload so seeded, accepted, and admitted-position rejected statuses carry exact runtime-owned target-cell mapping alongside the existing `MoveTargetStatus`
- keeps `viewer_shell.zig` as formatting only: it may display the richer runtime-owned move-option evidence in HUD copy and stderr diagnostics, but it must not recompute move targets
- keeps the current `ZONES NONE` / `zones=none` contract unchanged for the already-landed zero-fragment path
- keeps raw invalid-start copy separate; do not invent admitted-path option details for the baked invalid origin path
- keeps `origin_invalid` rejection copy separate; do not pretend the baked invalid path has admitted move-option semantics
- keeps HUD and stderr derived from the same runtime-owned move-option and zone data, while letting stderr stay structured
- keeps `main.zig` as input routing only

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

- extending the admitted-path move-option structs so they preserve exact target-cell mapping from `world_query.zig`
- adding compact viewer-local formatters for move-option evidence that can show direction, target cell, and status without recomputing anything in the viewer
- updating HUD copy and `printLocomotionStatusDiagnostic` together so they expose the same runtime-owned admitted-path option details and still preserve the existing zone-summary contract
- growing `ViewerLocomotionStatusDisplayBuffer` and the display line counts if the richer admitted-path copy needs it
- keeping raw invalid start diagnostics separate; only seeded, accepted, and admitted-position rejected runtime statuses should carry the richer admitted-path option evidence
- pinning runtime, viewer-shell, and render tests so future slices cannot silently drop target-cell detail back to status-only copy

Acceptance:

- runtime locomotion tests prove seeded, accepted, and admitted-position rejected statuses now preserve exact runtime-owned target-cell mapping for each cardinal option on the guarded `19/19` fixture path
- viewer-shell tests pin the exact seeded/accepted/rejected HUD copy and stderr diagnostics for the richer admitted-path move-option evidence, while keeping explicit `ZONES NONE` in the HUD path and explicit `zones=...` in stderr
- viewer-shell tests continue to prove the viewer consumes runtime-owned locomotion results without reintroducing viewer-owned movement policy
- render tests prove the zero-fragment guarded path surfaces:
  - raw invalid start status without admitted-path option detail
  - seeded admitted status with exact runtime-owned move-option target cells and explicit `ZONES NONE`
  - accepted south step with exact runtime-owned move-option target cells and explicit `ZONES NONE`
  - rejected west step that preserves `39/6`, still showing the admitted-position move-option target cells and explicit `ZONES NONE`
- raw invalid start tests continue to prove the baked invalid-origin copy without any zone-summary line or admitted-path option detail
- stderr locomotion diagnostics continue to expose the same exact containing-zone summary for seeded, accepted, and admitted-position rejected runtime statuses
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
