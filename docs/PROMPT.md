# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

The previous docs/product-boundary coherence slice is effectively complete in the current worktree:

- `docs/LBA2_ZIG_PORT_PLAN.md` now describes `19/19` as the only positive guarded runtime/load baseline and keeps `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- `port/README.md` now distinguishes the guarded `19/19` path from the explicit test-only unchecked `11/10` evidence path.
- `docs/codex_memory/current_focus.md`, `docs/codex_memory/subsystems/architecture.md`, `docs/codex_memory/subsystems/backgrounds.md`, and `docs/codex_memory/subsystems/life_scripts.md` already align with that branch-B boundary.
- `port/src/app/viewer/state.zig`, `port/src/app/viewer/state_test.zig`, and `scripts/verify-viewer.ps1` already enforce the same guarded runtime/load seam.

But the code still has an ownership gap that risks reintroducing dual behavior:

- The guarded room/load types and loaders still live under `port/src/app/viewer/state.zig` even though the stable module plan says this ownership belongs in `runtime`.
- `port/src/root.zig` still has no `runtime` module export.
- `port/src/app/viewer_shell.zig` is re-exporting room/runtime state types from the viewer layer instead of consuming a canonical runtime surface.
- `port/src/tools/cli.zig` currently stays on the guarded room/load seam by calling the viewer-owned loader; keep that seam intact during extraction and do not introduce a metadata-only inspection bypass while moving ownership.

The next slice is a bounded runtime-ownership extraction, not more docs churn.

Implement a current-state runtime extraction that:

- creates a canonical `port/src/runtime/` room-state module that owns guarded scene/background loading, room snapshots, and render-snapshot construction
- moves shared room/runtime data ownership out of `port/src/app/viewer/state.zig`
- keeps `inspect-room`, the viewer runtime, and their tests on the same guarded runtime/load seam with no metadata-only bypass
- updates `port/src/app/viewer_shell.zig` and `port/src/tools/cli.zig` to consume runtime-owned room-state APIs instead of viewer-owned room-state exports
- keeps `port/src/app/viewer/state.zig` limited to viewer-local state and rendering support instead of acting as the public owner of guarded room loading
- keeps `19/19` as the only positive guarded runtime/load pair
- keeps `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases
- keeps `11/10` available only on the explicit test-only unchecked evidence path
- updates `port/src/root.zig` so the canonical module map reflects the new runtime ownership instead of leaving room-state under `app/viewer`
- leaves viewer-local layout, draw, fragment-comparison, and HUD code under `port/src/app/viewer/`

Default to the hard-cut current-state path:

- do not preserve both a viewer-owned room loader and a runtime-owned room loader
- do not introduce or keep any CLI-only `loadRoomInspection` / metadata-only room path
- do not widen gameplay, life execution, or exterior loading as part of this slice
- do not reopen the Phase 4 branch-B decision for `LM_DEFAULT` or `LM_END_SWITCH`
- if you discover another recurring trap while doing the extraction, update `ISSUES.md` and keep the architecture subsystem pack aligned

Relevant files are likely in:

- `port/src/runtime/`
- `port/src/root.zig`
- `port/src/app/viewer/state.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/main.zig`
- `port/src/tools/cli.zig`
- `port/src/app/viewer/state_test.zig`
- `port/src/app/viewer/render_test.zig`
- `scripts/verify-viewer.ps1`
- `ISSUES.md`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Do not leave `inspect-room` on a looser boundary than the viewer runtime.
- Make the ownership move visible in the import graph, not just in file placement or re-export shims.
- Do not preserve stale `2/2` positive-fixture assumptions in tests while extracting ownership.
- Do not turn this into a broad renderer refactor; the target is ownership and boundary coherence.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/root.zig` exposes a canonical `runtime` module
- `port/src/app/viewer_shell.zig` and `port/src/tools/cli.zig` consume runtime-owned room-state APIs instead of viewer-owned room-state exports
- `port/src/app/viewer/state.zig` no longer owns or publicly exports the guarded room loader used by the viewer runtime and `inspect-room`
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no metadata-only room inspection path exists in the canonical code
- any unchecked `11/10` path remains explicit test-only evidence coverage, not part of the runtime public surface
