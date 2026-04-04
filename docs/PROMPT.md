# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

The previous runtime-foundation, anchor-admission, and topology-observation slices are complete in the current worktree:

- `port/src/runtime/room_state.zig` owns the canonical guarded room/load seam plus immutable room/render snapshots.
- `port/src/runtime/session.zig` still owns mutable frame-to-frame runtime state only.
- `port/src/runtime/world_query.zig` owns pure topology/query logic plus explicit runtime-owned mapping diagnostics over immutable room data only.
- `port/src/root.zig` still exposes the canonical `runtime` module map, including `world_query`.
- `inspect-room`, the viewer runtime, and their tests still share the same guarded room/load seam.
- `19/19` remains the only positive guarded runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded negative `ViewerUnsupportedSceneLife` cases.
- `11/10` remains available only on the explicit test-only unchecked evidence path.
- `world_query.zig` now makes evidence admission explicit:
  - `hero_start_world_point` is admitted
  - `zone_world_point` and `scene_object_world_point` remain rejected as `rejected_no_floor_truth`
  - `fragment_world_point` remains rejected as `rejected_out_of_scope_basis`
- `world_query.zig` now also exposes diagnostic-only local neighbor probes plus an observed-neighbor summary over immutable room snapshots.
- The guarded `19/19` neighbor-pattern regression is now explicit:
  - `1246` occupied origin cells
  - `4984` cardinal neighbor probes
  - `4828` occupied neighbors, all standable
  - `107` empty neighbors
  - `49` out-of-bounds neighbors
  - `0` blocked neighbors
  - `0` missing-top-surface neighbors
  - the only observed `top_y` delta bucket is `0`

The next slice is not more `19/19` topology API, not a relation taxonomy, not movement policy, and not a broader gameplay widening. The next slice is a bounded evidence-source decision plus falsification pass:

- decide whether explicit test-only unchecked rooms are allowed to justify any future topology relation classes at all
- if they are allowed, run one tiny offline selection pass to find a room with actual non-flat or blocked occupied-neighbor patterns
- if they are not allowed, or if no qualifying room is found in the checked-in evidence set, stop topology expansion explicitly and pivot the outcome toward another uncertainty reducer

Implement a current-state decision-and-falsification slice that:

- keeps `port/src/runtime/world_query.zig` as the canonical owner of runtime topology/query logic over immutable room data only
- keeps `port/src/runtime/room_state.zig` limited to guarded room loading plus immutable room/render snapshots
- keeps `port/src/runtime/session.zig` limited to mutable frame-to-frame state only
- does not change canonical runtime hero spawn policy
- does not add any new public CLI/debug-report surface just to print the result
- does not assume `11/10` is the right topology-evidence room merely because it is already a useful evidence pair

The target is a narrow decision:

- are unchecked evidence-only rooms an acceptable basis for discovering future topology relation classes?

If the answer is no, that is a valid successful outcome. Make the rejection explicit in code/tests/docs and stop there.

If the answer is yes, the question becomes:

- can we identify exactly one checked-in evidence-only room whose observed occupied-neighbor patterns contain non-flat or blocked cases that `19/19` does not?

Useful work in scope includes:

- documenting, in code and tests, why unchecked evidence-only rooms are or are not an acceptable basis for future topology-semantics discovery
- if they are acceptable, adding a tiny test-local or offline-only scan over the checked-in evidence set to rank candidate rooms by observed neighbor-pattern variety
- choosing at most one evidence-only room for follow-up topology observation
- proving whether the chosen room actually introduces non-flat or blocked occupied-neighbor cases beyond the pinned `19/19` baseline
- if no qualifying room exists, stopping at explicit rejection and recording that the current checked-in evidence does not justify richer relation classes yet
- if a qualifying room does exist, keeping the result diagnostic-only and evidence-only rather than turning it into runtime gameplay policy

Keep the implementation honest about current product boundaries:

- no life execution
- no actor AI
- no hero movement policy
- no session-driven collision resolution API
- no canonical spawn correction in `session.zig`
- no gameplay widening beyond the supported `19/19` load baseline
- no exterior loading
- no metadata-only room path
- no alternate or looser loader path in the public runtime surface
- no new CLI or viewer inspection mode for this slice
- no new relation enum or movement-facing taxonomy unless the checked-in evidence decision and room scan clearly justify it

Default to the hard-cut current-state path:

- do not move guarded loading out of `port/src/runtime/room_state.zig`
- do not add caches, mutable convenience fields, or query helpers back into `room_state.zig`
- do not turn `session.zig` into a world-geometry, topology-query, transform-selection, spawn-policy, or calibration owner
- do not silently promote any diagnostic result into canonical `gridCellAtWorldPoint` behavior
- do not add `hero_motion.zig` or any movement-policy surface in this slice
- do not reintroduce viewer-owned room/runtime ownership
- do not add compatibility bridges or dual runtime paths
- do not wire `inspect-room` to any looser or alternate path
- do not treat `11/10` as topology evidence by default; justify it or any other unchecked room explicitly
- do not let unchecked evidence-only rooms shape runtime-facing semantics unless this slice first makes that evidence-source rule explicit
- do not broaden the supported runtime/load baseline just because an unchecked room is useful for evidence
- do not reopen the Phase 4 branch-B decision for `LM_DEFAULT` or `LM_END_SWITCH`
- if the evidence-source answer is no, or the scan finds no qualifying room, stop at explicit rejection and do not force more topology work just to create motion
- if you discover another recurring trap while doing this work, update `ISSUES.md` and keep the architecture subsystem pack aligned

The intended ownership boundary after this slice remains:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic plus explicit runtime-owned mapping diagnostics and diagnostic-only topology observation over immutable room data only
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
- Do not claim gameplay support just because an unchecked room shows richer topology variation.
- Do not silently rewrite the hero start into a standable position as if that were now source-backed truth.
- Do not turn this into a broad viewer refactor or a generalized topology framework; the target is one bounded evidence-source decision and, at most, one evidence-room selection pass.
- Treat “unchecked rooms are not an acceptable basis” as a valid successful outcome.
- Treat “no qualifying evidence-only room found” as a valid successful outcome.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/runtime/world_query.zig` remains the canonical runtime-owned query surface and stays exported through `port/src/root.zig`
- `port/src/runtime/room_state.zig` still owns guarded room loading and immutable room/render snapshots
- `port/src/runtime/session.zig` still owns mutable state only and does not absorb mapping-query, transform-selection, topology-policy, or spawn-policy responsibilities
- runtime-owned tests still prove the `19/19` pinned neighbor summary remains unchanged
- runtime or test-local evidence work makes the evidence-source decision explicit:
  - unchecked evidence-only rooms are either explicitly rejected as a basis for future topology relation classes
  - or explicitly allowed for discovery-only use, with that allowance kept outside the public runtime boundary
- if unchecked evidence-only rooms are allowed, tests or offline helpers rank candidate rooms by observed neighbor-pattern variety instead of assuming `11/10`
- if a room is chosen, tests prove whether it does or does not introduce non-flat or blocked occupied-neighbor cases beyond the pinned `19/19` baseline
- no new CLI/debug-report command or viewer surface is added just to expose the decision result
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no metadata-only room inspection path exists in the canonical code
- no unchecked path is added to the runtime public surface
