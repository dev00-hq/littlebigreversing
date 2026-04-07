# Next Prompt

Relevant subsystem packs for this task: `architecture`, `backgrounds`, `life_scripts`, `scene_decode`, and `platform_windows`.

Current state:

- `19/19` is still the only supported positive branch-B runtime/load baseline.
- The guarded negative scene-life startup path is settled behavior: `2/2`, `44/2`, and `11/10` fail fast with `ViewerUnsupportedSceneLife`, and both `inspect-room` and viewer startup print the same first-hit `event=room_load_rejected ... unsupported_life_opcode_name=... unsupported_life_opcode_id=... unsupported_life_offset=...` line before the error.
- The guarded positive startup path still lands on `raw_invalid_start`, and the current scene metadata for `19` still reports `track_count=0`.
- `life_audit.zig` plus `rank-decoded-interior-candidates` are the canonical offline branch-B ranking surface for fully decoded interior scenes.
- `triage-same-index-decoded-interior-candidates` is already landed as the canonical same-index compatibility report. On the current asset tree, it keeps `219` at rank `1`, `19` at rank `49/50`, and `86/86` as the highest-ranked compatible same-index pair above baseline.
- `inspect-room-fragment-zones 86 86 --json` proves that `86/86` is a trivial compatibility pass: `fragment_count=0`, `grm_zone_count=0`, `compatible_zone_count=0`.
- `triage-same-index-decoded-interior-candidates` currently reports `187/187` as the first fragment-bearing compatible same-index pair, at `rank=16`.
- `inspect-room-fragment-zones 187 187 --json` proves that `187/187` carries actual fragment-zone data: `fragment_count=2`, `grm_zone_count=2`, and `compatible_zone_count=2`.
- `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`, and `inspect-room-fragment-zones 219 219 --json` remains the canonical blocker explanation surface for its six current `misaligned_min` issues.
- The missing checked-in answer is no longer whether any same-index decoded interior pair outranks the guarded baseline and still clears the current fragment-zone rules. That answer is already yes. The missing answer is to make the fragment-bearing compatible result explicit on the canonical triage surface instead of forcing readers to infer it from the long candidate list.

Next slice:

- Keep one canonical offline report surface in `tools/cli.zig`: `triage-same-index-decoded-interior-candidates`.
- Extend that existing surface so both the default text output and the `--json` payload explicitly report:
  1. the current `19/19` baseline
  2. the highest-ranked compatible same-index pair overall
  3. the highest-ranked compatible same-index pair above baseline
  4. the highest-ranked fragment-bearing compatible same-index pair overall
  5. the highest-ranked fragment-bearing compatible same-index pair above baseline
- Define a fragment-bearing compatible pair as one with `compatible=true`, `fragment_count > 0`, and `grm_zone_count > 0`.
- Preserve `86/86` as the highest-ranked compatible pair overall and above baseline on the current asset tree.
- Surface an explicit `none` result for either fragment-bearing summary when the current candidate set does not contain one.
- Reuse `life_audit.zig` for ranking and `runtime/room_state.zig` for fragment-zone compatibility. Do not invent a second ranking contract, duplicate the admission logic, or add a new one-off report command for fragment-bearing candidates.
- Keep `inspect-room`, `inspect-room-fragment-zones`, and the guarded runtime/viewer boundary unchanged for this slice.

Hard-cut ownership:

- `life_audit.zig`: canonical owner of offline decoded-interior ranking
- `runtime/room_state.zig`: canonical owner of fragment-zone compatibility and current room-admission rules
- `background` composition/model code plus tests: canonical owner of fragment data and fragment entry indices
- `scene` metadata/model code plus tests: canonical owner of scene-zone inputs
- `tools/cli.zig`: canonical owner of the stable same-index triage/report surface
- `viewer_shell.zig`, `render.zig`, `main.zig`, `locomotion.zig`, and `world_query.zig`: unchanged for this slice unless tiny plumbing is strictly required by tests

Scope:

- Preserve the guarded `19/19` boundary and the current negative guarded cases.
- Preserve `rank-decoded-interior-candidates` as the canonical offline ranking surface; do not replace it with another ranking contract.
- Same-index scene/background pairs only for this slice.
- No runtime widening, no new supported positive startup pair, no life execution, no movement-policy changes, no scene transitions, and no new unchecked public-runtime path.
- Do not add new `219`-only diagnostics or a second report command.
- Do not "fix" invalid bounds by normalizing or clamping them in this slice. Surface the evidence instead.
- Do not treat zero-fragment or zero-GRM compatibility as fragment-bearing evidence.
- Do not treat docs-only reasoning as enough. The answer must come from checked-in code, tests, or the canonical CLI/report surface.

Acceptance:

- One canonical checked-in surface answers both questions cleanly:
  1. what is the highest-ranked compatible same-index pair overall and above baseline?
  2. what is the highest-ranked fragment-bearing compatible same-index pair overall and above baseline?
- The answer is derived from existing `life_audit` ranking plus `room_state` compatibility data, not from ad hoc docs-only reasoning.
- The text output and `--json` payload both make the baseline comparison explicit, preserve `86/86` as the highest-ranked compatible result on current assets, and separately surface `187/187` as the first fragment-bearing compatible result on current assets.
- The text output and `--json` payload both emit explicit `none` results for fragment-bearing summaries if a future asset/configuration has no compatible fragment-bearing pair.
- `inspect-room-fragment-zones 86 86 --json` stays a zero-fragment/zero-GRM compatible pass, `inspect-room-fragment-zones 187 187 --json` stays the first fragment-bearing compatible pass, and `inspect-room 219 219 --json` still fails with `InvalidFragmentZoneBounds`.

Validation:

- From native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test-fast`
  - `zig build tool -- rank-decoded-interior-candidates --json`
  - `zig build tool -- triage-same-index-decoded-interior-candidates`
  - `zig build tool -- triage-same-index-decoded-interior-candidates --json`
  - `zig build tool -- inspect-room-fragment-zones 86 86 --json`
  - `zig build tool -- inspect-room-fragment-zones 187 187 --json`
  - `zig build tool -- inspect-room-fragment-zones 219 219 --json`
  - `zig build tool -- inspect-room 219 219 --json`  `# expected InvalidFragmentZoneBounds plus fragment-zone diagnostics on stderr`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1 -Fast`
  - `.\scripts\verify-viewer.ps1`
