# Next Prompt

Then relevant subsystem packs for this task: `architecture`, `backgrounds`, `scene_decode`, and `platform_windows`.

The next step is to refine and verify the landed viewer-local `BRK`-backed fragment comparison path, not to replace synthetic brick overlays from scratch. The current repo state already routes composition tops, fragment cells, and comparison cards through decoded `BRK` previews on the existing viewer-local composition snapshot; build the next slice on that path instead of introducing a new room-art layer or a shared handoff abstraction.

Target the current viewer/debug experience for the checked-in evidence pairs:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing path and the source of truth for comparison-surface refinement.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the explicit zero-fragment regression path.

Implement a narrow slice that:

- keeps the current viewer-local composition snapshot, `BRK`-backed top-surface rendering, fragment comparison panel, selected-cell detail strip, and deterministic navigation intact
- adds one more viewer-local refinement to the `11/10` comparison experience or strengthens its regression coverage, with preference for work centered in the comparison surface rather than new rendering layers
- preserves the existing height cues, contour cues, focus highlight, delta signaling, and fail-fast `BRK` preview requirements
- treats `inspect-room --json` as a probe-level sanity check for fragment counts and `BRK` summary counts, not as the source of truth for per-cell comparison behavior

Relevant files are likely in:

- `port/src/app/viewer/fragment_compare.zig`
- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/draw.zig`
- `port/src/app/viewer/state.zig`
- `port/src/app/viewer/fragment_compare_test.zig`
- `port/src/app/viewer/state_test.zig`

Guardrails:

- Do not add a new room-art layer or a shared handoff abstraction just for this slice.
- Do not treat the existing `BRK` swatches as proof of a complete renderer; keep this scoped to the current debug/viewer surfaces.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior; the viewer/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.
- Stay fail-fast if required `BRK` preview data is unexpectedly missing instead of adding silent fallback behavior.

Acceptance:

- `zig build test` passes from `port/`
- `zig build tool -- inspect-room 11 10 --json` still reports the checked-in fragment and `BRK` summary counts
- `zig build run -- --scene-entry 11 --background-entry 10` still launches the viewer with the fragment comparison flow intact
- `zig build run -- --scene-entry 2 --background-entry 2` still shows the explicit zero-fragment state
- Any new comparison-surface behavior is pinned in viewer tests rather than left runtime-only

If you hit the known Windows runtime trap where a prior viewer launch strands `port/zig-out/bin/lba2.exe`, clear the stale `lba2` process and rerun instead of weakening the build/run path.
