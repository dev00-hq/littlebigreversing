# Current Task

This sidequest continues the layer-boundary work in [sidequest/DECISION_PLAN.md](/D:/repos/reverse/littlebigreversing/sidequest/DECISION_PLAN.md).

## Landed Slice

- `port/src/runtime/world_geometry.zig` now owns the neutral runtime point and bounds types.
- `port/src/runtime/session.zig` depends on that module instead of `room_state.zig`.
- `port/src/runtime/world_query.zig` now imports the shared geometry module for its neutral point, bounds, grid-cell, and direction types.

## Next Slice

Look for the next neutral runtime type seam that can leave `world_query.zig` without pulling query semantics out with it.

Keep the boundary honest:

- leave occupancy, probe, and status logic in `world_query.zig`
- leave `RoomSnapshot` and room-shaped adaptation in `room_state.zig`
- keep query-specific evidence structures and unsupported-scene guards in `world_query.zig`

## Why This Matters

The session-to-room-state type coupling is gone. `world_query.zig` still mixes neutral geometry with room-backed topology logic, so the next slice should only extract a type if it stays neutral on its own.

## Guardrails

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Do not widen scene support, add compatibility shims, or introduce a second runtime model.

## Acceptance

- `world_query.zig` keeps its room-dependent topology/query behavior
- any extracted type remains neutral and compile-safe across the viewer/runtime call paths
- guarded runtime/viewer behavior is unchanged
- from native PowerShell, after `.\scripts\dev-shell.ps1`, `cd port` and run `zig build test`
