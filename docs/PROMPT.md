# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries and exact move-target evaluation, including raw target-cell mapping and `MoveTargetStatus`.
- `runtime/locomotion.zig` owns step/result policy and the guarded `19/19` seam. It already threads runtime-owned zone membership and target-cell evidence through `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already formats runtime-owned zone summaries as `ZONES NONE` or stable scene-order lists, and it already formats move-option target-cell evidence from runtime-owned data.
- `app/viewer/render.zig` owns display only. Today it renders the hero crosshair plus HUD text, but it does not yet surface admitted-path move-option evidence on the schematic grid itself.
- `main.zig` owns input routing only.
- The zone-summary surfacing and target-cell threading are already landed. Treat them as baseline, not next work.
- Raw invalid start and `origin_invalid` rejection still stay separate from the admitted-path movement surface.

Next slice:

- Add the next diagnostics-only movement-semantic cue as a viewer-local schematic overlay on the existing guarded `19/19` zero-fragment grid.
- Use the already-landed runtime-owned admitted-path evidence only: current admitted cell plus the four cardinal target cells with their existing `MoveTargetStatus`.
- For `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`, surface that evidence directly on the schematic with compact cell overlays. The most grounded version is: highlight the current admitted cell, outline each target cell, and label the target cells with their cardinal direction while color-coding from the existing `MoveTargetStatus`.
- Keep raw invalid start and `origin_invalid` rejection free of admitted-path target overlays. Do not imply admitted movement semantics on the baked invalid path.
- Keep the existing HUD `direction/cell/status` plus `ZONES ...` lines and the existing structured stderr diagnostics as the landed textual contract. This slice is about adding the schematic cue, not replacing the text path.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner
- `locomotion.zig`: runtime step/result owner and admitted-path evidence packaging
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute move targets
- `render.zig`: display only; it may project grid cells and draw the schematic cue from viewer-supplied display payload
- `main.zig`: input routing only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.

Useful work in scope:

- Extend `render.LocomotionStatusDisplay` or an equivalent render-owned display payload so render can consume current-cell and cardinal target-cell/status evidence without parsing HUD text or querying runtime directly.
- Have `viewer_shell.zig` populate that display payload from the existing runtime-owned locomotion result only.
- Draw deterministic schematic overlays for the admitted path: one current-cell cue plus four cardinal target-cell cues, with color and labels derived from the already-owned move-option data.
- Keep raw invalid-start copy separate and keep admitted-path target overlays absent on the baked invalid start and `origin_invalid` rejection path.
- Preserve the landed HUD and stderr text contract unless a tiny companion copy change is required to keep the new schematic cue understandable.
- Pin viewer-shell and render tests so the schematic cue cannot drift away from the landed target-cell and zone-summary contract.

Acceptance:

- Runtime locomotion tests stay green and continue to prove seeded, accepted, and admitted-position rejected statuses preserve runtime-owned target-cell mapping and zone membership on the guarded `19/19` fixture path.
- Viewer-shell tests prove the viewer packages the admitted-path current-cell and target-cell/status evidence into the render-facing display payload without reintroducing viewer-owned move evaluation, while keeping explicit `ZONES NONE` in the HUD path and explicit `zones=...` in stderr.
- Render tests prove the zero-fragment guarded path keeps raw invalid start separate and adds deterministic schematic overlays for:
  - seeded admitted status at `39/6`
  - accepted south step at `39/7`
  - rejected west step preserving `39/6`
- Render tests also prove the baked raw invalid start and the `origin_invalid` path do not gain admitted-path target overlays.
- Stderr diagnostics keep exposing the same runtime-owned zone summary and structured move-option evidence for seeded, accepted, and admitted-position rejected runtime statuses.
- `world_query.zig` remains the canonical pure move/query surface.
- `locomotion.zig` remains the canonical runtime step/result seam.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
