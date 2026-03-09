# Latest State

## Snapshot Date
- 2026-02-13

## What Is Done

### Plan Implementation
- Implemented incremental analysis pipeline CLI: `scripts/analyze_corpus.rb`.
- Implemented pipeline engine: `scripts/lib/analysis_pipeline.rb`.
- Implemented stages `0..5`:
  - Stage 0: schema + sampling policy in run folder.
  - Stage 1: bounded ingestion from `corpus/index/*`, `corpus/normalized/*`, `spec/*.md`.
  - Stage 2: claims/entities extraction with deterministic IDs and dedupe.
  - Stage 3: topic cards synthesis.
  - Stage 4: raw backfill from `corpus/raw/posts/*.jsonl` with merged outputs.
  - Stage 5: query indexes + quality/drift reporting.

### Hardening/Fixes Completed
- Pipeline now stops at first `partial` stage instead of continuing downstream.
- Stage 4 now enforces hard limits (`max_records`, `max_bytes`, `max_entities`).
- Stage 4 resume is dedupe-safe for raw delta records (`record_id` dedupe + per-file cursors).
- `limit_hit` is cleared when a resumed stage completes.

### Tests Added/Updated
- `test/test_analysis_pipeline.rb` expanded with regressions for:
  - stop-on-partial behavior,
  - stage 4 boundedness,
  - stage 4 resume dedupe,
  - stale `limit_hit` clearing.
- Existing tests also passing:
  - `test/test_classifier.rb`
  - `test/test_post_extractors.rb`
  - `test/test_category_recursion.rb`
  - `test/test_discourse_client_rate_limit.rb`
  - `test/test_evidence_builder.rb`

## Latest Runs

### Baseline Run (index + normalized)
- Run ID: `20260213T-baseline`
- Input scope: `index_normalized`
- Status: stages `0..5` all `completed`
- Coverage:
  - `stage1_records`: `9612`
  - `claims`: `6592`
  - `entities`: `12157`
  - `topic_cards`: `170`
- Quality:
  - `duplicate_claim_ratio`: `0.0`
  - `provenance_completeness.ratio`: `1.0`

### Raw Backfill Run
- Run ID: `20260213T-raw`
- Input scope: `with_raw`
- Status: stages `0..5` all `completed`
- Stage 4 metrics:
  - `topics_processed`: `59`
  - `raw_records_processed`: `1258`
  - `raw_records_emitted`: `1258`
  - `claims_delta_emitted`: `649`
  - `entities_delta_emitted`: `842`
  - `limit_hit`: `nil`
- Coverage:
  - `stage1_records`: `9612`
  - `claims`: `7241`
  - `entities`: `12999`
  - `topic_cards`: `170`
- Delta vs baseline:
  - `claims`: `+649`
  - `entities`: `+842`
  - `topic_cards`: `+0`

## Current Analysis Signal (From `20260213T-raw`)
- Top claim kinds:
  - `format` (4562), `tool` (971), `glossary` (790), `workflow` (641), `pitfall` (277)
- Top entities:
  - `ile`, `hqr`, `index`, `compression`, `offset`, `editor`, `twinsen`
- Main artifacts to query:
  - `corpus/analysis/stage2_claims_merged.jsonl`
  - `corpus/analysis/stage2_entities_merged.jsonl`
  - `corpus/analysis/topic_cards_merged.jsonl`
  - `corpus/analysis/index/by_kind.json`
  - `corpus/analysis/index/by_entity.json`
  - `runs/20260213T-raw/quality_report.json`

## What Should Be Done Next

### 1) Freeze Current Snapshot As Canonical
- Treat `20260213T-raw` as the current canonical KB snapshot for downstream work.
- If needed, copy key artifacts into a versioned export folder (read-only handoff).

### 2) Produce First Human-Facing Reports (Priority Order)
- Report A: Pitfalls and breakage patterns (highest-risk topics first).
- Report B: Practical workflows (import/export/replace playbooks with evidence links).
- Report C: Tools and format reference map (tool -> format -> topic evidence).

### 3) Add a Small Query/Export Utility
- Add script to filter merged claims by:
  - `claim_kind`,
  - `topic_id`,
  - minimum `confidence`,
  - entity keyword.
- Output as JSONL and Markdown summaries for easy review.

### 4) Quality Refinement Pass
- Reduce noisy generic entities (`tool`, `workflow`) in ranking outputs.
- Separate `spec`-derived records from forum-topic records in report views.
- Add optional thresholds to suppress low-confidence claims in summaries.

### 5) Operational Cadence Going Forward
- For new forum snapshots:
  1. `build_corpus` refresh,
  2. `analyze_corpus --stage 4 --input-scope with_raw`,
  3. `analyze_corpus --stage 5 --resume`,
  4. compare drift in `quality_report.json`.

## Suggested Immediate Command Set (Next Run Cycle)
```bash
# (After corpus refresh) backfill + indexes
ruby scripts/analyze_corpus.rb --stage 4 --input-scope with_raw --run-id <new_run_id>
ruby scripts/analyze_corpus.rb --stage 5 --input-scope with_raw --run-id <new_run_id> --resume
```
