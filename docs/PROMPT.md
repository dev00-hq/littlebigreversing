# Next Prompt

Relevant subsystem packs for this task: `architecture`, `scene_decode`, `life_scripts`, and `platform_windows`.

The previous runtime-topology evidence slice is complete in the current worktree:

- `port/src/runtime/room_state.zig` still owns the canonical guarded room/load seam plus immutable room/render snapshots.
- `port/src/runtime/session.zig` still owns mutable frame-to-frame runtime state only.
- `port/src/runtime/world_query.zig` still owns pure topology/query logic over immutable room data only.
- `port/src/root.zig` still exposes the canonical `runtime` module map, including `world_query`.
- `inspect-room`, the viewer runtime, and their tests still share the same guarded room/load seam.
- `19/19` remains the only positive guarded runtime/load baseline.
- `2/2`, `44/2`, and `11/10` remain guarded negative `ViewerUnsupportedSceneLife` cases.
- `11/10` remains available only on the explicit test-only unchecked evidence path.
- `world_query.zig` now makes topology evidence policy explicit:
  - guarded room snapshots are the only admitted runtime-semantic basis
  - unchecked evidence-only room snapshots are allowed for discovery-only observation
  - the current checked-in interior evidence set still does not justify richer relation classes
- the checked-in evidence scan result is now explicit:
  - `11/10` and `2/2` both show only flat, standable occupied-neighbor patterns
  - `44/2` is not an unchecked interior-room candidate at all; once the life guard is skipped it becomes `ViewerSceneMustBeInterior`

The next slice is not more topology work, not a new runtime diagnostic API, and not public error-surface widening. The next slice is a bounded proof about the existing life boundary:

- which exact unsupported life hit causes each guarded negative scene to fail
- whether the guarded room/load seam rejects on unsupported life before any later room classification logic matters

Implement a current-state boundary-proof slice that:

- keeps `port/src/runtime/room_state.zig` as the canonical guarded room/load seam
- keeps the public guarded failure as `ViewerUnsupportedSceneLife`
- keeps unsupported-life detail on test-local or offline-only paths unless a later prompt deliberately widens product surface
- does not add life execution
- does not widen guarded runtime support beyond `19/19`
- does not add a new CLI or viewer mode just to print richer blocker details

The target is narrow:

- pin the exact unsupported life hit behind the guarded negative cases that matter right now
- prove the guard ordering is intentional and stable

Useful work in scope includes:

- adding tests around `port/src/game_data/scene/life_audit.zig` that determine the exact unsupported hit for:
  - `SCENE.HQR[2]`
  - `SCENE.HQR[44]`
  - `SCENE.HQR[11]`
- asserting the relevant owner/opcode/offset facts instead of only asserting a generic failure
- proving separately that the guarded room/load seam still collapses those cases to `ViewerUnsupportedSceneLife`
- proving that `44/2` is a life-boundary rejection on the guarded path even though the unchecked test path later reveals `ViewerSceneMustBeInterior`
- documenting any new recurring trap in `ISSUES.md` and keeping the architecture subsystem pack aligned

Keep the implementation honest about current product boundaries:

- no life interpreter
- no compatibility bridge that returns both a public error and a side-channel diagnostic on normal runtime paths
- no unchecked loader added to the runtime public surface
- no metadata-only room path
- no gameplay widening
- no viewer/runtime ownership refactor
- no silent change to the order of the guarded checks

Default to the hard-cut current-state path:

- do not move guarded loading out of `port/src/runtime/room_state.zig`
- do not move life-boundary ownership out of `port/src/game_data/scene/life_audit.zig`
- do not turn `world_query.zig` into a life-boundary owner
- do not turn `session.zig` into a room classification or blocker-report owner
- do not change `inspect-room` so it exposes richer unsupported-life detail in normal use
- do not replace `ViewerUnsupportedSceneLife` with a more detailed public runtime error unless the slice first justifies that product change explicitly
- do not use the unchecked room path as if it were a supported diagnostic escape hatch
- do not let the `44/2` exterior fact blur the guarded-path assertion that unsupported life fires first there

The intended ownership boundary after this slice remains:

- `room_state.zig`: guarded room loading, immutable room snapshots, immutable render snapshots
- `session.zig`: mutable frame-to-frame runtime state only
- `world_query.zig`: pure topology/query logic plus diagnostic-only topology observation over immutable room data only
- `life_audit.zig`: canonical offline/source-facing unsupported-life hit analysis
- `app/viewer/*`: viewer-local layout, draw, HUD, fragment comparison, and interaction state

Relevant files are likely in:

- `port/src/runtime/room_state.zig`
- `port/src/game_data/scene/life_audit.zig`
- `port/src/game_data/scene/life_program.zig`
- `port/src/game_data/scene/tests/life_audit_tests.zig`
- `port/src/tools/cli.zig`
- `scripts/verify-viewer.ps1`
- `ISSUES.md`

Guardrails:

- Keep one canonical guarded room/runtime codepath.
- Keep `19/19` as the only positive guarded runtime/load pair.
- Keep `2/2`, `44/2`, and `11/10` as guarded negative `ViewerUnsupportedSceneLife` cases.
- Keep `11/10` only on explicit test-only unchecked evidence paths.
- Treat richer unsupported-hit detail as test-local or offline-only unless the slice explicitly justifies a public product change.
- Treat `44/2` becoming exterior on the unchecked path as a trap, not as permission to weaken the guarded-path life assertion.
- Do not turn this into a general blocker-reporting framework.
- Do not reopen topology relation expansion in this slice.

Acceptance:

- from native PowerShell, after `.\scripts\dev-shell.ps1`, run:
  - `cd port`
  - `zig build test`
  - `cd ..`
  - `.\scripts\verify-viewer.ps1`
- `port/src/runtime/room_state.zig` still owns guarded room loading and immutable room/render snapshots
- `port/src/runtime/session.zig` still owns mutable state only
- `port/src/runtime/world_query.zig` remains the canonical runtime-owned query surface and stays exported through `port/src/root.zig`
- tests now prove the exact unsupported life hit for the bounded negative scene set instead of only proving a generic rejection
- tests separately prove the guarded room/load seam still collapses those scenes to `ViewerUnsupportedSceneLife`
- tests or docs make the `44/2` ordering fact explicit:
  - guarded path: unsupported life rejects first
  - unchecked path: later room classification reveals exterior
- `inspect-room` still succeeds for `19/19` and still fails for `2/2`, `44/2`, and `11/10` with `ViewerUnsupportedSceneLife`
- no new public CLI/debug-report command or viewer surface is added just to expose blocker detail
