# Current Focus

## Current Priorities

- Keep the `codex-memory-v2` tree canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary.
- Keep the runtime/load seam fail-fast on unsupported switch-family life.
- Keep `runtime/session.zig` on explicit world-position seeds.
- Keep `runtime/world_query.zig` as the guarded query owner of exact containing-zone membership and raw target-cell evaluation.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam while future widening stays diagnostics-only.
- Keep `app/viewer_shell.zig` as the viewer-local locomotion-summary owner: HUD uses direction/cell/status plus `ZONES ...`, stderr uses structured move-options plus `zones=...`, and both stay runtime-owned.
- Keep `app/viewer/render.zig` as the display-only owner of admitted-path schematic cues.
- Keep fast Windows validation additive: use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` for iteration; bare commands stay canonical.

## Active Streams

- Guarded `19/19` viewer/runtime diagnostics: keep runtime-owned containing-zone membership and admitted-path target-cell evidence explicit in HUD, stderr, and schematic overlays on seeded, accepted, and admitted-position rejected statuses only.
- Fast Windows validation through `zig build test-fast` and `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.
- Memory hygiene: keep canonical pickup on `docs/codex_memory/`, the roadmap, and the live `port/` tree, not `sidequest/` or `LM_TASKS/`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, which are now explicitly rejected from the current parity target.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next guarded `SCENE.HQR[19]` slice on other movement-semantic evidence beyond landed zone-summary, target-cell diagnostics, and schematic overlays, not new movement policy or invented zone heuristics.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work scoped to rejection diagnostics, fail-fast coverage for unsupported switch-family opcodes, or a reopened evidence pass only if new checked-in primary-source evidence appears.
- Keep `2/2`, `44/2`, and `11/10` on their current guarded or evidence-only roles unless the runtime boundary widens explicitly.
- Keep canonical memory focused on current-state port work; keep `sidequest/` and `LM_TASKS/` independent until promoted.

## Relevant Subsystem Packs

- architecture
- assets
- scene_decode
- backgrounds
- life_scripts
- platform_windows
