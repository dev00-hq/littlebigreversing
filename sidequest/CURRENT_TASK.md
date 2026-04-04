# Current Task

This sidequest continues the layer-boundary work in [sidequest/DECISION_PLAN.md](/D:/repos/reverse/littlebigreversing/sidequest/DECISION_PLAN.md).

## Landed Slice

- `port/src/runtime/world_geometry.zig` now owns the neutral runtime point/bounds types.
- `port/src/runtime/session.zig` depends on that module instead of `room_state.zig`.
- `port/src/runtime/room_state.zig`, `port/src/runtime/world_query.zig`, `port/src/app/viewer_shell.zig`, and `port/src/app/viewer/state.zig` now consume the shared geometry module.

## Next Concrete Slice

Extract the remaining neutral grid primitives, starting with `GridCell` and `CardinalDirection`, into `port/src/runtime/world_geometry.zig`, then rewire `port/src/runtime/world_query.zig` and the viewer/runtime call paths to use them.

Keep the boundary honest:

- leave occupancy, probe, and status logic in `world_query.zig`
- leave `RoomSnapshot` and all room-shaped adaptation in `room_state.zig`
- do not move query-specific evidence structures or unsupported-scene guards out of `world_query.zig`

## Why This Is Next

The session-to-room-state coupling is gone, but `world_query.zig` still owns a small cluster of neutral geometry primitives that are shared with the viewer path. Extracting those next tightens the runtime seam without pretending the whole query layer is generic.

## Guardrails

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Do not widen scene support, add compatibility shims, or introduce a second runtime model.

## Acceptance

- `GridCell` and `CardinalDirection` live outside `world_query.zig` if they can be extracted cleanly as neutral runtime data
- `world_query.zig` still compiles and owns the room-dependent topology/query behavior
- viewer/runtime call paths still compile cleanly against the extracted types
- guarded runtime/viewer behavior is unchanged
- from native PowerShell, after `.\scripts\dev-shell.ps1`, `cd port` and run `zig build test`
