# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries, exact move-target evaluation, raw hero-start diagnostics, local-neighbor topology discovery, occupied-coverage evidence, and the already-computed cardinal move-option evaluations over immutable guarded room data.
- `runtime/locomotion.zig` owns the guarded `19/19` step/result seam. Raw invalid start already packages occupied-coverage plus nearest-candidate evidence, admitted-path statuses already package target-cell, zone, local-topology, footing, and attempt data, and admitted-position `target_rejected` already packages explicit rejected-target occupied coverage.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`, admitted-path `ZONES ...`, `TOPO ...`, and `SURF ...`, and admitted-position `target_rejected` structured stderr coverage fields.
- `app/viewer/render.zig` already owns the landed admitted-path schematic and attempt cues on the zero-fragment guarded path. Treat those cues as baseline, not next work.
- `main.zig` owns input routing only.
- `move_options=` currently stays on the older `direction:cell:status` structured stderr contract even though the runtime already has per-option occupied-coverage evidence available from `evaluateCardinalMoveOptions()`.

Next slice:

- Widen admitted-path `move_options=` diagnostics to carry compact per-option occupied-coverage evidence from the existing runtime-owned cardinal move-option evaluations.
- Keep this slice runtime-owned and diagnostic-first: extend each structured stderr `move_options=` entry from `direction:cell:status` to `direction:cell:status:coverage_relation:coverage_dx:coverage_dz`.
- Thread the new per-option coverage through `runtime/locomotion.MoveOptions` so seeded, accepted, and admitted-position rejected statuses all reuse the same runtime-owned payload.
- Keep explicit rejected-target `target_occupied_coverage=...`, `target_occupied_bounds=...`, `target_occupied_bounds_dx=...`, and `target_occupied_bounds_dz=...` fields unchanged. They remain the chosen-attempt surface; widened `move_options=` is complementary context, not a replacement.
- Keep raw invalid start and `origin_invalid` rejection separate and unchanged. Do not invent move options on either path.
- Keep the widened `move_options=` contract compact. Do not embed full occupied-bounds strings or other bulky per-option payloads in each entry for this slice.
- Keep HUD copy and render contracts unchanged unless a tiny consistency fix is required by tests. The primary output surface on this slice is structured stderr.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract here.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start diagnostics, admitted-path local-topology discovery, occupied-coverage evidence, and the underlying cardinal move-option evaluations
- `locomotion.zig`: runtime step/result owner and move-option packaging owner only; it may thread the already-computed per-option occupied coverage, but it must not invent heuristic reinterpretation or viewer-facing copy
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute queries or invent movement policy
- `render.zig`: display only; keep the admitted-path schematic and attempt cue exactly as landed on this slice
- `main.zig`: input routing only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep target overlays absent on both paths.

Useful work in scope:

- Add per-option occupied-coverage packaging to `runtime/locomotion.MoveOptions`, reusing the already-computed `evaluateCardinalMoveOptions()` results instead of issuing fresh probes.
- Widen `viewer_shell` structured stderr `move_options=` formatting to include each option's coverage relation plus `dx` / `dz` distance from occupied bounds.
- Keep the admitted-path HUD lines and render overlays unchanged unless a tiny test-driven consistency edit is required.
- Pin runtime locomotion tests so the packaged move-option coverage cannot drift away from the runtime-owned cardinal move-option evaluations.
- Pin viewer-shell tests so seeded, accepted, and admitted-position rejected structured stderr diagnostics gain the widened `move_options=` contract while raw-start and `origin_invalid` keep `move_options=unavailable`.

Acceptance:

- Runtime locomotion tests stay green and prove admitted-path `MoveOptions` now preserve per-option occupied-coverage evidence from `evaluateCardinalMoveOptions()`.
- Viewer-shell tests prove seeded, accepted, and admitted-position rejected structured stderr diagnostics widen `move_options=` to `direction:cell:status:coverage_relation:coverage_dx:coverage_dz`.
- Raw-start and `origin_invalid` diagnostics keep their landed `move_options=unavailable` contract.
- HUD and render tests stay green without requiring a new schematic, attempt cue, or HUD line on this slice.
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
