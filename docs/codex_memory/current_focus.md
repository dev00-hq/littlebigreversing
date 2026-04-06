# Current Focus

## Current Priorities

- Keep the topology-first `codex-memory-v2` tree canonical.
- Treat `19/19` as the only supported positive branch-B runtime/load baseline.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative load cases, with `11/10` preserved only on explicit evidence or test paths.
- Keep switch-family life outside the supported boundary.
- Keep the runtime/load seam fail-fast on unsupported switch-family scene life.
- Keep `runtime/session.zig` on explicit world-position seeds, not direct `RoomSnapshot` init.
- Keep `runtime/world_query.zig` as the guarded pure query owner, including exact containing-zone membership.
- Keep `runtime/locomotion.zig` as the guarded `19/19` step/result seam while future widening stays diagnostics-only.
- Keep `app/viewer_shell.zig` as the viewer-local zone-summary owner: HUD uses `ZONES ...`, stderr uses `zones=...`, and both derive from the same runtime-owned zone order.
- Keep fast Windows validation additive: use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` for iteration; bare commands stay canonical.

## Active Streams

- Guarded `19/19` viewer/runtime diagnostics: keep runtime-owned containing-zone membership explicit in HUD and stderr on seeded, accepted, and admitted-position rejected statuses only.
- Fast Windows validation through `zig build test-fast` and `scripts/verify-viewer.ps1 -Fast`, with bare commands still canonical.
- Memory hygiene: keep canonical pickup on `docs/codex_memory/`, the roadmap, and the live `port/` tree instead of `sidequest/` or `LM_TASKS/`.

## Blocked Items

- Scene-surface life integration remains blocked on `LM_DEFAULT` and `LM_END_SWITCH`, which are now explicitly rejected from the current parity target.
- Gameplay/runtime widening outside the guarded `19/19` baseline stays blocked on unsupported switch-family life and the lack of checked-in life execution support.
- Canonical Windows checks still depend on the extracted asset tree and SDL2 layout.

## Next Actions

- Keep the next guarded `SCENE.HQR[19]` slice on viewer/runtime evidence or movement-semantic cues beyond landed zone-summary work, not on new movement policy or invented zone heuristics.
- Use `zig build test-fast` plus `scripts/verify-viewer.ps1 -Fast` during iteration, and keep bare `zig build test` plus `scripts/verify-viewer.ps1` as the before-close pass.
- Keep future life work scoped to rejection diagnostics, fail-fast coverage for unsupported switch-family opcodes, or a reopened evidence pass only if new checked-in primary-source evidence appears.
- Keep `2/2`, `44/2`, and `11/10` on their current guarded or evidence-only roles unless the runtime boundary widens explicitly.
- Keep canonical memory focused on current-state port work; treat `sidequest/` and `LM_TASKS/` as independent until deliberately promoted.

## Relevant Subsystem Packs

- architecture
- assets
- scene_decode
- backgrounds
- life_scripts
- platform_windows
