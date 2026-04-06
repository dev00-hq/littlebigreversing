# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is now settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- `runtime/world_query.zig` already owns a guarded `19/19` room-wide local-neighbor evidence summary through `summarizeObservedNeighborPatterns()`, and its tests pin the current baseline counts: `origin_cell_count=1246`, `occupied_surface_count=4828`, `empty_count=107`, `out_of_bounds_count=49`, `missing_top_surface_count=0`, `standable_neighbor_count=4828`, `blocked_neighbor_count=0`, `top_y_delta_buckets=0:4828`.
- `runtime/locomotion.zig` owns the guarded `19/19` step/result seam, including raw-start plus admitted-path topology, footing, attempts, move-option coverage, and rejected-target coverage packaging.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam and the unsupported-life first-hit helper only.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`, admitted-path `ZONES ...` / `TOPO ...` / `SURF ...`, widened structured stderr `move_options=...` coverage diagnostics, and admitted-position `target_rejected` explicit rejected-target coverage fields.
- `app/viewer/render.zig` already owns the landed admitted-path schematic and attempt cues on the zero-fragment guarded path. Treat those cues as baseline, not next work.
- `main.zig` owns input routing plus startup failure formatting only.

Next slice:

- Stay on the guarded `19/19` evidence track, but make it concrete: surface the runtime-owned observed local-neighbor pattern summary on the positive startup stderr path.
- Reuse `runtime/world_query.zig.summarizeObservedNeighborPatterns()` as the canonical computation. Do not recompute counts in `viewer_shell.zig`, `render.zig`, or `main.zig`.
- Keep this slice startup-diagnostic-only: add one stable structured stderr line for the guarded positive `19/19` launch, and keep HUD, render, movement policy, and negative boundary behavior unchanged.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract here.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start diagnostics, admitted-path local-topology discovery, occupied-coverage evidence, the underlying cardinal move-option evaluations, and the observed-neighbor summary computation
- `locomotion.zig`: runtime step/result owner only; do not reopen it for this slice
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam and unsupported-life first-hit diagnostic helper only; it must not grow a second compatibility load path
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it may print the runtime-owned neighbor-summary line, but it must not derive the counts itself
- `render.zig`: display only; keep the admitted-path schematic and attempt cue exactly as landed on this slice
- `main.zig`: input routing plus startup failure formatting only; do not move positive-startup room-query policy into `main.zig`

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep the landed admitted-path schematic/attempt overlays unchanged while raw-start and `origin_invalid` remain overlay-free.
- Keep `ViewerUnsupportedSceneLife` as the public error for the negative boundary, and treat the mirrored startup diagnostics as already-landed regression behavior.

Useful work in scope:

- Thread a runtime-owned `ObservedNeighborPatternSummary` payload from `world_query.zig` to the startup stderr surface without changing locomotion status semantics.
- Print one stable structured line for the guarded positive startup path, for example `event=neighbor_pattern_summary ...`.
- Add focused viewer-shell or verifier coverage so the guarded `19/19` summary line does not silently drift.
- Keep `inspect-room` and negative viewer startup diagnostics unchanged unless a tiny consistency edit is required by tests.

Acceptance:

- The positive guarded `19/19` startup path prints one stable structured neighbor-summary line backed by `summarizeObservedNeighborPatterns()`.
- The summary line preserves the current guarded baseline counts for `19/19`: `origin_cell_count=1246`, `occupied_surface_count=4828`, `empty_count=107`, `out_of_bounds_count=49`, `missing_top_surface_count=0`, `standable_neighbor_count=4828`, `blocked_neighbor_count=0`, and `top_y_delta_buckets=0:4828`.
- The startup negative path for `2/2`, `44/2`, and `11/10` keeps printing the same guarded `room_load_rejected` unsupported-life fields and still fails with `ViewerUnsupportedSceneLife`.
- `inspect-room` negative-load diagnostics keep the landed first-hit blocker contract unchanged.
- The positive `19/19` viewer startup path stays green and keeps its current HUD and render behavior.
- `world_query.zig` remains the computation owner, and `viewer_shell.zig` remains the presentation owner.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build run -- --scene-entry 19 --background-entry 19`
  - `cd ..`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
