# Next Prompt

Then relevant subsystem packs for this task: `architecture`, `backgrounds`, `scene_decode`, and `platform_windows`.

The next step is to add deterministic render-level regression coverage for the landed viewer-local `BRK`-backed fragment comparison flow, not to re-implement comparison behavior that already exists. The current repo state already has:

- viewer-local composition snapshots
- `BRK`-backed top-surface rendering on composition, fragment, and comparison cards
- the fragment comparison panel
- the selected-cell detail strip
- deterministic ranked-entry and fragment-cell navigation
- the pinned selected-cell row

Build the next slice on that existing path instead of introducing a new room-art layer, a shared handoff abstraction, or another prompt that mostly repeats `fragment_compare` model coverage.

Target the current viewer/debug experience for the checked-in evidence pairs:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing path and the source of truth for comparison-surface render coverage.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the explicit zero-fragment regression path.

Implement a narrow slice that:

- keeps the current viewer-local composition snapshot, `BRK`-backed top-surface rendering, comparison panel, detail strip, navigation, and pinned selection behavior intact
- adds real viewer render-path assertions around `renderDebugView` / `renderDebugViewWithSelection` instead of only adding more catalog bookkeeping tests
- pins the `11/10` render path so the comparison panel is present, the focused fragment cell stays inspectable through the live render path, and the selected cell remains pinned at the head of the panel
- pins the `2/2` render path so the zero-fragment state stays stable and does not accidentally show the comparison panel
- preferably strengthens fail-fast coverage through the actual comparison-card/render path when required `BRK` preview data is missing, rather than only through lower-level lookup helpers
- treats `inspect-room --json` as a probe-level sanity check for fragment counts and `BRK` summary counts, not as the source of truth for per-cell comparison behavior

Relevant files are likely in:

- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/app/viewer/fragment_compare.zig`
- `port/src/app/viewer/fragment_compare_test.zig`
- `port/src/app/viewer/draw.zig`
- `port/src/app/viewer/draw_test.zig`
- `port/src/app/viewer/state_test.zig`
- `port/src/app/viewer_shell.zig`
- `port/src/main.zig`

Guardrails:

- Do not add a new room-art layer or a shared handoff abstraction just for this slice.
- Do not restate already-landed comparison behavior as if it were still missing; use the existing panel/detail/navigation surfaces as the starting point.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior; the viewer/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.
- Stay fail-fast if required `BRK` preview data is unexpectedly missing instead of adding silent fallback behavior.

Acceptance:

- `zig build test` passes from `port/`
- `zig build tool -- inspect-room 11 10 --json` still reports the checked-in fragment and `BRK` summary counts
- `zig build tool -- inspect-room 2 2 --json` still reports the explicit zero-fragment boundary
- `zig build run -- --scene-entry 11 --background-entry 10` still launches the viewer with the fragment comparison flow intact
- `zig build run -- --scene-entry 2 --background-entry 2` still shows the explicit zero-fragment state
- the new coverage exercises the actual viewer render path rather than only duplicating existing `fragment_compare` ordering logic

If you hit the known Windows runtime trap where a prior viewer launch strands `port/zig-out/bin/lba2.exe`, clear the stale `lba2` process and rerun instead of weakening the build/run path.
