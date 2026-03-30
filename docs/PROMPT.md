# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.
Load `scene_decode` only if the runtime verification exposes a scene-metadata mismatch.

The viewer-local HUD / legend slice from the previous prompt is already landed. The next step is not another viewer feature pass. The next step is a Windows-native end-to-end verification and fixup pass for the live viewer path that now exists.

The current repo state already has:

- viewer-local composition snapshots
- `BRK`-backed top-surface rendering on composition, fragment, and comparison cards
- the fragment comparison panel, selected-cell detail strip, deterministic navigation, and pinned selected-cell row
- viewer-local HUD / legend chrome that surfaces room metadata, focus state, comparison ordering, navigation semantics, and explicit `2/2` zero-fragment messaging
- deterministic render-path regression coverage for the `11/10` fragment path, the `2/2` zero-fragment path, and missing-preview failures

Use the next run to validate that landed behavior through the canonical Windows runtime path and fix only concrete mismatches that show up there.

Target the checked-in evidence pairs:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing runtime path.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the explicit zero-fragment control path.

Implement a narrow validation/fixup slice that:

- runs the canonical checks from native PowerShell, not `bash -lc`, and loads `.\scripts\dev-shell.ps1` from the repo root before validating inside `port/`
- treats `zig build run -- --scene-entry 11 --background-entry 10` and `zig build run -- --scene-entry 2 --background-entry 2` as first-class acceptance commands, not optional smoke checks
- preserves the current viewer-local composition, `BRK` preview rendering, comparison panel, detail strip, navigation, pinned selection behavior, HUD / legend surfaces, and render-path tests unless the executable path proves something is wrong
- fixes runtime-only discrepancies in the smallest canonical place if the live executable disagrees with the landed render tests or with the intended `11/10` / `2/2` viewer behavior
- adds or adjusts regression coverage only to lock in a real bug found during that verification pass
- keeps probe commands (`inspect-room`) as cross-checks for counts and linkage, not as the source of truth for per-cell viewer state
- clears any stale `lba2.exe` process if the known Windows lock trap blocks `zig build run`, then reruns instead of weakening the runtime path

Relevant files are likely in:

- `scripts/dev-shell.ps1`
- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/app/viewer/layout.zig`
- `port/src/app/viewer/state.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/main.zig`
- `port/src/platform/sdl.zig`

Guardrails:

- Do not spend this slice adding another viewer feature, another comparison refinement, or a fuller room-art renderer if the runtime path already matches the landed tests.
- Do not replace native PowerShell verification with `bash -lc` wrappers for canonical build/run commands.
- Do not widen into gameplay, life binding, exterior loading, or a shared UI / room layer as part of this pass.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior or current selection state; the viewer runtime/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.
- Keep the checked-in zero-fragment control as `2/2`.
- Stay fail-fast if required `BRK` preview data or viewer metadata is unexpectedly missing instead of adding silent fallback behavior.

Acceptance:

- from the repo root, `.\scripts\dev-shell.ps1` runs before validation
- from `port/`, `zig build test` passes
- from `port/`, `zig build tool -- inspect-room 11 10 --json` still reports the checked-in fragment and `BRK` summary counts
- from `port/`, `zig build tool -- inspect-room 2 2 --json` still reports the explicit zero-fragment boundary
- from `port/`, `zig build run -- --scene-entry 11 --background-entry 10` launches the viewer with the landed fragment comparison flow and HUD / legend visible on the live render path
- from `port/`, `zig build run -- --scene-entry 2 --background-entry 2` launches the viewer with the landed explicit zero-fragment state and HUD / legend visible on the live render path
- if the executable path matches the landed tests and intended behavior, do not add a new viewer feature just to keep the slice busy
