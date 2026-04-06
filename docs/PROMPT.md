# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- `rank-decoded-interior-candidates` is now the canonical offline report for fully-decoded interior branch-B candidates. It orders the `50` decoded interior scenes by `track_count`, `object_count`, `zone_count`, `blob_count`, then `scene_entry_index`.
- The current ranking result is explicit: `SCENE.HQR[219]` is the top offline candidate with `blob_count=34`, `object_count=34`, `zone_count=16`, `track_count=17`, and `patch_count=42`; the guarded `SCENE.HQR[19]` baseline ranks `49/50`.
- `inspect-scene 219 --json` confirms that the top-ranked candidate is structurally much richer than `19`, with real track data and a large scene/object payload.
- The next blocker is not life decoding or candidate selection. It is room/load viability: `inspect-room 219 219 --json` currently fails with `InvalidFragmentZoneBounds` inside `runtime/room_state.zig` while fragment-zone snapshots are being projected.
- Keep the claim calibrated: `219` is the best current offline candidate under the checked-in richness policy, not a newly admitted runtime scene.
- The current supported `19/19` startup is still diagnostic-only rather than gameplay-ready: the guarded viewer launch lands on `raw_invalid_start`, and the current scene metadata reports `track_count=0`.

Next slice:

- Stop revisiting candidate ranking for now. Make the new Phase 5 blocker concrete instead: explain exactly why the top-ranked `219/219` room/load attempt fails with `InvalidFragmentZoneBounds`.
- Build one canonical checked-in diagnostic surface that turns that generic failure into a first-hit explanation with the offending zone or bounds details needed to reason about the blocker.
- Keep this slice bounded to offline room/load diagnosis. Do not admit `219/219` as a supported positive pair yet, do not change viewer contracts, and do not widen runtime behavior beyond the diagnostic surface needed to explain the rejection.
- Treat a negative answer as useful output. If `219/219` is blocked because current fragment-zone projection assumptions reject real asset bounds, make that explicit and use it to drive the next planning step instead of inventing a new supported scene.

Hard-cut ownership:

- `runtime/room_state.zig`: canonical owner for fragment-zone projection and the `InvalidFragmentZoneBounds` failure
- `tools/cli.zig`: preferred owner for any explicit first-hit diagnostic surface surfaced through `inspect-room` or a closely related room probe
- `scene.zig` plus scene parser/model/tests: canonical owner for raw scene-zone metadata that the diagnostic must report
- `viewer_shell.zig`, `render.zig`, `main.zig`, and runtime admission policy: unchanged for this slice unless tiny plumbing is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative cases while you investigate the `219/219` room/load blocker offline.
- Prefer checked-in inputs that already exist at the seam: scene-zone bounds, zone type/number, fragment metadata, grid span assumptions, background pairing, and the exact error site in `runtime/room_state.zig`.
- No runtime widening, no new supported positive startup pair, no life execution, no scene transitions, no inventory/state systems, no combat, no track execution, no movement-policy changes, and no new unchecked public-runtime path.
- Do not treat docs-only reasoning as enough. The answer must come from checked-in code, tests, or a canonical CLI surface.
- Prefer a dedicated first-hit diagnostic or a precise `inspect-room` failure expansion over vague logging. If a new helper or payload is needed, keep it single-purpose and stable.

Useful work in scope:

- Reuse `inspect-room 219 219`, `inspect-scene 219`, and the fragment-zone projection helpers to surface the first offending zone/bounds pair rather than just returning `InvalidFragmentZoneBounds`.
- Pin the current ranking result only as context: `219` is the top offline candidate and `19` is not. The implementation work here is the room/load blocker explanation, not ranking changes.
- Surface the blocker in one canonical place that future sessions can rerun without manual debugging.
- If the root cause is a wrong background pairing or a too-strict room-state assumption, make that explicit. If the asset data itself is genuinely outside the current projection contract, make that explicit instead.

Acceptance:

- One canonical checked-in surface answers the question: why does the top-ranked `219/219` room/load attempt currently fail?
- The answer is derived from existing room-state, background, and scene-metadata owners, not from ad hoc docs-only reasoning.
- The repo makes it explicit whether the blocker is a fragment-zone alignment rule, a background-pairing issue, or another current room-state assumption.
- The guarded runtime/viewer boundary and its current startup/load diagnostics remain unchanged.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- rank-decoded-interior-candidates --json`
  - `zig build tool -- inspect-scene 219 --json`
  - `zig build tool -- inspect-room 219 219 --json`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
