# Current Focus

## Current Priorities

- Keep the `codex-memory-v2` tree canonical.
- Treat `19/19` as the only supported positive runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negatives, with `11/10` evidence/test-only.
- Keep switch-family life outside the supported boundary and fail-fast at the runtime/load seam.
- Keep `runtime/session.zig` on explicit world-position seeds.
- Keep `runtime/world_query.zig` owning exact zones, target evaluation, raw hero-start diagnostics, and target occupied-coverage evidence.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam, including raw-start plus admitted-path topology, footing, attempt, and rejected-target coverage packaging.
- Keep `app/viewer_shell.zig` owning HUD/stderr copy for admitted-path `ZONES ...` / `TOPO ...` / `SURF ...`, rejected-target coverage diagnostics, and raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`.
- Keep `app/viewer/render.zig` display-only for admitted-path schematic/attempt cues while raw invalid-start stays text-driven.
- Keep fast Windows validation additive: `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.

## Active Streams

- Guarded `19/19` diagnostics: keep zone, target/topology/current-footing, rejected-target coverage, and raw-start coverage/nearest-candidate explicit in HUD/stderr while schematic/attempt stay admitted-path-only.
- Fast Windows validation through `zig build test-fast` and `scripts/verify-viewer.ps1 -Fast`; bare commands stay canonical.
- Memory hygiene: keep canonical pickup on `docs/codex_memory/`, the roadmap, and the live `port/` tree, not `sidequest/` or `LM_TASKS/`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and missing checked-in life execution support.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next guarded `19/19` slice on evidence beyond landed zone, target-cell, rejected-target coverage, topology/current-footing, raw-start coverage/nearest-candidate, and schematic/attempt cues.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work on rejection diagnostics, fail-fast coverage for unsupported switch-family opcodes, or a reopened evidence pass only if new checked-in primary-source evidence appears.
- Keep `2/2`, `44/2`, and `11/10` on their current guarded or evidence-only roles unless the runtime boundary widens explicitly.
- Keep canonical memory focused on current-state port work; keep `sidequest/` and `LM_TASKS/` independent until promoted.

## Relevant Subsystem Packs

- architecture
- assets
- backgrounds
- life_scripts
- platform_windows
