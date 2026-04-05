# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.

The viewer-local locomotion harness slice is already landed in the current worktree:

- `port/src/runtime/world_query.zig` owns move-target evaluation over immutable room data.
- `port/src/runtime/session.zig` owns mutable hero position only.
- `port/src/runtime/room_state.zig` owns guarded room loading plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` already owns:
  - explicit fixture seeding for guarded `19/19`
  - one-cell cardinal step attempts
  - stderr seed/move diagnostics
- `port/src/main.zig` already keeps the current control routing:
  - `Enter` seeds only on explicit action
  - arrows navigate fragments when a fragment panel is active
  - arrows attempt hero movement only when no fragment panel is active
- `port/src/app/viewer/render.zig` already uses existing HUD/copy surfaces and already advertises the zero-fragment locomotion harness without adding a new panel.
- `port/src/app/viewer_shell_test.zig` already proves:
  - raw guarded `19/19` start remains invalid and non-mutating
  - explicit seed to the checked-in `39/6` fixture
  - accepted seeded south step
  - rejected seeded west step

That harness slice is complete. The next slice is narrower: add a viewer-local locomotion status surface for guarded `19/19` only. Do not widen controls, movement policy, spawn policy, or gameplay scope.

Implement a current-state slice that:

- adds a viewer-local locomotion status model in `port/src/app/viewer_shell.zig`
- initializes that status from the current guarded room plus the current session state
- updates that status after explicit seed and move attempts
- formats concise status copy from that viewer-local model
- threads the precomputed status through `port/src/main.zig` into `port/src/app/viewer/render.zig`
- renders that status through existing HUD/copy surfaces only
- keeps the existing zero-fragment control hints in the `NAV` card and uses the zero-fragment `FOCUS` card as the preferred status surface

The status model must represent:

- initial raw-invalid start
- explicit seeded-valid state
- last move accepted
- last move rejected, including the `MoveTargetStatus`

Keep ownership hard-cut and explicit:

- `world_query.zig`: unchanged owner of topology/query logic and move evaluation
- `session.zig`: unchanged mutable hero state only; do not store locomotion status here
- `room_state.zig`: unchanged guarded room/load seam only; do not add viewer-local status here
- `viewer_shell.zig`: owns status construction, status updates, and status formatting
- `render.zig`: receives precomputed status data/copy and displays it on the existing zero-fragment `FOCUS` card; do not re-evaluate move policy here
- `main.zig`: only maintains and threads the current viewer-local status through the existing event loop; do not grow a second interaction system

Keep the implementation honest about current boundaries:

- no new control bindings
- no classic keymap adoption
- no auto-seeding
- no spawn normalization
- no new HUD card or dedicated locomotion panel
- no scene transitions
- no life interpreter
- no gameplay widening
- no unchecked room path added to the public viewer/runtime seam
- no new CLI/debug-report command just to expose locomotion state
- do not wire `docs/ingame_keyboard_layout.json` into the app yet

Important current-state facts that must stay true:

- guarded `19/19` is still the only positive runtime/load pair
- the baked `19/19` hero start is still diagnostically invalid:
  - `probeHeroStart()` reports `mapped_cell_empty`
  - the mapped raw cell is `3/7`
  - the point sits outside occupied bounds
- the checked-in valid `39/6` fixture remains explicit viewer-local opt-in only
- branch B stays intact:
  - no support for `LM_DEFAULT`
  - no support for `LM_END_SWITCH`
  - no life execution
- guarded `2/2`, `44/2`, and `11/10` remain negative `ViewerUnsupportedSceneLife` cases

Useful work in scope includes:

- introducing a startup-status helper in `app/viewer_shell.zig`
- deriving seed/move status updates from the already-landed helper results instead of re-evaluating policy in the renderer
- preserving the current `NAV` card control wording while replacing the generic zero-fragment `FOCUS` copy with locomotion status
- aligning stderr seed/move diagnostics with the same structured status model when that removes duplication
- updating viewer-shell and render tests to pin the exact structured fields and HUD wording for:
  - raw-invalid start
  - seeded-valid state at `39/6`
  - accepted seeded south step
  - rejected seeded west step with `target_empty`

Acceptance:

- `port/src/app/viewer_shell_test.zig` proves the structured locomotion status for:
  - initial raw-invalid start
  - explicit seed to `39/6`
  - accepted seeded south step
  - rejected seeded west step with `target_empty`
- `port/src/app/viewer/render_test.zig` proves the zero-fragment guarded HUD/copy surface shows the expected locomotion status text
- the existing zero-fragment `NAV` card still advertises `ENTER SEED HERO`, `ARROWS MOVE HERO`, and `RAW START STAYS`
- `port/src/main.zig` control routing stays unchanged except for maintaining and passing the current locomotion status
- `world_query.zig` remains the canonical move-evaluation surface
- `session.zig` remains mutable-state-only
- `room_state.zig` remains the guarded room/load seam only
- `render.zig` does not become a locomotion-policy owner
- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
