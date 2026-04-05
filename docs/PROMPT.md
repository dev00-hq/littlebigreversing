# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, and `platform_windows`.

The guarded `19/19` viewer/runtime movement-prep slices are already landed in the current worktree:

- `port/src/runtime/world_query.zig` already owns:
  - move-target evaluation over immutable guarded room data
  - cardinal move-option evaluation for an admitted hero position
  - bounded topology/query evidence on the guarded `19/19` baseline
- `port/src/runtime/session.zig` already owns mutable hero position only.
- `port/src/runtime/room_state.zig` already owns the guarded room/load seam and immutable room/render snapshots.
- `port/src/app/viewer_shell.zig` already owns:
  - explicit fixture seeding for guarded `19/19`
  - viewer-local step attempts and status formatting
  - zero-fragment locomotion diagnostics/copy on top of the current guarded runtime path
- `port/src/main.zig` already routes:
  - `Enter` to explicit fixture seeding only
  - arrows to fragment navigation when a fragment panel is active
  - arrows to hero movement when no fragment panel is active
- Branch B remains active:
  - `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary
  - `19/19` is the only positive guarded runtime/load pair
  - `2/2`, `44/2`, and `11/10` stay guarded `ViewerUnsupportedSceneLife` negatives

That viewer-facing movement-semantic slice is complete. The next slice must stop living in viewer glue and start Phase 5 Branch B gameplay work: land a runtime-owned guarded `19/19` hero step/update seam, with bounded current-zone membership on the same path.

Implement a current-state slice that:

- adds a runtime-owned hero locomotion module under `port/src/runtime/` for guarded Branch B movement application
- moves one-cell cardinal step application out of `port/src/app/viewer_shell.zig` and into that runtime-owned seam
- keeps `runtime/world_query.zig` as the only owner of move evaluation and adds only the minimum pure query helper needed to derive current scene-zone membership for a hero world position
- lets the runtime-owned seam mutate `Session` only on allowed movement
- returns structured runtime step results that distinguish:
  - invalid-origin rejection from the baked raw start
  - accepted seeded movement
  - rejected seeded movement with the existing `MoveTargetStatus`
- includes bounded current-zone membership in that structured runtime result:
  - at the current admitted hero position after an accepted move
  - unchanged current admitted position on a rejected move
- keeps `viewer_shell.zig` as a consumer of runtime-owned movement results for formatting and diagnostics, not as a movement-policy owner

Keep ownership hard-cut and explicit:

- `world_query.zig`: pure guarded room query/evaluation owner, including any new pure zone-membership query helper
- `session.zig`: mutable session state only
- new runtime locomotion module: step application policy, session mutation, and structured runtime step result
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: explicit fixture seeding plus formatting/diagnostics only; do not leave step policy here
- `render.zig`: display only; do not add gameplay policy
- `main.zig`: input routing only

Keep the implementation honest about Branch B scope:

- no life execution
- no support for `LM_DEFAULT`
- no support for `LM_END_SWITCH`
- no scene transitions
- no object AI
- no inventory/state systems
- no combat
- no track execution yet
- no continuous movement or new input-repeat system
- no auto-seeding
- no spawn normalization
- no unchecked room path added to the public runtime seam
- no new viewer panel or HUD-heavy refinement pass just to expose the runtime result
- no zone-trigger semantics beyond current membership/containment on the guarded runtime path

Important current-state facts that must stay true:

- guarded `19/19` is still the only positive runtime/load pair
- the baked `19/19` hero start remains diagnostically invalid:
  - `probeHeroStart()` reports `mapped_cell_empty`
  - raw mapped cell `3/7`
  - outside occupied bounds
- the checked-in valid `39/6` fixture remains explicit opt-in only
- `2/2`, `44/2`, and `11/10` remain guarded negative cases
- Windows validation stays:
  - `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` for iteration
  - bare `zig build test` plus `scripts/verify-viewer.ps1` as the canonical full gate

Useful work in scope includes:

- introducing a dedicated runtime-owned step result type instead of reusing viewer-local display structs
- adding a pure `world_query` helper that reports which checked-in scene zones contain a world point on the guarded runtime path
- proving exact current-zone membership for the explicit seeded fixture and the accepted seeded south step in tests, instead of inventing zone semantics in prose
- keeping the current zero-fragment viewer path working by consuming the new runtime result rather than duplicating movement logic in the viewer

Acceptance:

- a new runtime test file proves the runtime-owned locomotion seam for guarded `19/19`:
  - raw invalid start rejects and does not mutate session state
  - explicit seed to `39/6`
  - accepted seeded south step mutates session state
  - rejected seeded west step does not mutate session state and reports `target_empty`
- the same runtime tests pin the exact current-zone membership for:
  - seeded `39/6`
  - accepted seeded south step
  - rejected seeded west step preserving the pre-rejection current-zone membership
- `viewer_shell` tests or `main`-path tests prove the viewer/runtime wiring now consumes the runtime-owned movement result instead of owning step policy itself
- `world_query.zig` remains the canonical move-evaluation/query surface
- `session.zig` remains mutable-state-only
- `room_state.zig` remains the guarded room/load seam only
- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
