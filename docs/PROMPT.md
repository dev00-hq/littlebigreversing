# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries, exact move-target evaluation, the raw hero-start probe, diagnostic-only local neighbor topology, and occupied-coverage evidence over immutable guarded room data.
- `runtime/locomotion.zig` owns the guarded `19/19` step/result seam. Raw invalid start already packages occupied-coverage plus nearest-candidate evidence, and admitted-path statuses already package target-cell, zone, local-topology, footing, and attempt data.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`, plus admitted-path `ZONES ...`, `TOPO ...`, and `SURF ...`.
- `app/viewer/render.zig` already owns the landed admitted-path schematic and attempt cues on the zero-fragment guarded path. Treat those cues as baseline, not next work.
- `main.zig` owns input routing only.
- Raw invalid start and `origin_invalid` rejection still stay separate from the admitted-path movement surface.

Next slice:

- Surface rejected-target occupied-coverage evidence for admitted-position `last_move_rejected` only, reusing the `evaluateHeroMoveTarget()` result already computed inside `runtime/locomotion.applyStep()`.
- Keep this slice runtime-owned and diagnostic-first: extend structured stderr diagnostics for `rejection_stage=target_rejected` with stable `target_occupied_coverage=...`, `target_occupied_bounds=...`, `target_occupied_bounds_dx=...`, and `target_occupied_bounds_dz=...` fields.
- Keep raw invalid start and `origin_invalid` rejection separate and unchanged. Do not imply the runtime admitted the baked invalid path or evaluated alternate movement semantics there.
- Keep `move_options=` on its current stable contract for this slice. Do not widen it into per-option coverage payloads just because the underlying query data exists.
- Keep HUD and render contracts unchanged unless a tiny consistency edit is required by tests. Do not churn the admitted-path line budget or schematic cue for this slice.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract here.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start diagnostics, admitted-path local-topology discovery, and target occupied-coverage evidence
- `locomotion.zig`: runtime step/result owner and raw-start/admitted-path evidence packaging only; it may thread the already-computed rejected-target occupied coverage, but it must not invent heuristic reinterpretation or viewer-facing copy
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute probes or invent mapping policy
- `render.zig`: display only; keep the admitted-path schematic cue exactly as landed and keep raw-start text-driven on this slice
- `main.zig`: input routing only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep admitted-path target overlays absent on both paths.

Useful work in scope:

- Add rejected-target occupied-coverage packaging to the admitted-position `last_move_rejected` runtime status, while keeping it absent on `origin_invalid`.
- Reuse the existing viewer-shell occupied-coverage formatting helpers for the new rejected-target structured diagnostics instead of inventing a second format.
- Keep viewer-shell HUD copy unchanged unless tests force a tiny consistency fix; the primary output surface on this slice is structured stderr.
- Keep render code unchanged unless a test-only adjustment is required to preserve the landed raw-start/no-schematic and admitted-path schematic contracts.
- Pin runtime locomotion tests so the packaged rejected-target coverage cannot drift away from the runtime-owned `MoveTargetEvaluation`.
- Pin viewer-shell tests so `target_rejected` diagnostics gain the new fields while raw-start and `origin_invalid` keep their existing contracts.

Acceptance:

- Runtime locomotion tests stay green and prove admitted-position `target_rejected` packages the existing target occupied-coverage evidence, while `origin_invalid` still omits it and session-mutation behavior stays unchanged.
- Viewer-shell tests prove structured stderr diagnostics for admitted-position `target_rejected` include `target_occupied_coverage`, `target_occupied_bounds`, `target_occupied_bounds_dx`, and `target_occupied_bounds_dz`, while raw-start and `origin_invalid` keep their landed contracts.
- Render tests stay green without requiring a new schematic or HUD contract on this slice.
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
