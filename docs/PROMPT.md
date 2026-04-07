# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- The guarded positive startup path still lands on `raw_invalid_start`, and the current scene metadata for `19` still reports `track_count=0`.
- `life_audit.zig` plus `rank-decoded-interior-candidates` are the canonical offline branch-B ranking surface for fully decoded interior scenes.
- The checked-in ranking contract is explicit and tested: sort by descending `track_count`, `object_count`, `zone_count`, and `blob_count`, with ascending `scene_entry_index` as the stable tie-breaker.
- On the current asset tree, `rank-decoded-interior-candidates` ranks `50` decoded interior scenes, with `SCENE.HQR[219]` first and `SCENE.HQR[19]` at `49/50`.
- `inspect-room` and `inspect-room-fragment-zones` already explain the current `219/219` blocker. `inspect-room 219 219 --json` prints `reason=invalid_fragment_zone_bounds` plus six `event=fragment_zone_validation_issue ...` lines before failing with `InvalidFragmentZoneBounds`.
- The current same-index `219/219` issues are all `misaligned_min`: zone `1` `z=4208..5744`, zone `10` `z=5600..6112`, zone `11` `x=20048..20560`, zone `12` `x=22000..22512`, zone `13` `z=7568..8080`, and zone `14` `x=3840..4352`.
- The missing checked-in answer is no longer "why does `219/219` fail?" The missing answer is whether any same-index decoded interior pair that outranks the current `19/19` baseline clears the current fragment-zone admission rules, or whether same-index branch-B candidate selection is presently a dead end under those rules.
- A pair can be fragment-zone compatible because it has no GRM zones at all. The next surface must make `fragment_count` and `grm_zone_count` explicit so a zero-GRM compatible pair is not mistaken for new fragment-bearing room-admission evidence.

Next slice:

- Stop adding more `219/219`-specific diagnostics. Reuse the landed ranking and fragment-zone compatibility surfaces.
- Build one canonical offline triage/report surface in `tools/cli.zig`: `triage-same-index-decoded-interior-candidates`. It should iterate the ranked decoded interior candidates as same-index scene/background pairs and evaluate each pair with the current `runtime/room_state.zig` fragment-zone compatibility rules.
- The primary question is: does any same-index decoded interior candidate outrank the current `19/19` baseline and still clear the current fragment-zone rules?
- The output should make three things explicit:
  1. the current `19/19` baseline rank and compatibility status
  2. the highest-ranked compatible same-index pair overall, if one exists
  3. an explicit `none` result if no compatible same-index pair outranks the current `19/19` baseline
- The output must also surface `fragment_count` and `grm_zone_count` per candidate so "compatible because there are no GRM zones" is visible instead of implicit.
- Reuse `life_audit.zig` for ranking and `runtime/room_state.zig` for fragment-zone compatibility. Do not invent a second ranking contract, duplicate the admission logic, or add another blocker-only CLI for a single hard-coded pair.
- Do not count `19/19` itself as the "next" candidate. It is the comparison baseline, not the replacement answer.
- Keep `inspect-room`, `inspect-room-fragment-zones`, and the guarded runtime/viewer boundary unchanged for this slice.
- Treat a negative answer as useful output. If same-index pairing is currently a dead end above the supported baseline, make that explicit and use it to sharpen the next Phase 5 plan instead of inventing progress.

Hard-cut ownership:

- `life_audit.zig`: canonical owner of offline decoded-interior ranking
- `runtime/room_state.zig`: canonical owner of fragment-zone compatibility and current room-admission rules
- `background` composition/model code plus tests: canonical owner of fragment data and fragment entry indices
- `scene` metadata/model code plus tests: canonical owner of scene-zone inputs
- `tools/cli.zig`: preferred owner for the stable offline triage/report surface
- `viewer_shell.zig`, `render.zig`, `main.zig`, `locomotion.zig`, and `world_query.zig`: unchanged for this slice unless tiny plumbing is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative guarded cases.
- Preserve `rank-decoded-interior-candidates` as the canonical offline ranking surface; do not replace it with another ranking contract.
- Focus on checked-in evidence already present in code and assets: ranking data, fragment geometry, scene zones, room-state validation, and explicit failure sites.
- No runtime widening, no new supported positive startup pair, no life execution, no movement-policy changes, no scene transitions, and no new unchecked public-runtime path.
- Same-index scene/background pairs only for this slice.
- Do not add new 219-only diagnostics or a second one-off explanation command.
- Do not "fix" invalid bounds by normalizing or clamping them in this slice. Surface the evidence instead.
- Do not treat docs-only reasoning as enough. The answer must come from checked-in code, tests, or a canonical CLI/report surface.

Acceptance:

- One canonical checked-in surface answers the question: among ranked decoded interior same-index pairs, is there any compatible candidate that outranks `19/19` under the current fragment-zone rules?
- The answer is derived from existing `life_audit` ranking plus `room_state` compatibility data, not from ad hoc docs-only reasoning.
- The output makes the current baseline comparison explicit, reports the highest-ranked compatible same-index pair overall, separately reports an explicit `none` result if nothing outranks the current baseline, and keeps zero-GRM compatibility visibly distinct from fragment-bearing evidence.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`, and the guarded runtime/viewer boundary plus current startup/load diagnostics remain unchanged.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- rank-decoded-interior-candidates --json`
  - `zig build tool -- triage-same-index-decoded-interior-candidates --json`
  - `zig build tool -- inspect-room-fragment-zones 219 219 --json`
  - `zig build tool -- inspect-room 219 219 --json`  `# expected InvalidFragmentZoneBounds plus fragment-zone diagnostics on stderr`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
