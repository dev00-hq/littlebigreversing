# Canonical Inputs

Phase 0 supports one canonical local layout and fails fast if it is missing.

## Frozen Roots

- asset root: `work/_innoextract_full/Speedrun/Windows/LBA2_cdrom/LBA2`
- classic source root: `reference/lba2-classic/SOURCES`
- evidence database: `work/mbn_workbench/mbn_workbench.sqlite3`
- corpus source for rebuilding the evidence database: `docs/mbn_reference/`

## Required Canonical Dependencies

The generated asset inventory must classify and flag at least these dependencies for the first viewer and runtime slices:

- `SCENE.HQR`
- `LBA_BKG.HQR`
- `RESS.HQR`
- `BODY.HQR`
- `ANIM.HQR`
- `SPRITES.HQR`
- `TEXT.HQR`
- `VIDEO/VIDEO.HQR`
- the `VOX/*.VOX` set
- every island `.ILE` and `.OBL` pair in the canonical asset root

## Output Contract

- Generated phase 0 output lives only under `work/phase0/`.
- Generated JSON must be deterministic across repeated runs on unchanged inputs.
- Missing canonical roots or missing required canonical files are hard errors.
- Phase 0 validation checks generated output drift against the current canonical baseline definitions and required checked-in docs.
