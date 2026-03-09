## Context-Rot-Resistant Corpus Analysis Plan (Incremental, Fully Automatic)

  ### Summary

  Build a staged analysis pipeline that never reads whole large files into a single run, works in bounded chunks, and emits checkpointed JSONL artifacts after every stage.
  Default execution starts with corpus/index/* and corpus/normalized/*, then expands to corpus/raw/* only after schema and scoring are stable.

  ### Goals And Success Criteria

  1. Produce a queryable knowledge base (JSONL) with deterministic records and provenance.
  2. Keep each run bounded by explicit limits (records, bytes, or files) to prevent context rot.
  3. Support resumable incremental runs with manifests and per-stage checkpoints.
  4. Maintain fully automatic processing (no review queue gating).
  5. Provide measurable quality signals (coverage, duplicate rate, extraction confidence, drift).

  ### Scope

  1. In scope now:
      - corpus/index/*.jsonl
      - corpus/normalized/*.jsonl
      - spec/*.md as supporting signals
  2. Deferred to stage 4+:
      - corpus/raw/topics/*.json
      - corpus/raw/posts/*.jsonl
  3. Out of scope:
      - manual adjudication workflow
      - one-shot “read everything” analysis

  ### Stage Plan

  1. Stage 0: Schema Registry + Sampling Rules
      - Define canonical schemas for topic, post, evidence, tool, format, workflow, glossary entities.
      - Record per-file-type parsing rules and max sample limits.
      - Output: runs/<ts>/schema_registry.json, runs/<ts>/sampling_policy.json.
  2. Stage 1: High-Signal Ingestion (Indexes + Normalized)
      - Ingest files in fixed batches (example: 250 records/chunk).
      - Normalize fields and attach provenance (source_file, line_no, topic_id, post_id, source_url).
      - Output: corpus/analysis/stage1_records.jsonl, manifest with offsets.
  3. Stage 2: Entity + Claim Extraction
      - Extract entities: tools, file formats, workflows, glossary candidates, pitfalls.
      - Emit atomic claims with evidence links and confidence score.
      - Deduplicate by stable hash of normalized claim text + source tuple.
      - Output: corpus/analysis/stage2_claims.jsonl, stage2_entities.jsonl.
  4. Stage 3: Topic-Level Synthesis
      - Build per-topic summaries from bounded evidence windows.
      - Generate structured topic cards (problem, method, constraints, known risks, referenced tools/formats).
      - Output: corpus/analysis/topic_cards.jsonl.
  5. Stage 4: Raw Backfill
      - Add corpus/raw/* in small deterministic slices (topic-id windows).
      - Recompute only affected derived records (incremental DAG update).
      - Output: delta files + merged canonical outputs.
  6. Stage 5: Query Layer + Reporting
      - Build lightweight query indexes (by topic_id, kind, entity, confidence).
      - Emit coverage and drift reports per run.
      - Output: corpus/analysis/index/*.json, runs/<ts>/quality_report.json.

  ### Anti-Context-Rot Controls

  1. Hard limits per run:
      - max input records
      - max bytes parsed
      - max entities emitted
  2. Strict chunking:
      - fixed-size batch processing with checkpoint after each batch
  3. Deterministic resumability:
      - persistent cursor per file (byte_offset or line_offset)
  4. Separation of concerns:
      - ingestion, extraction, synthesis as separate stages/files
  5. No full-file reads for large corpora:
      - stream JSONL line-by-line
      - partial window parsing for large JSON blobs when needed

  ### Important Interfaces / Types (Planned)

  1. AnalysisRecord (JSONL)
      - record_id, record_type, topic_id, post_id, text, metadata, provenance
  2. ClaimRecord
      - claim_id, claim_kind, claim_text, entities[], confidence, evidence_refs[]
  3. TopicCard
      - topic_id, title, labels, summary, key_claims[], tools[], formats[], workflows[], risks[]
  4. RunManifest
      - run_id, stage, inputs, cursors, outputs, metrics, started_at, finished_at
  5. CLI entrypoint extension (planned)
      - ruby scripts/analyze_corpus.rb --stage <n> --resume --max-records <n> --input-scope <scope>

  ### Testing And Validation Scenarios

  1. Schema conformance:
      - each output file validates against required keys/types
  2. Determinism:
      - same inputs + same limits produce identical IDs/hashes
  3. Resume correctness:
      - interrupted run resumes without dropped/duplicated records
  4. Boundedness:
      - parser never exceeds configured limits in a stage
  5. Incremental recompute:
      - adding new input records only updates dependent outputs
  6. Quality checks:
      - duplicate claim ratio below threshold
      - provenance completeness near 100%
      - confidence distribution report generated each run

  ### Assumptions And Defaults

  1. Default final artifact is machine-queryable JSONL KB.
  2. Workflow is fully automatic (no human review gate).
  3. Cadence is incremental snapshots with manifests.
  4. Initial scope is indexes + normalized corpus only.
  5. Existing corpus schemas remain broadly stable; schema drift is handled via registry versioning.
  6. Large raw files are processed only in bounded slices and only after early-stage stability.