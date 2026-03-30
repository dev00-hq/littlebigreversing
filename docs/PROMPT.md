# Next Prompt

Then relevant subsystem packs for this task: `architecture`, `backgrounds`, `scene_decode`, and `platform_windows`.

The next step is to replace the remaining synthetic brick-index overlay in the viewer with real `BRK`-backed rendering on the existing viewer-local path. The repo already has real palette-backed `BRK` preview data and helper drawing code, but the viewer still uses synthetic `drawBrickProbe` overlays in places that can be mistaken for final brick output.

Target the current viewer/debug experience for the checked-in positive evidence pair:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing path.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the zero-fragment regression path.

Implement a narrow slice that:

- keeps the current viewer-local composition snapshot, fragment comparison panel, selected-cell detail strip, and deterministic navigation intact
- replaces the remaining synthetic top-surface brick-pattern overlays with real `BRK`-backed preview rendering wherever that viewer path currently presents composition or fragment top surfaces
- preserves the existing height cues, contour cues, focus highlight, and delta signaling
- stays fail-fast if required brick preview data is unexpectedly missing instead of adding silent fallback behavior

Relevant files are likely in:

- `port/src/app/viewer/draw.zig`
- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/fragment_compare.zig`
- `port/src/app/viewer/state.zig`
- `port/src/app/viewer/*_test.zig`

Guardrails:

- Do not add a new room-art layer or a shared handoff abstraction just for this slice.
- Do not treat the existing `BRK` swatches as proof of a complete renderer; keep this scoped to the current debug/viewer surfaces.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior; the viewer/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.

Acceptance:

- `zig build test` passes from `port/`
- `zig build tool -- inspect-room 11 10 --json` still reports the checked-in fragment and `BRK` summary counts
- `zig build run -- --scene-entry 11 --background-entry 10` still launches the viewer with the fragment comparison flow intact
- `zig build run -- --scene-entry 2 --background-entry 2` still shows the explicit zero-fragment state

If you hit the known Windows runtime trap where a prior viewer launch strands `port/zig-out/bin/lba2.exe`, clear the stale `lba2` process and rerun instead of weakening the build/run path.
