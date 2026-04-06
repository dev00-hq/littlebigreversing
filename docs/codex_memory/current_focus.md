# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary and fail-fast at the runtime/load seam.
- Keep `runtime/world_query.zig` owning zones, move-target/raw-start diagnostics, move-option coverage, and the observed-neighbor summary computation.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam for topology, footing, attempts, and rejected-target coverage.
- Keep `runtime/room_state.zig` owning the guarded room/load seam plus first-hit unsupported-life diagnostics for guarded negative loads.
- Keep `main.zig` on input routing plus guarded negative startup formatting.
- Keep `app/viewer_shell.zig` owning HUD/stderr copy for `neighbor_pattern_summary`, `ZONES`, `TOPO`, `SURF`, `move_options=...`, and raw-start `DIAG` / `BOUNDS` / `NEAR`.
- Keep fast Windows validation additive: `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.

## Active Streams

- Guarded `19/19` diagnostics: keep startup `neighbor_pattern_summary`, zone, topology/current-footing, `move_options=...`, rejected-target coverage, and raw-start coverage explicit while schematic/attempt stay admitted-path-only.
- Guarded negative-load diagnostics: keep `ViewerUnsupportedSceneLife` fail-fast, but surface the first blocking opcode/id/offset for `2/2`, `44/2`, and `11/10` on both `inspect-room` and viewer startup.
- Phase 5 branch-B candidate selection: use decoded interior-candidate and scene-metadata evidence to determine whether any fully-decoded interior scene is a better gameplay target than the current guarded `19/19` diagnostic baseline.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- The first Phase 5 playable-path candidate is still unproven under branch B: the only supported positive startup is `19/19`, and it still lands on `raw_invalid_start` with `track_count=0`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next Phase 5 slice on ranking decoded interior candidates from `life_audit` plus scene metadata, because guarded `19/19` still starts `raw_invalid_start` with zero tracks.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work on widening guarded unsupported-life diagnostics, adding unsupported-opcode fail-fast coverage, or reopening evidence only with new checked-in proof.

## Relevant Subsystem Packs

- architecture
- life_scripts
- scene_decode
- platform_windows
