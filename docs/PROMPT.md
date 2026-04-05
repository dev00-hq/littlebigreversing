# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.

The guarded `19/19` viewer-local locomotion harness, status slice, and topology-style neighbor surface are already landed in the current worktree:

- `port/src/runtime/world_query.zig` already owns move-target evaluation over immutable room data.
- `port/src/runtime/session.zig` already owns mutable hero position only.
- `port/src/runtime/room_state.zig` already owns guarded room loading plus immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` already owns:
  - explicit fixture seeding for guarded `19/19`
  - one-cell cardinal step attempts
  - structured viewer-local locomotion status construction and formatting
  - current-cell topology summaries for admitted zero-fragment hero positions
  - stderr status diagnostics derived from the same viewer-local status model
- `port/src/main.zig` already keeps the current control routing:
  - `Enter` seeds only on explicit action
  - arrows navigate fragments when a fragment panel is active
  - arrows attempt hero movement only when no fragment panel is active
- `port/src/app/viewer/render.zig` already uses existing HUD/copy surfaces and already renders the zero-fragment locomotion status without adding a new panel.
- `port/src/app/viewer_shell_test.zig` and `port/src/app/viewer/render_test.zig` already prove:
  - raw guarded `19/19` start remains invalid and non-mutating
  - explicit seed to the checked-in `39/6` fixture
  - accepted seeded south step
  - rejected seeded west step with `target_empty`
  - zero-fragment `FOCUS`/`NAV` copy for those landed locomotion states and the current topology-style neighbor cues

That topology-style status slice is complete. The next slice is narrower: replace the zero-fragment topology-style neighbor cues with actual cardinal move-option context derived from `MoveTargetStatus` for guarded `19/19` only. Do not widen controls, movement policy, spawn policy, or gameplay scope.

Implement a current-state slice that:

- extends the existing viewer-local locomotion status model in `port/src/app/viewer_shell.zig` with current-cell move-option context instead of a parallel second state object
- derives that move-option context from the current guarded room plus the current session state inside the existing status construction/update path
- uses `runtime/world_query.zig` as the only owner of cardinal target evaluation for one-cell move options
- records concise per-direction `MoveTargetStatus` for the current admitted hero cell
- keeps raw-invalid-start handling explicit by not inventing move options from the invalid baked start
- formats concise move-option copy from that one viewer-local status model
- replaces the current topology-style zero-fragment `FOCUS` card cue lines with move-option lines that are derived from actual move evaluation
- keeps the existing zero-fragment control hints in the `NAV` card
- keeps the raw-invalid-start surface on the landed concise copy only; do not add blank filler move-option lines for invalid starts

The move-option surface must represent:

- no move options for the raw invalid baked start
- move-option statuses for the explicit seeded-valid `39/6` fixture cell
- updated move-option statuses after the accepted seeded south step
- unchanged current-cell move-option statuses after the rejected seeded west step

Keep ownership hard-cut and explicit:

- `world_query.zig`: unchanged owner of topology/query logic and move evaluation; if a helper is added for cardinal move-option evaluation, it belongs here
- `session.zig`: unchanged mutable hero state only; do not store move-option or viewer status data here
- `room_state.zig`: unchanged guarded room/load seam only; do not add viewer-local status or move-option state here
- `viewer_shell.zig`: owns move-option construction, move-option updates, and move-option formatting inside the existing viewer-local locomotion status model
- `render.zig`: receives precomputed status/move-option copy and displays it on the existing zero-fragment `FOCUS` card; do not re-evaluate move policy here
- `main.zig`: only maintains and threads the current viewer-local status through the existing event loop; do not grow a second interaction system

Keep the implementation honest about current boundaries:

- no new control bindings
- no classic keymap adoption
- no auto-seeding
- no spawn normalization
- no new HUD card or dedicated locomotion panel
- no layout resize just to fit extra text; keep the move-option copy concise enough for the existing `FOCUS` card body
- no scene transitions
- no life interpreter
- no gameplay widening
- no unchecked room path added to the public viewer/runtime seam
- no new CLI/debug-report command just to expose move options
- do not wire `docs/ingame_keyboard_layout.json` into the app yet
- do not present topology-only standability as if it were the same thing as an evaluated move option
- do not invent a new movement taxonomy beyond the existing `MoveTargetStatus`

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

- introducing a small `world_query` helper for four cardinal move-option evaluations if that removes duplication while keeping ownership pure
- deriving seeded and post-attempt move-option updates from the already-landed move-evaluation path instead of from the current topology-only probe
- preserving the current landed locomotion headline copy while appending concise move-option lines for admitted cells
- keeping rejected-step copy anchored to the current valid cell rather than the rejected target cell
- updating viewer-shell and render tests to pin the exact structured fields and HUD wording for:
  - raw-invalid start with no move options
  - seeded-valid state at `39/6`
  - accepted seeded south step
  - rejected seeded west step with `target_empty`

Acceptance:

- `port/src/app/viewer_shell_test.zig` proves the structured move-option state for:
  - raw-invalid start with no move options
  - explicit seed to `39/6`
  - accepted seeded south step
  - rejected seeded west step with `target_empty`
- `port/src/app/viewer/render_test.zig` proves the zero-fragment guarded HUD/copy surface shows the expected locomotion headline text plus the expected move-option text instead of the older topology-style cue text
- the existing zero-fragment `NAV` card still advertises `ENTER SEED HERO`, `ARROWS MOVE HERO`, and `RAW START STAYS`
- `port/src/main.zig` control routing stays unchanged except for maintaining and passing the richer single viewer-local status value
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
