# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` remains the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- The guarded positive startup path still lands on `raw_invalid_start`, and the current scene metadata for `19` still reports `track_count=0`.
- `life_audit.zig` plus `rank-decoded-interior-candidates` are the canonical offline branch-B ranking surface for fully decoded interior scenes.
- The checked-in ranking contract is explicit and tested: sort by descending `track_count`, `object_count`, `zone_count`, and `blob_count`, with ascending `scene_entry_index` as the stable tie-breaker.
- On the current asset tree, `rank-decoded-interior-candidates` ranks `50` decoded interior scenes, with `SCENE.HQR[219]` first and `SCENE.HQR[19]` at `49/50`.
- `room_state.inspectRoomFragmentZoneDiagnostics` already owns fragment-zone admission rules, and `inspect-room-fragment-zones` already exposes the blocker surface for specific same-index pairs.
- `inspect-room 219 219 --json` already prints `reason=invalid_fragment_zone_bounds` plus six per-zone issue lines before failing with `InvalidFragmentZoneBounds`; do not add more `219/219`-specific diagnostics in this slice.
- The remaining question is not why `219/219` fails. The remaining question is which ranked same-index decoded interior pair is next after excluding the currently blocked ones under the checked-in fragment-zone rules.

Next slice:

- Build one canonical offline surface, preferably in `tools/cli.zig`, that evaluates ranked decoded interior candidates against the current room-state fragment-zone admission rules for same-index scene/background pairs.
- The goal is not runtime widening. The goal is to surface the highest-ranked same-index pair that clears current fragment-zone bounds, or make it explicit that no current same-index decoded candidate does.
- Reuse `life_audit.zig` for ranking and `runtime/room_state.zig` for fragment-zone compatibility. Do not invent a second ranking contract or duplicate the admission logic in viewer or docs code.
- Keep `inspect-room` and the guarded runtime/viewer boundary unchanged for this slice.
- Treat a negative answer as useful output. If same-index pairing is currently a dead end under the checked-in fragment-zone rules, make that explicit and use it to sharpen the next Phase 5 plan instead of inventing progress.

Hard-cut ownership:

- `life_audit.zig`: canonical owner of offline decoded-interior ranking
- `runtime/room_state.zig`: canonical owner of fragment-zone compatibility and current room-admission rules
- `background` composition/model code plus tests: canonical owner of fragment data and fragment entry indices
- `scene` metadata/model code plus tests: canonical owner of scene-zone inputs
- `tools/cli.zig`: preferred owner for the stable offline triage/report surface
- `viewer_shell.zig`, `render.zig`, `main.zig`, and locomotion/world-query contracts: unchanged for this slice unless tiny plumbing is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative guarded cases.
- Preserve `rank-decoded-interior-candidates` as the canonical offline ranking surface; do not replace it with another ranking contract.
- Focus on checked-in evidence already present in code and assets: ranking data, fragment geometry, scene zones, room-state validation, and explicit failure sites.
- No runtime widening, no new supported positive startup pair, no life execution, no movement-policy changes, no scene transitions, and no new unchecked public-runtime path.
- Same-index scene/background pairs only for this slice.
- Do not "fix" invalid bounds by normalizing or clamping them in this slice. Surface the evidence instead.
- Do not treat docs-only reasoning as enough. The blocker explanation must come from checked-in code, tests, or a canonical CLI/report surface.

Acceptance:

- One canonical checked-in surface answers the question: among ranked decoded interior same-index pairs, which candidate is next after excluding the currently blocked ones under checked-in fragment-zone rules?
- The answer is derived from existing `life_audit` ranking plus `room_state` compatibility data, not from ad hoc docs-only reasoning.
- The output makes `219/219`'s current failure category explicit and surfaces the next viable same-index candidate or an explicit `none` result.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`, and the guarded runtime/viewer boundary plus current startup/load diagnostics remain unchanged.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- rank-decoded-interior-candidates --json`
  - `zig build tool -- <new same-index triage/report surface> --json`
  - `zig build tool -- inspect-room-fragment-zones 219 219 --json`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
