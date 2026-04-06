# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries, exact move-target evaluation, the raw hero-start probe, and diagnostic-only local neighbor topology over immutable guarded room data.
- `runtime/locomotion.zig` owns the guarded `19/19` step/result seam. It already packages raw-start occupied-coverage plus nearest-candidate evidence, and admitted-path target-cell, zone, local-topology, and attempt data.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces raw-start `DIAG ...` / `BOUNDS ...` / `NEAR ...`, plus admitted-path `ZONES ...` and `TOPO ...`, but it still hides admitted-path current footing inside the topology payload instead of surfacing it explicitly.
- `app/viewer/render.zig` already owns the landed admitted-path schematic and attempt cues on the zero-fragment guarded path. Treat those cues as baseline, not next work.
- `main.zig` owns input routing only.
- Raw invalid start and `origin_invalid` rejection still stay separate from the admitted-path movement surface.

Next slice:

- Surface the next diagnostics-only admitted-path evidence on the existing guarded `19/19` path by making current footing explicit from the already-owned `local_topology.origin_surface` plus `origin_standability`.
- Keep this slice viewer-local and text-first: extend admitted-path HUD copy and structured stderr diagnostics with stable `SURF ...` / `current_footing=...` data for `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`, without changing the admitted-path schematic cue.
- Keep raw invalid start and `origin_invalid` rejected-step output separate and lean. Do not imply the runtime admitted the baked invalid path or evaluated alternate movement semantics there.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract on this slice.
- The admitted-path HUD line budget is bounded on this slice. It is acceptable to repurpose the final admitted-path status line for current-footing, and for admitted-position rejected only to fold the rejection reason into the stay-cell line, as long as move-option, zone, topology, schematic, and attempt cues remain intact.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start diagnostics and admitted-path local-topology discovery
- `locomotion.zig`: runtime step/result owner and raw-start/admitted-path evidence packaging only; it must not invent heuristic reinterpretation or viewer-facing copy
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute probes or invent mapping policy
- `render.zig`: display only; keep the admitted-path schematic cue exactly as landed and keep raw-start text-driven on this slice
- `main.zig`: input routing only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep admitted-path target overlays absent on both paths.

Useful work in scope:

- Reuse the existing `local_topology.origin_surface` and `origin_standability` payload already carried on admitted-path statuses; do not add a second footing probe or a new runtime query seam for this slice.
- Have `viewer_shell.zig` format stable admitted-path `SURF ...` HUD copy using only runtime-owned local-topology data.
- Extend admitted-path stderr diagnostics with a structured `current_footing=...` field derived from the same runtime-owned evidence.
- Keep raw invalid-start and `origin_invalid` surfaces unchanged except for tiny consistency edits if tests prove they are necessary.
- Keep admitted-path move-option, zone, topology, schematic, and attempt cues intact; any text-line rebalance must preserve those contracts rather than replace them with viewer-local heuristics.
- Keep render code unchanged unless a test-only adjustment is required to preserve the landed raw-start/no-schematic contract.
- Pin viewer-shell and render tests so the richer admitted-path footing surface cannot drift away from the runtime-owned local-topology data and so raw-start / `origin_invalid` stay on their existing contracts.

Acceptance:

- Runtime locomotion tests stay green and keep current-footing sourced from existing admitted-path local-topology data, with no new runtime seam and no session-mutation regression.
- Viewer-shell tests prove seeded, accepted, and admitted-position rejected HUD and stderr diagnostics surface the extra runtime-owned current-footing evidence, while raw-start and `origin_invalid` keep their landed text/diagnostic contracts.
- Viewer-shell tests also prove admitted-position rejected output may rebalance text lines for footing without losing move-option, zone, topology, or attempt cues.
- Render tests prove the zero-fragment guarded path shows the extra admitted-path footing line on seeded, accepted, and admitted-position rejected traces, while raw-start and `origin_invalid` stay schematic-free and keep their existing text-first contract.
- `world_query.zig` remains the canonical pure move/query surface.
- `locomotion.zig` remains the canonical runtime step/result seam.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
