# Phase 0 Baseline

Phase 0 freezes the canonical inputs and golden targets for the Zig-first port plan.

This baseline is intentionally narrow:

- `docs/phase0/` is the checked-in canonical description.
- `work/phase0/` is rebuildable generated state.
- `py -3 tools/lba2_phase0.py build` is the end-to-end regeneration command.
- `py -3 tools/lba2_phase0.py validate` is the end-to-end integrity check.

Canonical roots:

- asset root: `work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2`
- classic source root: `reference/lba2-classic/SOURCES`
- evidence database: `work/mbn_workbench/mbn_workbench.sqlite3`

Generated outputs:

- `work/phase0/asset_inventory.json`
- `work/phase0/source_ownership.json`
- `work/phase0/evidence_bundle.json`
- `work/phase0/phase0_manifest.json`

Locked golden target ids:

- `interior-room-twinsens-house`
- `exterior-area-citadel-cliffs`
- `actor-player-scene2`
- `dialog-voice-holomap`
- `cutscene-ascenseu`

Phase 0 does not introduce Zig runtime code, SDL bootstrap, parsers, or a viewer. It exists to keep later implementation work from re-deciding inputs, evidence location, or first validation fixtures.
