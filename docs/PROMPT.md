# Next Prompt

Relevant subsystem packs for this task: `architecture`, `life_scripts`, `backgrounds`, `scene_decode`, and `platform_windows`.

The previous Phase 5 entry slice is only partially coherent in the checked-in repo state:

- `listDecodedInteriorSceneCandidates` does prove there are `50` fully-decoded interior candidates, and `SCENE.HQR[19]` is the earliest one (`classic_loader_scene_number = 17`, `blob_count = 3`).
- The guarded viewer/runtime seam in `loadRoomSnapshot` does reject unsupported scene life, so the supported positive guarded baseline is `19/19`.
- `2/2` and `44/2` are guarded negative unsupported-scene-life cases on that viewer/runtime seam.
- `11/10` is still useful checked-in fragment evidence, but only on explicit evidence or test-only unchecked paths.

But the repo still has an incoherent second story:

- `inspect-room` in `port/src/tools/cli.zig` still uses an unguarded room inspection path.
- `inspect-room 2 2 --json` still succeeds even though `2/2` is no longer inside the supported guarded runtime/load boundary.
- CLI tests and `scripts/verify-viewer.ps1` still preserve older `2/2` and `11/10` positive fixture language that no longer matches the guarded product boundary.
- There is no direct guarded negative regression for `loadRoomSnapshot(11, 10)`, so the evidence-only boundary for scene `11` is under-protected.

The next slice is to resolve that boundary drift, not to widen gameplay again yet.

Implement a bounded coherence pass that:

- makes the canonical room-inspection/runtime story match the guarded branch-B boundary
- removes or rewrites stale positive-fixture language that still treats `2/2` or `11/10` as canonical supported runtime loads
- adds an explicit guarded negative regression for `11/10`
- keeps `19/19` as the only supported positive guarded runtime/load baseline
- keeps `2/2`, `44/2`, and `11/10` outside the guarded positive runtime boundary
- keeps `LM_DEFAULT` and `LM_END_SWITCH` unsupported

Default to the hard-cut current-state path:

- route `inspect-room` through the same guarded scene-life seam as `loadRoomSnapshot` instead of preserving a second implicit room-loading behavior
- if a raw evidence-only room probe is still genuinely needed after that change, do not keep it hidden behind the canonical `inspect-room` name; either prove it is unnecessary or introduce it only with explicit naming, explicit scope, and fail-fast semantics

Use the current checked-in state as the product boundary:

- `19/19` is the only supported positive guarded runtime/load pair
- `2/2` and `44/2` are negative guarded unsupported-scene-life cases
- `11/10` is fragment evidence only and must not become a guarded positive runtime fixture
- candidate rediscovery is already complete; do not spend the slice re-running the Phase 5 entry decision

Relevant files are likely in:

- `port/src/app/viewer/state.zig`
- `port/src/app/viewer/state_test.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/app/viewer/fragment_compare_test.zig`
- `port/src/app/viewer_shell_test.zig`
- `port/src/tools/cli.zig`
- `scripts/verify-viewer.ps1`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/architecture.md`
- `docs/codex_memory/subsystems/life_scripts.md`
- `docs/codex_memory/task_events.jsonl`
- `ISSUES.md`

Guardrails:

- Do not reopen the Phase 4 branch decision.
- Do not add support for `LM_DEFAULT`, `LM_END_SWITCH`, or partial switch-family handling.
- Do not add compatibility glue, silent fallbacks, or a second implicit room-loading path.
- Do not reintroduce `2/2` or `11/10` as positive guarded runtime fixtures.
- Do not spend the slice on new gameplay capability or viewer-only polish.
- Keep evidence-only access explicit if it survives at all; do not leave it disguised as the canonical guarded room path.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `zig build tool -- audit-life-programs --json --scene-entry 19`
  - `zig build tool -- audit-life-programs --json --scene-entry 11`
  - `zig build tool -- inspect-scene 19 --json`
  - `zig build tool -- inspect-room 19 19 --json`
  - `zig build tool -- inspect-room 2 2 --json`
  - `zig build tool -- inspect-room 11 10 --json`
- checked-in tests keep `19/19` as the positive guarded runtime baseline
- checked-in tests keep `2/2`, `44/2`, and `11/10` as guarded negative unsupported-scene-life cases where the guarded seam is exercised
- if `inspect-room` remains the canonical room inspection command, it must now fail for unsupported guarded scenes instead of silently succeeding
- if an evidence-only room probe survives, its naming/tests/docs must make that status explicit and must not describe it as the supported runtime/load boundary
