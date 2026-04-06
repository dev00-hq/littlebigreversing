# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- The guarded positive startup path still lands on `raw_invalid_start`, and the current scene metadata for `19` still reports `track_count=0`.
- `life_audit.zig` plus `rank-decoded-interior-candidates` now provide the canonical offline branch-B ranking surface for fully-decoded interior scenes.
- The current checked-in ranking contract is explicit and tested: sort by descending `track_count`, `object_count`, `zone_count`, and `blob_count`, with ascending `scene_entry_index` as the stable tie-breaker.
- On the current asset tree, `rank-decoded-interior-candidates` ranks `50` decoded interior scenes, with `SCENE.HQR[219]` first and `SCENE.HQR[19]` at `49/50`.
- The top-ranked offline candidate is still not a valid guarded room/load pair: `zig build tool -- inspect-room 219 219 --json` currently fails with `InvalidFragmentZoneBounds`.
- `scripts/verify-viewer.ps1` now clears stale `$LASTEXITCODE` after inspected executable calls, so expected-failure probes no longer leak a nonzero script exit after a successful summary.

Next slice:

- Stop widening offline candidate ranking for now and make the new blocker concrete instead: explain why `219/219` fails with `InvalidFragmentZoneBounds`.
- Build one canonical checked-in surface that turns the current raw `InvalidFragmentZoneBounds` failure into actionable evidence. The goal is to identify which fragment-zone bounds or room-state assumptions fail for `219/219`, not to admit the pair at runtime.
- Keep the claim calibrated: this slice is diagnostic and offline only. It must not widen the guarded runtime/load boundary or imply that `219/219` is now supported.
- Treat a negative answer as useful output. If the current checked-in evidence shows that `219/219` is structurally misaligned for reasons that are not safe to paper over, make that explicit and use it to sharpen the next Phase 5 plan instead of inventing progress.

Hard-cut ownership:

- `runtime/room_state.zig`: canonical owner of fragment-zone validation and the `InvalidFragmentZoneBounds` failure
- `background` composition/model code plus tests: canonical owner of fragment data and fragment-zone inputs
- `scene` metadata/model code plus tests: canonical owner of scene-zone inputs
- `tools/cli.zig`: preferred owner for any stable probe/report surface needed to explain the blocker
- `viewer_shell.zig`, `render.zig`, `main.zig`, and locomotion/world-query contracts: unchanged for this slice unless tiny plumbing is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative guarded cases.
- Preserve `rank-decoded-interior-candidates` as the canonical offline ranking surface; do not replace it with another ranking contract.
- Focus on checked-in evidence already present in code and assets: fragment geometry, scene zones, room-state validation, and explicit failure sites.
- No runtime widening, no new supported positive startup pair, no life execution, no movement-policy changes, no scene transitions, and no new unchecked public-runtime path.
- Do not treat docs-only reasoning as enough. The blocker explanation must come from checked-in code, tests, or a canonical CLI/report surface.

Useful work in scope:

- Add a stable probe or diagnostic surface that makes `219/219`'s fragment-zone failure concrete and rerunnable.
- Pin the current winner facts (`219` first, `19` at `49/50`) while showing why the top-ranked candidate still cannot cross the guarded room/load seam.
- If the failure reduces to one or two specific fragment-zone invariants, surface them explicitly.
- If the failure instead proves the current `219/219` pairing is not the next safe slice, make that negative result explicit.

Acceptance:

- One canonical checked-in surface answers the question: why does `inspect-room 219 219 --json` currently fail with `InvalidFragmentZoneBounds`?
- The answer is derived from existing room-state, background, and scene owners, not from ad hoc docs-only reasoning.
- The repo makes it explicit whether the blocker is a fragment-zone data issue, a room-state assumption issue, or another guarded invariant.
- The guarded runtime/viewer boundary and the current startup/load diagnostics remain unchanged.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- rank-decoded-interior-candidates`
  - `zig build tool -- inspect-room 219 219 --json`
  - `# plus the new blocker-explanation surface if this slice adds one`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
