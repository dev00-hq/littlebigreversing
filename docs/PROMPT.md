# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, and `platform_windows`.

The previous life-boundary proof slice is complete in the current worktree:

- `port/src/runtime/room_state.zig` still owns the canonical guarded room/load seam plus immutable room/render snapshots.
- `port/src/runtime/session.zig` still owns mutable frame-to-frame runtime state only.
- `port/src/runtime/world_query.zig` still owns pure topology/query logic over immutable room data only.
- `port/src/root.zig` still exposes the canonical `runtime` module map, including `world_query`.
- `inspect-room`, the viewer runtime, and their tests still share the same guarded room/load seam.
- `19/19` remains the only positive guarded runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded negative `ViewerUnsupportedSceneLife` cases.
- `11/10` remains available only on the explicit test-only unchecked evidence path.
- the guarded negative set is now pinned to exact first-hit life blockers:
  - `SCENE.HQR[2]`: hero `LM_DEFAULT` at byte offset `170`
  - `SCENE.HQR[44]`: hero `LM_END_SWITCH` at byte offset `713`
  - `SCENE.HQR[11]`: object `12` `LM_DEFAULT` at byte offset `38`
- the guarded ordering trap is now explicit:
  - guarded `44/2` rejects on unsupported life first
  - unchecked `44/2` later reveals `ViewerSceneMustBeInterior`

The next slice is not more viewer polish, not more life-boundary work, and not live input wiring yet. The next slice is a bounded locomotion-policy proof on the supported `19/19` baseline:

- define the minimum runtime-owned move-evaluation policy needed to answer whether an arbitrary hero world position is admissible on guarded `19/19`
- prove that policy with tests before binding any controls in the app loop
- keep the result inside branch B without life execution

Implement a current-state runtime slice that:

- keeps `port/src/runtime/world_query.zig` as the canonical owner of geometry/standability/move evaluation
- keeps `port/src/runtime/session.zig` as mutable hero state only
- keeps `port/src/runtime/room_state.zig` as the guarded room/load seam only
- keeps supported runtime scope at guarded `19/19` only
- does not execute life scripts
- does not widen scene support
- does not bind movement controls in `port/src/main.zig` yet

The target is narrow:

- define and test the minimal move-policy seam for arbitrary world positions on `19/19`
- prove at least one allowed move and several rejected moves using guarded room data only
- leave live controls and classic key-binding adoption for a later slice

Important current-state constraint:

- on guarded `19/19`, the baked hero start is still diagnostically invalid:
  - `probeHeroStart()` reports `mapped_cell_empty`
  - the mapped raw cell is `3/7`
  - the point sits outside occupied bounds
- this slice must not silently normalize that by auto-snapping the runtime session, rewriting the guarded load seam, or treating the nearest standable candidate as the canonical spawn point on normal runtime paths

Useful work in scope includes:

- adding a minimal `world_query` helper that evaluates an arbitrary current world position or candidate move target against the guarded room snapshot
- reusing the existing composition-grid, top-surface, and standability logic instead of inventing a parallel movement grid
- pinning a seeded valid standable point on `19/19` in tests and evaluating moves from that point
- asserting concrete accepted/rejected outcomes for:
  - a standable occupied target
  - an empty or outside-occupied-bounds target
  - an out-of-bounds target
  - a blocked or otherwise non-standable target if the checked-in room data exposes one
- keeping zone observations diagnostic-only unless a test proves they matter to the move-policy seam

Keep the implementation honest about current product boundaries:

- no life interpreter
- no scene transitions
- no object behavior or AI
- no combat, inventory, or interaction system
- no unchecked room path added to the runtime public surface
- no viewer-HUD expansion just to display move-policy state
- no classic key-binding adoption yet
- no camera behavior work
- no silent hero-start correction on normal runtime paths

Default to the hard-cut current-state path:

- do not move guarded loading out of `port/src/runtime/room_state.zig`
- do not move runtime geometry/query ownership out of `port/src/runtime/world_query.zig`
- do not turn `session.zig` into a collision or topology owner
- do not use `11/10` or any unchecked room as if it were a supported runtime movement fixture
- do not widen the public runtime surface around unsupported life
- do not wire `docs/ingame_keyboard_layout.json` into the app yet; keep it as future reference for the later input-binding slice

The intended ownership boundary after this slice remains:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic and the minimal move-policy evaluation over immutable room data only
- `app/viewer/*`: viewer-local layout, draw, HUD, fragment comparison, and interaction state
- `main.zig`: current viewer loop only, with fragment-panel navigation unchanged for now

Relevant files are likely in:

- `port/src/runtime/world_query.zig`
- `port/src/runtime/session.zig`
- `port/src/runtime/room_state.zig`
- `port/src/main.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/runtime/world_query.zig` tests
- `docs/ingame_keyboard_layout.json`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Keep the baked `19/19` hero start diagnostic-only until a later slice explicitly decides what runtime spawn normalization policy should be.
- Treat nearest-cell and standability evidence as input to the move-policy seam, not as permission to silently rewrite spawn semantics.
- Keep branch B intact: no support for `LM_DEFAULT` or `LM_END_SWITCH`, no life execution, no gameplay widening beyond what this slice explicitly proves.
- Keep `docs/ingame_keyboard_layout.json` out of implementation scope for now; it belongs to the later live-input slice.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/runtime/room_state.zig` still owns guarded room loading and immutable room/render snapshots
- `port/src/runtime/session.zig` still owns mutable state only
- `port/src/runtime/world_query.zig` remains the canonical runtime-owned query surface and stays exported through `port/src/root.zig`
- tests prove a bounded move-policy result for arbitrary world positions on guarded `19/19`
- tests make the invalid baked `19/19` hero start explicit and keep it separate from any seeded valid movement fixture
- `port/src/main.zig` still does not bind live hero locomotion controls yet
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no new public CLI/debug-report command is added just to expose move-policy diagnostics
