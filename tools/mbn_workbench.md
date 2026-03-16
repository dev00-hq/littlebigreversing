# MBN Workbench

`tools/mbn_workbench.py` implements two linked local tools over the canonical MBN scrape:

- Evidence-to-Spec Workbench
- Asset Semantics Cataloger

It reads the checked-in corpus under `docs/mbn_reference/` and writes generated SQLite state to `work/mbn_workbench/mbn_workbench.sqlite3`.

## Build The Database

```bash
python3 tools/mbn_workbench.py build-db
```

This ingests:

- `corpus/raw/topics/*.json`
- `corpus/raw/posts/*.jsonl`
- `corpus/index/evidence_index.jsonl`
- `corpus/analysis/topic_cards_merged.jsonl`

## Evidence Workbench Commands

Search evidence:

```bash
python3 tools/mbn_workbench.py search-evidence "scene"
python3 tools/mbn_workbench.py search-evidence "entry 49" --kind format
```

Promote an evidence row into the spec register:

```bash
python3 tools/mbn_workbench.py promote-evidence \
  2043 \
  "video-index" \
  "RESS.HQR entry 49 contains the movie-name index used by VIDEO.HQR." \
  --status verified_by_source \
  --asset RESS.HQR \
  --entry 49
```

Create a manual spec fact:

```bash
python3 tools/mbn_workbench.py add-spec-fact \
  "asset-entry" \
  "SCENE.HQR entries should be validated against source and runtime fixtures." \
  --status unverified \
  --source-kind manual
```

List the current spec register:

```bash
python3 tools/mbn_workbench.py list-spec
```

## Asset Catalog Commands

List indexed assets:

```bash
python3 tools/mbn_workbench.py list-assets --limit 20
```

Inspect one asset or one asset entry:

```bash
python3 tools/mbn_workbench.py show-asset RESS.HQR --entry 49
python3 tools/mbn_workbench.py show-asset ANIM.HQR --entry 1
```

The cataloger currently supports:

- structured entry lists like `%1 049 ~5 Movies names *`
- inline references like `Entry 49 of RESS.HQR`

Each catalog row keeps:

- asset name
- entry index
- visibility code and label
- type code and type label, when present in the same post
- descriptor
- source topic/post/url
- parser name and confidence

## Intended Workflow

1. Search evidence around a subsystem or file.
2. Inspect matching asset entries.
3. Promote only the claims you can defend into `spec_facts`.
4. Verify promoted facts against the original assets and `lba2-classic`.
