# Room Intelligence Implementation Contract

## Source Of Truth

Use these documents in order:

1. `sidequest/docs/plans.md`
2. `sidequest/docs/architecture.md`
3. `docs/LBA2_ZIG_PORT_PLAN.md`
4. `sidequest/docs/prompt.md`

This pack is a side quest and is not canonical until promoted.

`sidequest/docs/plans.md` is the source of truth for this project. If another file drifts, update the other file to match `plans.md` rather than improvising.

## Execution Rules

- Extend existing scene and room decode codepaths; do not create a second parser.
- Keep `inspect-scene` and `inspect-room` stable.
- Add the new command as an additive surface.
- Prefer machine-readable JSON contracts over human-only terminal summaries.
- Preserve raw values whenever a friendly interpretation is incomplete.

## Ambiguity Rules

- If a field meaning is not already justified by repo evidence, keep it raw.
- If a name lookup matches more than one candidate, fail with a deterministic ambiguity error.
- If scene and background names are missing from metadata, allow entry-index usage to continue working.
- Do not infer scene/background pairing from matching numbers in v1; require explicit scene and explicit background selection.
- Keep numeric selectors raw-index-first, but reject out-of-range entries before deeper loader dispatch.

## Validation Rules

After each milestone:

- run `zig build`
- run `zig build test-fast`
- run `zig build test-cli-integration`
- run the existing `inspect-scene`, `inspect-room`, and life inspection probes that cover the touched behavior
- add or update JSON-focused tests for the new command before broadening scope

Before considering the work complete:

- command parsing is covered
- name resolution is covered
- one positive entry-based probe is covered
- one positive name-based probe is covered
- one validation-failure probe is covered
- out-of-range numeric selector failures are covered
- existing inspector commands still pass unchanged

## Completion Criteria

The project is complete when:

- `inspect-room-intelligence` exists
- it accepts scene/background selection by entry or name
- it emits one stable JSON payload with scene, background, actors, zones, tracks, and patches
- it includes explicit raw-vs-decoded actor counts and a machine-readable `validation` block
- actor records expose both raw fields and mapped semantics
- life and track structure are included without promising full life semantic decompilation
