# Current Focus

## Current Priorities

- Keep `codex-memory-v2` canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary and fail-fast at the runtime/load seam.
- Keep `runtime/world_query.zig` owning exact zones, move-target evaluation, raw-start diagnostics, and move-option plus target occupied coverage.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam, including topology, footing, attempts, move-option coverage, and rejected-target coverage.
- Keep `runtime/room_state.zig` owning the guarded room/load seam plus first-hit unsupported-life diagnostics for guarded negative loads.
- Keep `main.zig` on input routing plus guarded negative startup formatting.
- Keep `app/viewer_shell.zig` owning HUD/stderr copy for `ZONES`, `TOPO`, `SURF`, `move_options=...`, rejected-target coverage, and raw-start `DIAG` / `BOUNDS` / `NEAR`.
- Keep fast Windows validation additive: `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.

## Active Streams

- Guarded `19/19` diagnostics: keep zone, topology/current-footing, widened `move_options=...`, rejected-target coverage, and raw-start coverage/nearest-candidate explicit while schematic/attempt stay admitted-path-only.
- Guarded negative-load diagnostics: keep `ViewerUnsupportedSceneLife` fail-fast, but surface the first blocking opcode/id/offset for `2/2`, `44/2`, and `11/10` on both `inspect-room` and viewer startup.
- Fast Windows validation through `zig build test-fast` and `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.
- Memory hygiene: keep canonical pickup on `docs/codex_memory/`, the roadmap, and the live `port/` tree.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next guarded `19/19` slice on runtime-owned neighbor-pattern evidence, not new movement policy, mapping narratives, or viewer-side probing.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work on widening guarded unsupported-life diagnostics, adding unsupported-opcode fail-fast coverage, or reopening evidence only with new checked-in proof.
- Keep `2/2`, `44/2`, and `11/10` on their current guarded or evidence-only roles unless the runtime boundary widens explicitly.
- Keep canonical memory focused on current-state port work; keep `sidequest/` and `LM_TASKS/` independent until promoted.

## Relevant Subsystem Packs

- architecture
- assets
- backgrounds
- life_scripts
- platform_windows
