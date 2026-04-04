# Current Task

This sidequest continues the layer-boundary work in [sidequest/DECISION_PLAN.md](/D:/repos/reverse/littlebigreversing/sidequest/DECISION_PLAN.md).

## Landed Slice

- `port/src/runtime/world_geometry.zig` owns `WorldPointSnapshot`, `WorldBounds`, `GridCell`, and `CardinalDirection`.
- `port/src/runtime/session.zig` and `port/src/runtime/world_query.zig` import that module instead of defining those shared types locally.

## Next Slice

Do not extract more from `world_query.zig` unless a type is both neutral and shared with a non-query consumer. If no such type exists, stop here.

Keep these boundaries intact:

- leave occupancy, probe, and status logic in `world_query.zig`
- leave `RoomSnapshot` and room-shaped adaptation in `room_state.zig`
- keep query-specific evidence structures and unsupported-scene guards in `world_query.zig`

## Guardrails

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Do not widen scene support, add compatibility shims, or introduce a second runtime model.

## Acceptance

- no further `world_query.zig` type extraction happens unless a real shared neutral type appears
- `world_query.zig` keeps its room-dependent topology/query behavior
- guarded runtime/viewer behavior stays unchanged
- from native PowerShell, after `.\scripts\dev-shell.ps1`, `cd port` and run `zig build test`
