# Current Focus

## Current Priorities

- Keep the `codex-memory-v2` tree canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary.
- Keep the runtime/load seam fail-fast on unsupported switch-family life.
- Keep `runtime/session.zig` on explicit world-position seeds.
- Keep `runtime/world_query.zig` as the owner of exact containing-zone queries, raw target-cell evaluation, and raw hero-start diagnostics.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam, including raw-start packaging plus admitted-path local topology and attempt data.
- Keep `app/viewer_shell.zig` as the owner of HUD/stderr copy for admitted-path `ZONES ...` / `TOPO ...` / `SURF ...` and raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`.
- Keep `app/viewer/render.zig` display-only for admitted-path schematic/attempt cues while raw invalid-start stays text-driven.
- Keep fast Windows validation additive: use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` for iteration; bare commands stay canonical.

## Active Streams

- Guarded `19/19` diagnostics: keep runtime-owned zone, admitted target/topology/current-footing, and raw-start coverage/nearest-candidate evidence explicit in HUD/stderr while schematic and attempt cues stay admitted-path-only.
- Fast Windows validation through `zig build test-fast` and `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.
- Memory hygiene: keep canonical pickup on `docs/codex_memory/`, the roadmap, and the live `port/` tree, not `sidequest/` or `LM_TASKS/`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, which are now explicitly rejected from the current parity target.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next guarded `SCENE.HQR[19]` slice on evidence beyond landed zone, target-cell, local-topology/current-footing, raw-start coverage/nearest-candidate, and schematic/attempt cues.
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
