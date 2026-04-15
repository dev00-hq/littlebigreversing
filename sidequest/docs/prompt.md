# Room Intelligence Prompt

You are working in `D:\repos\reverse\littlebigreversing` on the `room intelligence` tooling project.

Read first:

1. `docs/plans.md`
2. `docs/architecture.md`
3. `docs/implement.md`
4. `docs/LBA2_ZIG_PORT_PLAN.md`

Role:

- Extend the existing Zig CLI with a new machine-facing `inspect-room-intelligence` command.

Hard requirements:

- Do not modify the JSON contract of `inspect-scene` or `inspect-room` in place.
- Reuse the existing typed scene decode, room decode, track decode, and life decode machinery.
- Keep output JSON-first and machine-readable.
- Support explicit scene/background selection by entry index and by friendly name.
- Always include resolved numeric indices in the output.
- Preserve raw actor truth and add mapped semantics only where current evidence justifies them.

Deliverables:

- CLI command parsing and validation
- metadata-backed name resolution
- composed room-intelligence payload
- actor intelligence section with `raw`, `mapped`, `track`, and `life`
- tests for parser behavior, name resolution, JSON payload invariants, and CLI integration

Validation:

- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build`
- `py -3 .\scripts\dev-shell.py exec --cwd port -- zig build test-fast`
- existing scene, room, and life inspection probes still work
- the new command works for one entry-based room pair and one name-based room pair

If documentation and code disagree, update the implementation to match `docs/plans.md` unless there is clear repo evidence that the plan is wrong.
