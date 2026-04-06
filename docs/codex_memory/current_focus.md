# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary and fail-fast at the runtime/load seam.
- Keep `life_audit.zig` owning offline decoded-interior ranking and `tools/cli.zig` owning `rank-decoded-interior-candidates`.
- Keep `runtime/world_query.zig` owning zones plus move-target/raw-start diagnostics and neighbor-summary computation.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam for topology, footing, attempts, and rejected-target coverage.
- Keep `runtime/room_state.zig` owning the guarded room/load seam plus first-hit unsupported-life diagnostics for guarded negative loads.
- Keep `main.zig` on input routing plus guarded negative startup formatting.
- Keep `app/viewer_shell.zig` owning HUD/stderr copy for `neighbor_pattern_summary`, `ZONES`, `TOPO`, `SURF`, `move_options=...`, and raw-start `DIAG` data.
- Keep fast Windows validation additive: `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.

## Active Streams

- Guarded `19/19` diagnostics: keep `neighbor_pattern_summary`, zone/current-footing, `move_options=...`, rejected-target coverage, and raw-start coverage explicit.
- Guarded negative-load diagnostics: keep `ViewerUnsupportedSceneLife` fail-fast, with first blocking opcode/id/offset on `2/2`, `44/2`, and `11/10`.
- Phase 5 branch-B triage: `rank-decoded-interior-candidates` ranks the `50` decoded interior scenes, with `SCENE.HQR[219]` first and `SCENE.HQR[19]` at `49/50`.
- Top-candidate viability: explain why `inspect-room 219 219 --json` fails with `InvalidFragmentZoneBounds`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- The first Phase 5 playable-path candidate is still unproven under branch B: the only supported positive startup is `19/19`, and it still lands on `raw_invalid_start` with `track_count=0`.
- The top-ranked offline candidate is not yet a valid guarded room/load pair: `inspect-room 219 219 --json` currently fails with `InvalidFragmentZoneBounds`.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next Phase 5 slice on making the `219/219` blocker explicit: surface which fragment-zone bounds or assumptions trigger `InvalidFragmentZoneBounds`.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work on unsupported-life diagnostics or new checked-in proof only.

## Relevant Subsystem Packs

- architecture
- backgrounds
- life_scripts
- scene_decode
- platform_windows
