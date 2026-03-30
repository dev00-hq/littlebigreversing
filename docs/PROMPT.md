# Next Prompt

Then relevant subsystem packs for this task: `architecture`, `backgrounds`, `scene_decode`, and `platform_windows`.

The next step is to make the landed viewer/debug surface self-describing in the live render path, not to add another fragment-comparison feature or a new room-art layer. The current repo state already has:

- viewer-local composition snapshots
- `BRK`-backed top-surface rendering on composition, fragment, and comparison cards
- the fragment comparison panel
- the selected-cell detail strip
- deterministic ranked-entry and fragment-cell navigation
- the pinned selected-cell row
- deterministic render-level regression coverage for the `11/10` fragment path, the `2/2` zero-fragment path, and missing-preview failures

Build the next slice on that existing path instead of introducing a shared UI framework, an external text dependency, or another prompt that mostly repeats render-test coverage.

Target the current viewer/debug experience for the checked-in evidence pairs:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing path and the source of truth for the comparison-state HUD.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the explicit zero-fragment regression path and should stay visibly self-describing instead of relying on the absence of the comparison panel.

Implement a narrow slice that:

- keeps the current viewer-local composition snapshot, `BRK`-backed top-surface rendering, comparison panel, detail strip, navigation, pinned selection behavior, and render-path regression coverage intact
- adds a viewer-local HUD / legend surface inside the SDL render path so screenshots and live runs explain what room is loaded, what the key overlays mean, and how fragment navigation is being interpreted without depending on the window title alone
- surfaces room metadata that matters for debugging, such as scene/background entry pairing, classic loader scene number when present, and fragment-state summary for the currently loaded pair
- surfaces the current fragment focus when the `11/10` comparison panel is active, including enough on-canvas context to tell which selected cell is being inspected and whether it is a changed / exact / no-base comparison result
- surfaces an explicit stable zero-fragment message/state for `2/2` rather than leaving users to infer it from a missing panel
- prefers a small built-in viewer-local text/label solution or similarly deterministic HUD chrome over adding SDL_ttf, external font assets, or a generic retained-mode UI layer
- adds real render-path assertions around the new HUD / legend behavior instead of treating the window title or `inspect-room --json` output as the source of truth for what the viewer communicates

Relevant files are likely in:

- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/app/viewer/draw.zig`
- `port/src/app/viewer/draw_test.zig`
- `port/src/app/viewer/fragment_compare.zig`
- `port/src/app/viewer/layout.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/main.zig`
- `port/src/platform/sdl.zig`

Guardrails:

- Do not add a new room-art layer, shared handoff abstraction, or generic UI system just for this slice.
- Do not re-implement fragment comparison behavior that already landed; use the current panel/detail/navigation path as the starting point.
- Do not add SDL_ttf, external font files, or another runtime dependency just to draw labels.
- Do not make the window title or stderr startup dump the only self-describing surface; the live render path should own the screenshot/debug experience.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior or current selection state; the viewer/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.
- Keep the checked-in zero-fragment control as `2/2`, and make that zero-state explicit rather than inferred.
- Stay fail-fast if required `BRK` preview data or any newly required HUD data is unexpectedly missing instead of adding silent fallback behavior.

Acceptance:

- `zig build test` passes from `port/`
- `zig build tool -- inspect-room 11 10 --json` still reports the checked-in fragment and `BRK` summary counts
- `zig build tool -- inspect-room 2 2 --json` still reports the explicit zero-fragment boundary
- `zig build run -- --scene-entry 11 --background-entry 10` still launches the viewer with the fragment comparison flow intact and the new self-describing HUD visible on the live render path
- `zig build run -- --scene-entry 2 --background-entry 2` still launches the viewer with the explicit zero-fragment state visible on the live render path
- the new coverage exercises the actual viewer render path rather than only lower-level layout or title-format helpers

If you hit the known Windows runtime trap where a prior viewer launch strands `port/zig-out/bin/lba2.exe`, clear the stale `lba2` process and rerun instead of weakening the build/run path.
