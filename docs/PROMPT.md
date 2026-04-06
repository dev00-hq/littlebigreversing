# Next Prompt

Relevant subsystem packs for this task: `architecture`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives, with `11/10` staying test-only.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries, exact move-target evaluation, raw hero-start diagnostics, target occupied-coverage evidence, and the underlying admitted-path cardinal move-option coverage data over immutable guarded room data.
- `runtime/locomotion.zig` owns the guarded `19/19` step/result seam, including raw-start plus admitted-path topology, footing, attempt, move-option occupied coverage, and rejected-target coverage packaging.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus first-hit unsupported-life diagnostics for guarded negative loads.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`, admitted-path `ZONES ...` / `TOPO ...` / `SURF ...`, widened structured stderr `move_options=...` coverage diagnostics, and admitted-position `target_rejected` explicit rejected-target coverage fields.
- `app/viewer/render.zig` already owns the landed admitted-path schematic and attempt cues on the zero-fragment guarded path. Treat those cues as baseline, not next work.
- `main.zig` owns input routing only.
- Guarded negative `inspect-room` loads now keep `ViewerUnsupportedSceneLife` as the public failure while preceding it with `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` for the first blocking blob only.

Next slice:

- Surface the same guarded unsupported-life first-hit diagnostics on the viewer startup failure path, not just `inspect-room`.
- Keep this slice load-seam-owned and fail-fast: when `lba2` rejects `2/2`, `44/2`, or `11/10` with `ViewerUnsupportedSceneLife`, print the same stable `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the existing error.
- Reuse the existing `runtime/room_state.zig` unsupported-life helper instead of re-auditing scene life a second way in `main.zig`.
- Preserve the current `inspect-room` failure contract, the positive `19/19` startup path, and the guarded scene boundary exactly as landed.
- Keep viewer success-path HUD/render output unchanged on this slice. The only output surface that should change is the negative startup stderr path for unsupported scene life.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract here.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start diagnostics, admitted-path local-topology discovery, occupied-coverage evidence, and the underlying cardinal move-option evaluations
- `locomotion.zig`: runtime step/result owner only; do not reopen it for this slice
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam and unsupported-life first-hit diagnostic helper only; it must not grow a second compatibility load path
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute probes or invent movement policy
- `render.zig`: display only; keep the admitted-path schematic and attempt cue exactly as landed on this slice
- `main.zig`: input routing plus negative startup error formatting only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep the landed admitted-path schematic/attempt overlays unchanged while raw-start and `origin_invalid` remain overlay-free.
- Keep `ViewerUnsupportedSceneLife` as the public error. Do not add a new success or fallback path for unsupported scene life just to surface richer diagnostics.

Useful work in scope:

- Reuse the landed `runtime/room_state.inspectUnsupportedSceneLifeHit()` helper from `main.zig` instead of duplicating scene-life audit logic.
- Add a small negative-startup stderr contract test or harness coverage so the viewer failure path cannot silently drift back to bare `ViewerUnsupportedSceneLife`.
- Keep `inspect-room` negative-load diagnostics unchanged unless a tiny consistency edit is required by tests.
- Keep the positive `19/19` viewer startup path and canonical Windows verifier green.

Acceptance:

- The viewer startup failure path for `2/2`, `44/2`, and `11/10` prints the same guarded `room_load_rejected` unsupported-life fields that `inspect-room` now emits, then still fails with `ViewerUnsupportedSceneLife`.
- `inspect-room` negative-load diagnostics keep the landed first-hit blocker contract unchanged.
- The positive `19/19` viewer startup path stays green and keeps its current stderr, HUD, and render behavior.
- `room_state.zig` remains the canonical guarded load seam.
- `main.zig` remains the canonical viewer startup owner.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build run -- --scene-entry 2 --background-entry 2`
  - `cd ..`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
