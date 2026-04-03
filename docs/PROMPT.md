# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `life_scripts`, and `platform_windows`.

The previous runtime-foundation and mapping-evidence slices are complete in the current worktree:

- `port/src/runtime/room_state.zig` owns the canonical guarded room/load seam plus immutable room/render snapshots.
- `port/src/runtime/session.zig` still owns mutable frame-to-frame runtime state only.
- `port/src/runtime/world_query.zig` owns pure topology/query logic plus explicit runtime-owned mapping diagnostics over immutable room data only.
- `port/src/root.zig` still exposes the canonical `runtime` module map, including `world_query`.
- `inspect-room`, the viewer runtime, and their tests still share the same guarded room/load seam.
- `19/19` remains the only positive guarded runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded negative `ViewerUnsupportedSceneLife` cases.
- `11/10` remains available only on the explicit test-only unchecked evidence path.
- The mapping-evaluation layer in `world_query.zig` now makes three states explicit:
  - the canonical mapping performs poorly on current admitted evidence
  - a candidate can show only partial signal from a flattering metric
  - a stricter multi-metric winner can still remain diagnostic-only
- `world_query.zig` now also makes evidence admission explicit:
  - `hero_start_world_point` is currently admitted
  - `scene_object_world_point` and `zone_world_point` are currently rejected as `rejected_no_floor_truth`
  - `fragment_world_point` is currently rejected as `rejected_out_of_scope_basis`
- The retained mapping hypothesis set is now intentionally small and justified:
  - `canonical_axis_aligned_512`
  - `swapped_axes_512_control`
  - `dense_swapped_axes_64`

The next slice is not more generic scoring work, not movement policy, not session spawn correction, and not a broader anchor grab. It is a bounded evidence-admission investigation for exactly one possible new anchor class on the supported `19/19` baseline.

Implement a current-state evidence-admission slice that:

- keeps `port/src/runtime/world_query.zig` as the canonical owner of runtime mapping diagnostics and evidence-admission policy
- keeps `port/src/runtime/room_state.zig` limited to guarded room loading plus immutable room/render snapshots
- keeps `port/src/runtime/session.zig` limited to mutable frame-to-frame state only
- does not change the canonical runtime hero spawn policy
- does not add any new public CLI/debug-report surface just to print the investigation result
- determines whether exactly one currently rejected anchor class should stay rejected or become admitted for runtime mapping evaluation

The target is a narrow, evidence-first investigation over `19/19`. The question is not “can we find more coordinates?” It is “can one additional anchor class be justified as floor-truth evidence under the repo’s current standards?”

Useful work in scope includes:

- reviewing the decoded `19/19` scene objects and zone semantics as possible evidence sources
- ranking the two realistic candidate anchor classes before implementation work:
  - `scene_object_world_point`
  - `zone_world_point`
- choosing at most one of those classes for the actual admission test
- documenting, in code and tests, why the chosen class is or is not valid floor-truth evidence
- if the class fails the evidence bar, keeping it rejected explicitly
- if the class clears the evidence bar, admitting exactly that one class in `world_query.zig`
- if a class is admitted, constraining it to the metrics that the checked-in evidence actually supports instead of automatically enabling every metric
- adding tests that prove rejected anchor kinds do not silently score and that any newly admitted class scores only through the approved metrics

Keep the implementation honest about current product boundaries:

- no life execution
- no actor AI
- no hero movement policy
- no session-driven collision resolution API
- no canonical spawn correction in `session.zig`
- no gameplay widening beyond the supported `19/19` load baseline
- no exterior loading
- no metadata-only room path
- no alternate or looser loader path
- no new CLI or viewer inspection mode for this slice

Default to the hard-cut current-state path:

- do not move guarded loading out of `port/src/runtime/room_state.zig`
- do not add caches, mutable convenience fields, or query helpers back into `room_state.zig`
- do not turn `session.zig` into a world-geometry, topology-query, transform-selection, spawn-policy, or calibration owner
- do not silently promote any candidate mapping into canonical `gridCellAtWorldPoint` behavior yet
- do not add `hero_motion.zig` or any movement-policy surface in this slice
- do not reintroduce viewer-owned room/runtime ownership
- do not add compatibility bridges or dual runtime paths
- do not wire `inspect-room` to any looser or alternate path
- do not treat scene objects or zones as floor anchors unless the checked-in evidence is metric-specific and explicit
- do not admit more than one new anchor class in this slice
- do not widen the retained mapping hypothesis set again just because a new anchor class is under review
- do not reopen the Phase 4 branch-B decision for `LM_DEFAULT` or `LM_END_SWITCH`
- if neither `scene_object_world_point` nor `zone_world_point` clears the evidence bar, stop at explicit rejection and do not force an admission just to create motion
- if you discover another recurring trap while doing this work, update `ISSUES.md` and keep the architecture subsystem pack aligned

The intended ownership boundary after this slice remains:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic plus explicit runtime-owned mapping diagnostics, evidence-admission policy, and candidate-evaluation reports over immutable room data only
- `app/viewer/*`: viewer-local layout, draw, HUD, fragment comparison, and viewer interaction state

Relevant files are likely in:

- `port/src/runtime/world_query.zig`
- `port/src/runtime/room_state.zig`
- `port/src/runtime/session.zig`
- `port/src/game_data/scene.zig`
- `port/src/game_data/scene/parser.zig`
- `port/src/game_data/scene/model.zig`
- `port/src/root.zig`
- `scripts/verify-viewer.ps1`
- `ISSUES.md`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Do not turn `world_query.zig` into a second loader or room-decoder surface.
- Keep `inspect-room` and the viewer runtime on the same guarded load boundary they already use.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Keep `11/10` only on explicit test-only unchecked evidence paths.
- Do not claim gameplay support just because one more anchor class is admitted for diagnostic scoring.
- Do not silently rewrite the hero start into a standable position as if that were now source-backed truth.
- Do not turn this into a broad viewer refactor or a generalized evidence framework; the target is one bounded anchor-class decision.
- Because the supported `19/19` baseline has zero fragment zones, do not force fragment-based theories into this slice just to look future-proof.
- Treat “no additional admissible anchor class yet” as a valid successful outcome if the checked-in evidence does not clear the bar.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/runtime/world_query.zig` remains the canonical runtime-owned query and evidence-policy surface and stays exported through `port/src/root.zig`
- `port/src/runtime/room_state.zig` still owns guarded room loading and immutable room/render snapshots
- `port/src/runtime/session.zig` still owns mutable state only and does not absorb mapping-query, transform-selection, or spawn-policy responsibilities
- runtime-owned tests prove the investigation consumes `room_state.RoomSnapshot` or decoded scene data without duplicating guarded loading logic
- runtime tests cover:
  - the currently admitted `hero_start_world_point` case staying admitted
  - the chosen candidate anchor class being ranked, investigated, and either explicitly admitted or explicitly rejected
  - proof that rejected anchor kinds do not silently contribute to mapping scores
  - proof that any newly admitted class contributes only through the metrics justified by checked-in evidence
  - proof that any admitted class remains diagnostic-only and is not wired into canonical session initialization or the default runtime mapping
- no new CLI/debug-report command or viewer surface is added just to expose the admission result
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no metadata-only room inspection path exists in the canonical code
- no unchecked `11/10` path is added to the runtime public surface
