# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `backgrounds`, `life_scripts`, and `platform_windows`.

Current state:

- `19/19` is the only supported positive branch-B runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded `ViewerUnsupportedSceneLife` negatives.
- `LM_DEFAULT` and `LM_END_SWITCH` stay outside the supported decoder/interpreter boundary.
- `runtime/world_query.zig` owns exact containing-zone queries, exact move-target evaluation, the raw hero-start probe, nearest occupied/standable diagnostic candidates, and the discovery-only hero-start mapping comparison helpers.
- `runtime/locomotion.zig` owns step/result policy and the guarded `19/19` seam. It already threads runtime-owned zone membership, target-cell evidence, and local admitted-cell topology through `seeded_valid`, `last_move_accepted`, and admitted-position `last_move_rejected`, but its `raw_invalid_start` payload still drops `diagnostic_status` plus nearest-candidate evidence from the raw hero-start probe.
- `runtime/session.zig` owns mutable hero world position only.
- `runtime/room_state.zig` owns the guarded room/load seam plus immutable room/render snapshots.
- `app/viewer_shell.zig` owns formatting, stderr diagnostics, and explicit fixture seeding only. It already surfaces admitted-path move-option and zone-summary evidence, but its raw invalid-start copy still stops at mapped cell plus occupied-coverage summary.
- `app/viewer/render.zig` already owns the landed admitted-path schematic cue on the zero-fragment guarded path, including accepted/rejected attempt segments where present. Treat those cues as baseline, not next work.
- `main.zig` owns input routing only.
- Raw invalid start and `origin_invalid` rejection still stay separate from the admitted-path movement surface.

Next slice:

- Surface the next diagnostics-only movement-semantic evidence on the existing guarded `19/19` raw invalid-start path.
- Use only the already-landed runtime-owned raw hero-start probe evidence: `diagnostic_status`, `nearest_occupied`, `nearest_standable`, and their existing cell/distance facts.
- Keep this slice text-first: extend raw invalid-start HUD copy and structured stderr diagnostics to expose that evidence clearly without changing the admitted-path schematic cue.
- Keep `origin_invalid` rejected-step output separate and lean. Do not imply the runtime admitted the baked invalid path or evaluated alternate movement semantics there.
- Keep `evaluateHeroStartMappings()` and `investigateAdditionalEvidenceAnchor()` discovery-only. Do not promote mapping-hypothesis narratives, alternate coordinate policies, or extra-anchor scoring into the runtime/viewer contract on this slice.

Hard-cut ownership:

- `world_query.zig`: pure guarded room query/evaluation owner, including raw hero-start probe and nearest-candidate discovery
- `locomotion.zig`: runtime step/result owner and raw-start evidence packaging only; it must not invent heuristic reinterpretation or viewer-facing copy
- `session.zig`: mutable state only
- `room_state.zig`: guarded load seam only
- `viewer_shell.zig`: formatting, diagnostics, explicit fixture seeding, and packaging render-facing display data from already-owned runtime results only; it must not recompute probes or invent mapping policy
- `render.zig`: display only; keep the admitted-path schematic cue exactly as landed and keep raw-start evidence text-driven on this slice
- `main.zig`: input routing only

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases.
- Keep future work diagnostics-only unless new primary-source evidence justifies widening the boundary.
- No new movement rules, no new zone heuristics, no viewer-side move evaluation, no alternate mapping policy, no scene transitions, no life execution, no object AI, no inventory/state systems, no combat, no track execution, no new input-repeat system, no auto-seeding, and no unchecked room path in the public runtime seam.
- Keep raw invalid start and `origin_invalid` rejection separate, and keep admitted-path target overlays absent on both paths.

Useful work in scope:

- Extend `runtime/locomotion.RawInvalidStartStatus` or an equivalent runtime-owned payload so raw invalid-start status preserves `diagnostic_status` plus the minimal nearest-candidate facts the viewer needs.
- If a helper snapshot type is needed, keep it runtime-owned and minimal: candidate kind, cell, and distance facts only.
- Have `viewer_shell.zig` format stable raw invalid-start HUD lines for `diagnostic_status`, nearest occupied candidate, and nearest standable candidate, using only runtime-owned data.
- Extend raw invalid-start stderr diagnostics with explicit fields derived from the same runtime-owned evidence.
- Keep seeded, accepted, and admitted-position rejected status surfaces unchanged except for tiny consistency edits if tests prove they are necessary. Their admitted-path topology and attempt cues are baseline, not next work.
- Keep render code unchanged unless a test-only adjustment is required to preserve the landed raw-start/no-schematic contract.
- Pin viewer-shell and render tests so the raw invalid-start surface cannot drift away from the runtime-owned probe data and so `origin_invalid` stays schematic-free.

Acceptance:

- Runtime world-query tests stay green and continue proving the raw hero-start probe separates exact invalid mapping evidence from nearest candidate evidence on the guarded `19/19` snapshot.
- Runtime locomotion tests prove raw invalid-start status preserves packaged `diagnostic_status` plus nearest-candidate evidence without mutating session state.
- Viewer-shell tests prove the raw invalid-start HUD and stderr diagnostics surface the extra runtime-owned evidence, while seeded, accepted, and admitted-position rejected displays keep the landed move-option and zone-summary contract.
- Viewer-shell tests also prove `origin_invalid` rejection stays separate from the richer raw invalid-start text path and remains schematic-free.
- Render tests prove the zero-fragment guarded path still shows no admitted-path schematic cue on raw invalid start and `origin_invalid` rejection, while the seeded, accepted, and admitted-position rejected admitted-path schematic cues stay exactly as landed.
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
