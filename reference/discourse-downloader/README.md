# discourse-downloader
Downloads all posts from a Discourse topic

Requires no external GEMS, should work without changes on a Mac.

This is still a work in progress.

## Usage

```bash
./discourse-downloader [options] <topic-or-category-url>
```

Common examples:

```bash
# Topic -> HTML (default)
./discourse-downloader https://forum.example.com/t/some-topic/123

# Topic -> text/markdown style
./discourse-downloader -m https://forum.example.com/t/some-topic/123

# Category -> downloads each topic in category
./discourse-downloader -m https://forum.example.com/c/general/1
```

## Authentication

The tool supports three modes:

1. Anonymous (no auth), for public forums/content.
2. Discourse API key auth (`API_KEY` + `API_USER`) via `-c <config-file>`.
3. Username/password session login via `-c <config-file>` or CLI flags.

### Username/password config file (`mbn` style)

Two-line format:

```text
user@example.com
super-secret-password
```

Usage:

```bash
./discourse-downloader -m -c ./mbn https://forum.magicball.net/t/about-the-administration-category/10
```

### API key config file

Ruby-style constants:

```ruby
API_KEY = "put_api_key_here"
API_USER = "username"
```

Usage:

```bash
./discourse-downloader -m -c ./apikeys https://forum.example.com/t/some-topic/123
```

### CLI auth flags

```bash
./discourse-downloader -u user@example.com --password-env DISCOURSE_PASSWORD \
  https://forum.example.com/t/some-topic/123
```

Available auth flags:

- `-u, --username USERNAME`
- `-p, --password PASSWORD`
- `--password-env ENV_VAR`

## LBA2 Corpus Pipeline

Use the pipeline to build a reproducible corpus from subforums, classify topics, fetch full posts for LBA2/mixed, and generate JSONL/CSV/spec outputs.

```bash
ruby scripts/build_corpus.rb -c ./mbn
```

Options:

- `--categories <url1,url2>` override target category URLs
- `--out-dir <dir>` write outputs under a custom root
- `--rules <file.yml>` override classifier terms/weights
- `--[no-]recurse-subcategories` include child categories recursively (default: enabled)
- `--mixed-policy <exclude|include|flagged>` control handling of mixed topics (default: `flagged`)
- `--min-delay-ms <n>` / `--max-delay-ms <n>` set per-request delay with jitter
- `--max-retries <n>` / `--backoff-base-ms <n>` control retry strategy for 429/5xx
- `-v` verbose progress logs

Behavior notes:

- Category harvesting follows Discourse pagination (`more_topics_url`) until exhaustion.
- Category roots can be expanded recursively using `/site.json` parent/child category relationships.
- Topic fetching includes full thread post streams (not only the first post), with pagination fallback when needed.
- Topic labels are `lba2`, `mixed`, and `undetermined`.
- In `flagged` mixed policy, mixed topics are included in the main corpus and marked with `needs_review=true`.

Default outputs:

- `corpus/topics_lba2.jsonl`
- `corpus/posts_lba2.jsonl`
- `corpus/links.csv`
- `corpus/raw/topics/<topic_id>.json`
- `corpus/raw/posts/<topic_id>.jsonl`
- `corpus/index/topics_discovered.jsonl`
- `corpus/index/topic_classification.jsonl`
- `corpus/index/mixed_review_queue.jsonl`
- `corpus/index/evidence_index.jsonl`
- `spec/formats.md`
- `spec/tools.md`
- `spec/workflows.md`
- `spec/glossary.md`
- `runs/<timestamp>/manifest.json`

Rebuild only the evidence index from an existing post corpus:

```bash
ruby scripts/build_evidence_index.rb --posts corpus/posts_lba2.jsonl \
  --out corpus/index/evidence_index.jsonl --base-url https://forum.magicball.net
```

## Incremental Analysis Pipeline

Execute `PLAN.md` as a bounded, resumable multi-stage run:

```bash
ruby scripts/analyze_corpus.rb --stage 5 --input-scope index_normalized
```

Key options:

- `--stage <0..5>` highest stage to execute.
- `--resume` continue the latest (or `--run-id`) analysis run.
- `--input-scope <index_normalized|with_raw>` include only index+normalized inputs, or include raw backfill stage.
- `--max-records <n>` hard stage limit for processed records.
- `--max-bytes <n>` hard stage limit for parsed bytes.
- `--max-entities <n>` hard stage limit for emitted claims/entities.
- `--chunk-size <n>` checkpoint/write frequency.

Execution behavior:

- The pipeline stops at the first stage that becomes `partial` due to limits.
- Use `--resume` (optionally with `--run-id`) to continue from the saved checkpoint.

Outputs:

- `corpus/analysis/stage1_records.jsonl`
- `corpus/analysis/stage2_claims.jsonl`
- `corpus/analysis/stage2_entities.jsonl`
- `corpus/analysis/topic_cards.jsonl`
- `corpus/analysis/index/*.json`
- `runs/<timestamp>/analysis_manifest.json`
- `runs/<timestamp>/quality_report.json`

## Claims Query Utility

Filter/export analysis claims from canonical outputs:

```bash
ruby scripts/query_claims.rb [options]
```

Default source behavior:

- Uses `corpus/analysis/stage2_claims_merged.jsonl` when present.
- Falls back to `corpus/analysis/stage2_claims.jsonl`.

Common options:

- `--claim-kind KIND`
- `--topic-id ID`
- `--min-confidence FLOAT` (0.0..1.0)
- `--entity KEYWORD`
- `--limit N`
- `--format jsonl|md|both` (default: `jsonl`)
- `--out-jsonl FILE`
- `--out-md FILE`
- `--claims-path FILE` (manual override)

Examples:

```bash
# filter by kind + confidence (stdout JSONL)
ruby scripts/query_claims.rb --claim-kind pitfall --min-confidence 0.7

# filter by topic + entity keyword (stdout Markdown)
ruby scripts/query_claims.rb --topic-id 30241 --entity offset --format md

# export both JSONL and Markdown to files
ruby scripts/query_claims.rb --claim-kind workflow --format both \
  --out-jsonl runs/exports/workflows.jsonl --out-md runs/exports/workflows.md
```
