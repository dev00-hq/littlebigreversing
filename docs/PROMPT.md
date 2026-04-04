# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.

The previous viewer-local locomotion harness slice is complete and accepted in the current worktree:

- `port/src/runtime/world_query.zig` still owns the canonical move-evaluation seam.
- `port/src/runtime/session.zig` still owns mutable hero state only.
- `port/src/runtime/room_state.zig` still owns the guarded room/load seam plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` now owns the explicit viewer-local locomotion harness:
  - raw guarded `19/19` hero start remains invalid and non-mutating
  - `Enter` seeds the session to the checked-in valid `39/6` fixture on an explicit action only
  - arrow keys attempt cardinal movement only when no fragment panel is active
  - fragment-panel navigation remains unchanged when a fragment panel is present
- `port/src/app/viewer/render.zig` now advertises the locomotion controls on the zero-fragment guarded path without adding a new HUD panel.
- `zig build test` and `.\scripts\verify-viewer.ps1` both pass on this branch after the harness landed.

The next slice is not more controls, not classic keymap adoption, not auto-seeding, and not gameplay widening. The next slice is a bounded locomotion-status surface for guarded `19/19` only:

- keep the current harness behavior exactly as-is
- make its state explicit instead of widening policy again
- reuse existing viewer copy/HUD surfaces instead of inventing a new panel

Implement a current-state viewer slice that:

- keeps `port/src/runtime/world_query.zig` as the canonical move-evaluation surface
- keeps `port/src/runtime/session.zig` as mutable hero state only
- keeps `port/src/runtime/room_state.zig` as the guarded room/load seam only
- keeps `Enter` seeding, arrow-key movement, and fragment-navigation routing exactly as they work now
- adds a viewer-local locomotion status snapshot/formatter over the existing harness state
- surfaces that status through existing copy/HUD surfaces only

The target is narrow:

- define a viewer-local locomotion status model that can represent:
  - initial raw-invalid start
  - explicit seeded-valid state
  - last move accepted
  - last move rejected, including the existing move-target reason
- keep the current stderr diagnostics aligned with that status model if possible
- thread the status through the viewer-local surfaces without adding new keys or changing control routing
- prove the status output with focused tests instead of adding broader interactivity

Important current-state constraints:

- on guarded `19/19`, the baked hero start is still diagnostically invalid:
  - `probeHeroStart()` reports `mapped_cell_empty`
  - the mapped raw cell is `3/7`
  - the point sits outside occupied bounds
- the checked-in valid `39/6` fixture is still explicit viewer-local opt-in only
- this slice must not silently normalize startup, rewrite the guarded load seam, or turn the fixture into the canonical spawn
- this slice must not widen movement semantics beyond the already-landed one-cell cardinal harness

Useful work in scope includes:

- introducing a viewer-local locomotion status struct in `app/viewer_shell.zig` or another viewer-local seam
- deriving status from the already-landed seed and move-attempt helpers instead of re-evaluating policy in the renderer
- formatting concise status text that can live in existing HUD/copy surfaces
- updating render tests and viewer-shell tests to pin the exact status wording or structured fields for:
  - raw-invalid start
  - seeded-valid state at `39/6`
  - accepted seeded step
  - rejected seeded step with the move-target rejection reason

Keep the implementation honest about current product boundaries:

- no new control bindings
- no classic keymap adoption
- no auto-seeding
- no spawn normalization
- no new HUD card or dedicated locomotion panel
- no scene transitions
- no life interpreter
- no gameplay widening
- no unchecked room path added to the public viewer/runtime seam

Default to the hard-cut current-state path:

- do not move move-policy ownership out of `port/src/runtime/world_query.zig`
- do not turn `session.zig` into a status or policy owner
- do not let `main.zig` grow a second interaction system; keep control routing unchanged
- do not add a new CLI/debug-report command just to expose locomotion state
- do not wire `docs/ingame_keyboard_layout.json` into the app yet

The intended ownership boundary after this slice remains:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic and move-target evaluation over immutable room data only
- `app/viewer_shell.zig`: viewer-local seeding, step-attempt orchestration, and locomotion status shaping
- `app/viewer/render.zig`: existing copy/HUD surfaces only
- `main.zig`: current control routing only

Relevant files are likely in:

- `port/src/app/viewer_shell.zig`
- `port/src/app/viewer_shell_test.zig`
- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/main.zig`
- `port/src/runtime/world_query.zig`
- `port/src/runtime/session.zig`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Keep the baked `19/19` hero start diagnostic-only until a later slice explicitly changes spawn policy.
- Keep `39/6` as the explicit viewer-local fixture only.
- Keep branch B intact: no support for `LM_DEFAULT` or `LM_END_SWITCH`, no life execution, no gameplay widening beyond what the harness already proves.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- tests prove status output for:
  - initial raw-invalid start
  - explicit seed to `39/6`
  - accepted seeded step
  - rejected seeded step with the move-target reason
- `world_query.zig` remains the canonical move-evaluation surface
- `session.zig` remains mutable-state-only
- `main.zig` control routing stays unchanged
- no new CLI/debug-report command is added just to expose locomotion state
