# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, and `platform_windows`.
Load `scene_decode` only if you need to cross-check the checked-in evidence pairs or scene metadata while implementing the focused-zone overlay.

The previous landing / verification slice is complete. The viewer-local HUD / legend, selected-cell provenance text, and native PowerShell verification path are already landed. The next step is one narrow viewer-local evidence cue on top of that existing runtime path: make the owning fragment zone visually obvious on the schematic when the checked-in `11/10` fragment cell is focused.

The current repo state already has:

- viewer-local composition snapshots
- `BRK`-backed top-surface rendering on composition, fragment, and comparison cards
- the fragment comparison panel, selected-cell detail strip, deterministic navigation, and pinned selected-cell row
- viewer-local HUD / legend chrome that surfaces room metadata, focus state, comparison ordering, navigation semantics, explicit `2/2` zero-fragment messaging, and now selected-cell zone provenance / stack-depth evidence
- deterministic render-path regression coverage for the `11/10` fragment path, the `2/2` zero-fragment path, and missing-preview failures
- a canonical Windows verification gate in `scripts/verify-viewer.ps1`

Target the checked-in evidence pairs:

- `SCENE.HQR[11]` with `LBA_BKG.HQR[10]` is the fragment-bearing runtime path.
- `SCENE.HQR[2]` with `LBA_BKG.HQR[2]` is the explicit zero-fragment control path.

Implement a narrow viewer-local refinement slice that:

- adds a distinct overlay on the schematic for the owning fragment-zone footprint when the viewer has a focused fragment cell on `11/10`, and makes that overlay visually distinct from the existing fragment-zone border and focused-cell marker
- keeps that overlay viewer-local and driven directly from the focused `FragmentComparisonEntry` plus the existing render snapshot / schematic projection path instead of inventing a new handoff layer or metadata path
- preserves the current composition rendering, `BRK` preview surfaces, comparison panel, selected-cell detail strip, deterministic navigation, pinned selection behavior, HUD / legend text, and fail-fast preview handling unless a concrete bug is found while implementing the overlay
- keeps `2/2` explicitly zero-fragment: no synthetic focus state, no comparison panel, and no fragment-zone overlay when no fragment focus exists
- keeps probe commands (`inspect-room`) as cross-checks for counts and linkage, not as the source of truth for per-cell viewer state
- reruns the canonical Windows verification gate before landing, using `pwsh -File scripts/verify-viewer.ps1`
- updates memory only if the active repo status changes after the slice lands, and only in the canonical v2 locations
- adds an `ISSUES.md` note only if the work uncovers a new recurring trap

Relevant files are likely in:

- `port/src/app/viewer/render.zig`
- `port/src/app/viewer/render_test.zig`
- `port/src/app/viewer/fragment_compare.zig`
- `port/src/app/viewer/layout.zig`
- `port/src/app/viewer/state.zig`
- `port/src/app/viewer/fragment_compare_test.zig`
- `port/src/app/viewer/state_test.zig`
- `scripts/verify-viewer.ps1`
- `docs/codex_memory/task_events.jsonl`
- `docs/codex_memory/current_focus.md`
- `docs/codex_memory/subsystems/backgrounds.md`
- `ISSUES.md`

Guardrails:

- Do not widen this into another comparison panel redesign, a generalized scene-zone labeling system, or a fuller room-art renderer.
- Do not widen a viewer-local refinement into gameplay, life binding, exterior loading, a shared UI / room layer, or another repo-wide cleanup pass.
- Do not use `inspect-room --json` as the source of truth for per-cell comparison behavior or current selection state. The viewer runtime/tests own that surface.
- Keep the checked-in positive pair as `11/10`; do not collapse it into a same-index assumption.
- Keep the checked-in zero-fragment control as `2/2`.
- Stay fail-fast if required `BRK` preview data or viewer metadata is unexpectedly missing instead of adding silent fallback behavior.
- Keep the overlay readable as provenance evidence. It should not replace or obscure the existing selected-cell cue, the baseline fragment-zone border, or the `BRK`-backed surfaces.

Acceptance:

- `11/10` shows a distinct owning-zone provenance overlay on the focused cell's owning fragment-zone rect on the live schematic
- `2/2` remains explicitly zero-fragment and does not render a fragment-zone overlay
- render-path regression coverage asserts a deterministic trace op on the focused zone's projected rect for `11/10`, and asserts that no focused-zone overlay trace op appears on `2/2`
- `pwsh -File scripts/verify-viewer.ps1` passes after the change
- any typed history update stays within `codex-memory-v2` conventions
- if the repo already contains the exact overlay behavior described above, land the slice as a no-op review instead of inventing another feature
