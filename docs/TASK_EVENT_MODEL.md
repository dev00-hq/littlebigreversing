# Task Event Model

Mode: `critical-sparring / decision-review`

## Facts

- `docs/codex_memory/task_events.jsonl` is currently an append-only event log in policy, but the schema does not give a task a stable identity beyond a row's timestamped `record_id`.
- For `task_events`, `record_id` is derived from `timestamp_utc + stream + summary` in [tools/codex_memory.py](../tools/codex_memory.py).
- That means changing the wording of an old `summary` changes the canonical `record_id`, which pushes people toward rewriting old history rows instead of appending a fresh event.

## Evidence-backed critique

- The current model mixes two jobs: immutable audit log and evolving task state. That is the root flaw.
- Adding a pure tree on top of the current rows is not enough. Real work does not stay tree-shaped: tasks split, merge, block each other, and get reframed across streams. A tree encodes parentage but handles cross-links badly.
- Using `stream` as the durable grouping key is too weak. Streams are broad lanes such as `runtime` or `viewer-prep`, not stable task identities.
- Using mutable prose fields such as `summary` as part of identity is brittle. The review finding happened because the model made wording changes feel like identity changes.

Potential confirmation bias: treating the append-only bug as just a validator gap would miss the actual design pressure. The validator helps, but it does not remove the reason people keep wanting to mutate old rows.

## Stronger model

Use event-sourced task threads, not free-floating task events and not a tree-only shape.

### Proposed split

1. Keep `task_events.jsonl` append-only and immutable.
2. Add a stable task identity layer, for example `task_threads.jsonl`.
3. Make each task event reference a stable `task_id`.
4. Let current task state be derived from the latest event sequence, not edited into older rows.

### Thread record

Minimal thread fields:

- `task_id`
- `title`
- `status`
- `opened_by_event_id`
- `subsystem` or `stream_tags`
- `related_task_ids`

This is the durable identity surface. It answers "what task is this?" without depending on a mutable summary sentence.

### Event record

Minimal event additions:

- `task_id`
- `event_kind`: `opened`, `progressed`, `blocked`, `decision`, `completed`, `cancelled`, `reframed`
- `parent_event_id` optional
- `related_event_ids` optional

`parent_event_id` is useful for local sequencing. `related_event_ids` is the stronger primitive because task reality is often a DAG, not a tree.

## Counterpoint

A separate `task_threads.jsonl` layer adds complexity. If the repo barely uses durable task history, the added model can become ceremony.

That said, the current repo already uses task history enough for this weakness to matter. The review finding is evidence, not theory.

## Recommended next step

Do not migrate the schema yet.

First ship the append-only validator guard. Then, if task-history query quality or review friction still hurts, add:

- `task_threads.jsonl`
- `task_id` on new `task_events`
- optional `parent_event_id` and `related_event_ids`

That is the smallest change that fixes the identity problem without committing the repo to a fake tree.
