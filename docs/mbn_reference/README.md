# MBN Reference Corpus

Canonical scrape run: `runs/20260213T-raw`

This is the run to treat as the current source of truth for the MBN LBA2 scrape.

Why this run is canonical:
- It is the latest complete run.
- It includes the raw-inclusive stage 4 outputs.
- Its coverage matches the checked-in `corpus/` outputs:
  - `stage1_records`: 9612
  - `claims`: 7241
  - `entities`: 12999
  - `topic_cards`: 170
- It has zero drift relative to `runs/20260213T010000Z`, which means both runs produce the same final claim set. `20260213T-raw` is the later, clearer-named copy.

Run classification:
- `runs/20260213T-raw`: canonical full raw-inclusive run.
- `runs/20260213T010000Z`: full raw-inclusive run, data-equivalent to the canonical run.
- `runs/20260213T-baseline`: full normalized-only baseline run.
- `runs/20260213T000001Z`: earlier full normalized-only run.
- `runs/20260213T000002Z`: raw-inclusive run that stops at stage 4; not the canonical final run.
- `runs/20260213T000003Z`: test run with `max_records=100`.
- `runs/20260213T000004Z`: test run with `max_records=1`.

Current corpus note:
- The checked-in `corpus/` tree reflects the raw-inclusive full dataset, not the normalized-only baseline.
- When in doubt, prefer `runs/20260213T-raw` over every other run directory.
