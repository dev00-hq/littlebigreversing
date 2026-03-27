# Mbn Corpus

## Purpose

Own the checked-in MBN reference corpus, preserved downstream tooling, and the repo-local workbench path used for evidence queries.

## Invariants

- Treat `docs/mbn_reference/runs/20260213T-raw` as the canonical scrape run.
- Keep checked-in corpus data authoritative and derived workbench state rebuildable.
- Do not blur MBN corpus storage with Codex memory storage.

## Current Parity Status

- The canonical corpus snapshot is checked in under `docs/mbn_reference/`.
- The repo still uses `tools/mbn_workbench.py` as the "checked-in inputs plus generated SQLite state" pattern for corpus work.
- Corpus maintenance is independent from the Zig runtime implementation path.

## Known Traps

- The corpus tree is large and often dirty after local analysis passes; do not infer current repo state from memory docs alone.
- Preserved `reference/` tooling is useful evidence context but not the canonical source of truth over the checked-in corpus snapshot.
- The checked-in corpus index is wider than the raw/workbench evidence layer. A thread can be present in `topics_discovered.jsonl` and `topic_classification.jsonl` even when no raw post payload was captured under `corpus/raw/posts/` and no evidence rows are searchable through `tools/mbn_workbench.py`.

## Canonical Entry Points

- `docs/mbn_reference/README.md`
- `tools/mbn_workbench.py`
- `tools/mbn_catalog_parser.py`

## Important Files

- `tools/mbn_workbench.md`
- `reference/discourse-downloader/`
- `reference/littlebigreversing/`

## Test / Probe Commands

- `python3 tools/mbn_workbench.py --help`
- `python3 tools/mbn_catalog_parser.py --help`

## Open Unknowns

- Which future port tasks need new durable evidence promoted out of the corpus and into checked-in docs.
- Whether the preserved downloader/tooling stack needs any repo-local hardening beyond current archival use.
