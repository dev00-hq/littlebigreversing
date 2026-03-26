# Phase0 Baseline

## Purpose

Freeze the canonical asset roots, classic source roots, evidence database, and golden targets used to anchor later implementation work.

## Invariants

- `docs/phase0/` is canonical and `work/phase0/` is rebuildable.
- Keep golden targets explicit instead of rediscovering them ad hoc.
- Do not expand phase0 into runtime code or viewer behavior.

## Current Parity Status

- Phase0 docs and generated outputs are in place.
- The current locked targets still include one interior room, one exterior area, one actor, one dialog/voice path, and one cutscene path.
- The tooling path remains `tools/lba2_phase0.py`.

## Known Traps

- The old exterior target confusion around `SCENE.HQR[4]` is resolved; do not revive it.
- Phase0 evidence is a baseline, not a substitute for current subsystem boundaries in `port/src`.

## Canonical Entry Points

- `docs/phase0/README.md`
- `docs/phase0/golden_targets.md`
- `tools/lba2_phase0.py`

## Important Files

- `docs/phase0/canonical_inputs.md`
- `docs/phase0/source_ownership.md`
- `docs/phase0/unresolved_gaps.md`

## Test / Probe Commands

- `py -3 tools/lba2_phase0.py build`
- `py -3 tools/lba2_phase0.py validate`

## Open Unknowns

- Which future viewer/runtime slices need new golden targets.
- Which remaining unresolved gaps should be promoted from memo status into active blockers.
