# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

The previous runtime-foundation slices are complete in the current worktree:

- `port/src/runtime/room_state.zig` owns the canonical guarded room/load seam plus immutable room/render snapshots.
- `port/src/runtime/session.zig` owns mutable frame-to-frame runtime state for the supported `19/19` path.
- `port/src/root.zig` exposes the canonical `runtime` module map.
- `port/src/app/viewer_shell.zig` and `port/src/main.zig` now consume runtime-owned room/session surfaces instead of viewer-owned room/runtime ownership.
- `inspect-room`, the viewer runtime, and their tests still share the same guarded room/load seam.
- `19/19` remains the only positive guarded runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded negative `ViewerUnsupportedSceneLife` cases.
- `11/10` remains available only on the explicit test-only unchecked evidence path.

The next slice is not movement policy and not more viewer plumbing. It is the first bounded static world-query layer on top of the supported `19/19` room snapshot.

Implement a current-state runtime world-query slice that:

- creates a canonical `port/src/runtime/world_query.zig` module
- keeps `port/src/runtime/room_state.zig` limited to guarded room loading plus immutable room/render snapshots
- keeps `port/src/runtime/session.zig` limited to mutable frame-to-frame state only
- makes `world_query.zig` consume `room_state.RoomSnapshot` and immutable render/composition data only
- introduces the smallest useful pure-query surface for later hero motion work:
  - world/grid bounds queries for the supported room snapshot
  - composition occupancy / top-surface lookup queries for base room cells
  - explicit hero-start validation or resolution against the loaded room snapshot
  - explicit standability-style queries that answer from immutable room topology only
- keeps the implementation honest about current product boundaries:
  - no life execution
  - no actor AI
  - no hero movement policy
  - no session-driven collision resolution API yet
  - no gameplay widening beyond the supported `19/19` load baseline
  - no exterior loading
  - no metadata-only room path
- updates `port/src/root.zig` so the canonical runtime module map includes the new world-query surface
- adds runtime-owned tests that prove the query layer consumes `room_state.RoomSnapshot` instead of duplicating guarded loading logic

Default to the hard-cut current-state path:

- do not move guarded loading out of `port/src/runtime/room_state.zig`
- do not add caches, mutable convenience fields, or query helpers back into `room_state.zig`
- do not turn `session.zig` into a world-geometry or topology-query owner
- do not add `hero_motion.zig` or any movement-policy surface in this slice
- do not reintroduce viewer-owned room/runtime ownership
- do not add compatibility bridges or dual runtime paths
- do not wire `inspect-room` to any looser or alternate path
- do not treat this as a gameplay feature slice; it is a bounded runtime-query foundation slice
- do not reopen the Phase 4 branch-B decision for `LM_DEFAULT` or `LM_END_SWITCH`
- if you discover another recurring trap while doing this work, update `ISSUES.md` and keep the architecture subsystem pack aligned

The intended ownership boundary after this slice is:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic over immutable room data only
- `app/viewer/*`: viewer-local layout, draw, HUD, fragment comparison, and viewer interaction state

Relevant files are likely in:

- `port/src/runtime/room_state.zig`
- `port/src/runtime/session.zig`
- `port/src/runtime/world_query.zig`
- `port/src/root.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/main.zig`
- `port/src/app/viewer/state_test.zig`
- `port/src/runtime/`
- `scripts/verify-viewer.ps1`
- `ISSUES.md`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Do not turn `world_query.zig` into a second loader or room-decoder surface.
- Keep `inspect-room` and the viewer runtime on the same guarded load boundary they already use.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Keep `11/10` only on explicit test-only unchecked evidence paths.
- Do not claim gameplay support just because static world queries now exist.
- Do not turn this into a broad viewer refactor; the target is bounded runtime-owned query logic.
- Because the supported `19/19` baseline has zero fragment zones, do not force fragment-toggle semantics into the first query surface just to look future-proof.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/runtime/world_query.zig` exists and is exported through `port/src/root.zig`
- `port/src/runtime/room_state.zig` still owns guarded room loading and immutable room/render snapshots
- `port/src/runtime/session.zig` still owns mutable state only and does not absorb world-query responsibilities
- the new runtime world-query layer owns pure topology/query logic without loosening the guarded room/load seam
- runtime tests prove world-query initialization and queries consume `room_state.RoomSnapshot` instead of duplicating loading logic
- runtime tests cover at least one occupied/base-supported query on `19/19`, at least one explicit empty/out-of-bounds rejection, and explicit hero-start validation on the supported room snapshot
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no metadata-only room inspection path exists in the canonical code
- no unchecked `11/10` path is added to the runtime public surface
