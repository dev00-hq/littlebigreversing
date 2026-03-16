#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "codex-memory-v1"
DECISION_STATUSES = {"accepted", "proposed", "provisional", "rejected", "superseded"}
TASK_STATUSES = {"planned", "in_progress", "blocked", "completed", "cancelled"}

DEFAULT_REPO_ROOT = Path(__file__).resolve().parent.parent

MARKDOWN_SPECS: dict[str, tuple[str, ...]] = {
    "README.md": ("Workflow", "Commands", "Write Rules"),
    "project_brief.md": ("Purpose", "Repo Map", "Canonical Sources", "Invariants", "Non-Goals"),
    "current_focus.md": ("Current Priorities", "Active Streams", "Blocked Items", "Next Actions"),
    "handoff.md": ("Current State", "Verified Facts", "Open Risks", "Next 3 Steps"),
}

DECISION_REQUIRED_FIELDS = (
    "schema_version",
    "decision_id",
    "timestamp_utc",
    "topic",
    "status",
    "statement",
    "rationale",
    "evidence_refs",
    "affected_paths",
    "supersedes",
    "author",
)
TASK_REQUIRED_FIELDS = (
    "schema_version",
    "event_id",
    "timestamp_utc",
    "task_id",
    "title",
    "status",
    "summary",
    "next_actions",
    "affected_paths",
    "author",
)


@dataclass(frozen=True)
class MemoryPaths:
    repo_root: Path
    docs_dir: Path
    work_dir: Path
    db_path: Path
    handoff_summary_path: Path

    @classmethod
    def defaults(cls, repo_root: Path = DEFAULT_REPO_ROOT) -> "MemoryPaths":
        repo_root = repo_root.resolve()
        docs_dir = repo_root / "docs" / "codex_memory"
        work_dir = repo_root / "work" / "codex_memory"
        return cls(
            repo_root=repo_root,
            docs_dir=docs_dir,
            work_dir=work_dir,
            db_path=work_dir / "codex_memory.sqlite3",
            handoff_summary_path=work_dir / "handoff_summary.md",
        )

    @property
    def decision_log(self) -> Path:
        return self.docs_dir / "decision_log.jsonl"

    @property
    def task_log(self) -> Path:
        return self.docs_dir / "task_log.jsonl"


def utc_now(timestamp: str | None = None) -> str:
    if timestamp:
        return parse_timestamp(timestamp)
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_timestamp(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"invalid ISO timestamp: {value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp must include timezone: {value}")
    return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact_timestamp(value: str) -> str:
    return value.replace("-", "").replace(":", "").replace("+00:00", "Z").replace(".", "")


def stable_hash(payload: Any) -> str:
    normalized = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "record"


def normalize_path_strings(values: list[str]) -> list[str]:
    normalized: list[str] = []
    for raw in values:
        candidate = raw.strip().replace("\\", "/")
        if not candidate:
            raise ValueError("path values must not be empty")
        path = Path(candidate)
        if path.is_absolute():
            raise ValueError(f"path must be repo-relative, not absolute: {raw}")
        parts = path.parts
        if any(part == ".." for part in parts):
            raise ValueError(f"path must stay inside repo: {raw}")
        normalized.append(path.as_posix())
    return normalized


def normalize_string_list(values: list[str], field_name: str) -> list[str]:
    normalized = [value.strip() for value in values if value.strip()]
    if len(normalized) != len([value for value in values if value is not None]):
        raise ValueError(f"{field_name} must not contain empty values")
    return normalized


def make_decision_id(topic: str, statement: str, timestamp_utc: str) -> str:
    digest = stable_hash({"topic": topic, "statement": statement})[:10]
    return f"decision-{compact_timestamp(timestamp_utc)}-{digest}"


def make_task_event_id(task_id: str, summary: str, timestamp_utc: str) -> str:
    digest = stable_hash({"task_id": task_id, "summary": summary})[:10]
    return f"task-{compact_timestamp(timestamp_utc)}-{digest}"


def write_if_missing(path: Path, content: str) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def generic_templates(paths: MemoryPaths) -> dict[str, str]:
    repo_name = paths.repo_root.name
    return {
        "README.md": """# Codex Memory

## Workflow

1. Read the canonical memory docs or run `python3 tools/codex_memory.py context`.
2. Record durable conclusions in `decision_log.jsonl`.
3. Record meaningful task checkpoints in `task_log.jsonl`.
4. Rebuild generated state with `python3 tools/codex_memory.py build-index`.

## Commands

```bash
python3 tools/codex_memory.py validate
python3 tools/codex_memory.py context
python3 tools/codex_memory.py build-index
python3 tools/codex_memory.py refresh-handoff
```

## Write Rules

- Checked-in memory is canonical.
- Generated state is rebuildable and non-canonical.
- Use the current schema version only.
""",
        "project_brief.md": f"""# Project Brief

## Purpose

Durable Codex memory for `{repo_name}`.

## Repo Map

- `docs/`: canonical checked-in knowledge
- `tools/`: local tooling
- `work/`: generated state

## Canonical Sources

- Add the primary sources of truth here.

## Invariants

- Keep canonical memory in `docs/codex_memory/`.
- Keep generated memory state in `work/codex_memory/`.

## Non-Goals

- Cross-repo personal memory
- Automatic migration of older memory schemas
""",
        "current_focus.md": """# Current Focus

## Current Priorities

- Keep durable task state out of chat-only context.

## Active Streams

- Fill this in for the repository.

## Blocked Items

- Fill this in when needed.

## Next Actions

- Update this file before major handoffs.
""",
        "handoff.md": """# Handoff

## Current State

- Summarize the latest durable repo state.

## Verified Facts

- Add verified facts only.

## Open Risks

- List active risks and sources of uncertainty.

## Next 3 Steps

1. Replace this scaffold with real next steps.
2. Keep them explicit.
3. Keep them short.
""",
        "decision_log.jsonl": "",
        "task_log.jsonl": "",
    }


def init_memory(paths: MemoryPaths) -> None:
    paths.docs_dir.mkdir(parents=True, exist_ok=True)
    paths.work_dir.mkdir(parents=True, exist_ok=True)
    templates = generic_templates(paths)
    for filename, content in templates.items():
        write_if_missing(paths.docs_dir / filename, content)


def extract_h2_sections(content: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    for line in content.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            sections[current] = []
            continue
        if current is not None:
            sections[current].append(line)
    return {key: "\n".join(value).strip() for key, value in sections.items()}


def validate_markdown_file(path: Path, required_sections: tuple[str, ...]) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"missing file: {path}"]
    content = path.read_text(encoding="utf-8")
    if not content.startswith("# "):
        errors.append(f"{path}: missing top-level heading")
    sections = extract_h2_sections(content)
    for section in required_sections:
        if section not in sections or not sections[section].strip():
            errors.append(f"{path}: missing or empty ## {section}")
    return errors


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise ValueError(f"missing file: {path}")
    records: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_no, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON: {exc.msg}") from exc
            if not isinstance(payload, dict):
                raise ValueError(f"{path}:{line_no}: record must be an object")
            records.append(payload)
    return records


def validate_decision_record(record: dict[str, Any], path: Path, line_no: int) -> list[str]:
    errors: list[str] = []
    for field_name in DECISION_REQUIRED_FIELDS:
        if field_name not in record:
            errors.append(f"{path}:{line_no}: missing field {field_name}")
    if errors:
        return errors
    if record["schema_version"] != SCHEMA_VERSION:
        errors.append(f"{path}:{line_no}: unsupported schema_version {record['schema_version']}")
    if record["status"] not in DECISION_STATUSES:
        errors.append(f"{path}:{line_no}: unsupported decision status {record['status']}")
    for field_name in ("evidence_refs", "affected_paths", "supersedes"):
        if not isinstance(record[field_name], list) or any(not isinstance(item, str) or not item.strip() for item in record[field_name]):
            errors.append(f"{path}:{line_no}: {field_name} must be a list of non-empty strings")
    if not isinstance(record["statement"], str) or not record["statement"].strip():
        errors.append(f"{path}:{line_no}: statement must be a non-empty string")
    if not isinstance(record["rationale"], str) or not record["rationale"].strip():
        errors.append(f"{path}:{line_no}: rationale must be a non-empty string")
    try:
        parse_timestamp(record["timestamp_utc"])
    except ValueError as exc:
        errors.append(f"{path}:{line_no}: {exc}")
    expected_id = make_decision_id(record["topic"], record["statement"], record["timestamp_utc"])
    if record["decision_id"] != expected_id:
        errors.append(f"{path}:{line_no}: decision_id does not match canonical form {expected_id}")
    return errors


def validate_task_record(record: dict[str, Any], path: Path, line_no: int) -> list[str]:
    errors: list[str] = []
    for field_name in TASK_REQUIRED_FIELDS:
        if field_name not in record:
            errors.append(f"{path}:{line_no}: missing field {field_name}")
    if errors:
        return errors
    if record["schema_version"] != SCHEMA_VERSION:
        errors.append(f"{path}:{line_no}: unsupported schema_version {record['schema_version']}")
    if record["status"] not in TASK_STATUSES:
        errors.append(f"{path}:{line_no}: unsupported task status {record['status']}")
    for field_name in ("next_actions", "affected_paths"):
        if not isinstance(record[field_name], list) or any(not isinstance(item, str) or not item.strip() for item in record[field_name]):
            errors.append(f"{path}:{line_no}: {field_name} must be a list of non-empty strings")
    if not isinstance(record["summary"], str) or not record["summary"].strip():
        errors.append(f"{path}:{line_no}: summary must be a non-empty string")
    try:
        parse_timestamp(record["timestamp_utc"])
    except ValueError as exc:
        errors.append(f"{path}:{line_no}: {exc}")
    expected_id = make_task_event_id(record["task_id"], record["summary"], record["timestamp_utc"])
    if record["event_id"] != expected_id:
        errors.append(f"{path}:{line_no}: event_id does not match canonical form {expected_id}")
    return errors


def validate_jsonl_file(path: Path, validator: Any) -> list[str]:
    errors: list[str] = []
    if not path.exists():
        return [f"missing file: {path}"]
    with path.open(encoding="utf-8") as handle:
        for line_no, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                errors.append(f"{path}:{line_no}: invalid JSON: {exc.msg}")
                continue
            if not isinstance(record, dict):
                errors.append(f"{path}:{line_no}: record must be an object")
                continue
            errors.extend(validator(record, path, line_no))
    return errors


def validate_all(paths: MemoryPaths) -> list[str]:
    errors: list[str] = []
    for filename, required_sections in MARKDOWN_SPECS.items():
        errors.extend(validate_markdown_file(paths.docs_dir / filename, required_sections))
    errors.extend(validate_jsonl_file(paths.decision_log, validate_decision_record))
    errors.extend(validate_jsonl_file(paths.task_log, validate_task_record))
    return errors


def read_markdown(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def recent_records(path: Path, limit: int) -> list[dict[str, Any]]:
    records = load_jsonl(path)
    return records[-limit:]


def render_context(paths: MemoryPaths, recent_limit: int = 5) -> str:
    errors = validate_all(paths)
    if errors:
        raise ValueError("\n".join(errors))

    project_sections = extract_h2_sections(read_markdown(paths.docs_dir / "project_brief.md"))
    focus_sections = extract_h2_sections(read_markdown(paths.docs_dir / "current_focus.md"))
    handoff_sections = extract_h2_sections(read_markdown(paths.docs_dir / "handoff.md"))
    decisions = recent_records(paths.decision_log, recent_limit)
    tasks = recent_records(paths.task_log, recent_limit)

    lines = [
        "# Codex Context",
        "",
        "## Purpose",
        project_sections["Purpose"],
        "",
        "## Repo Map",
        project_sections["Repo Map"],
        "",
        "## Invariants",
        project_sections["Invariants"],
        "",
        "## Current Priorities",
        focus_sections["Current Priorities"],
        "",
        "## Active Streams",
        focus_sections["Active Streams"],
        "",
        "## Current State",
        handoff_sections["Current State"],
        "",
        "## Open Risks",
        handoff_sections["Open Risks"],
        "",
        "## Next 3 Steps",
        handoff_sections["Next 3 Steps"],
        "",
        "## Recent Decisions",
    ]

    if decisions:
        for record in decisions:
            lines.append(
                f"- {record['timestamp_utc']} {record['decision_id']}: {record['statement']} ({record['status']})"
            )
    else:
        lines.append("- None recorded.")

    lines.extend(["", "## Recent Task Events"])
    if tasks:
        for record in tasks:
            lines.append(
                f"- {record['timestamp_utc']} {record['task_id']} / {record['status']}: {record['summary']}"
            )
    else:
        lines.append("- None recorded.")

    return "\n".join(lines).strip() + "\n"


def connect_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def build_index(paths: MemoryPaths) -> None:
    errors = validate_all(paths)
    if errors:
        raise ValueError("\n".join(errors))

    conn = connect_db(paths.db_path)
    try:
        conn.executescript(
            """
            DROP TABLE IF EXISTS documents;
            DROP TABLE IF EXISTS decisions;
            DROP TABLE IF EXISTS task_events;

            CREATE TABLE documents (
                name TEXT PRIMARY KEY,
                path TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL
            );

            CREATE TABLE decisions (
                decision_id TEXT PRIMARY KEY,
                timestamp_utc TEXT NOT NULL,
                topic TEXT NOT NULL,
                status TEXT NOT NULL,
                statement TEXT NOT NULL,
                rationale TEXT NOT NULL,
                evidence_refs_json TEXT NOT NULL,
                affected_paths_json TEXT NOT NULL,
                supersedes_json TEXT NOT NULL,
                author TEXT NOT NULL
            );

            CREATE TABLE task_events (
                event_id TEXT PRIMARY KEY,
                timestamp_utc TEXT NOT NULL,
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                status TEXT NOT NULL,
                summary TEXT NOT NULL,
                next_actions_json TEXT NOT NULL,
                affected_paths_json TEXT NOT NULL,
                author TEXT NOT NULL
            );
            """
        )

        for filename in MARKDOWN_SPECS:
            path = paths.docs_dir / filename
            body = read_markdown(path)
            title = body.splitlines()[0].lstrip("# ").strip()
            conn.execute(
                """
                INSERT INTO documents(name, path, title, body)
                VALUES (?, ?, ?, ?)
                """,
                (filename, path.relative_to(paths.repo_root).as_posix(), title, body),
            )

        for record in load_jsonl(paths.decision_log):
            conn.execute(
                """
                INSERT INTO decisions(
                    decision_id, timestamp_utc, topic, status, statement, rationale,
                    evidence_refs_json, affected_paths_json, supersedes_json, author
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    record["decision_id"],
                    record["timestamp_utc"],
                    record["topic"],
                    record["status"],
                    record["statement"],
                    record["rationale"],
                    json.dumps(record["evidence_refs"], ensure_ascii=True, sort_keys=True),
                    json.dumps(record["affected_paths"], ensure_ascii=True, sort_keys=True),
                    json.dumps(record["supersedes"], ensure_ascii=True, sort_keys=True),
                    record["author"],
                ),
            )

        for record in load_jsonl(paths.task_log):
            conn.execute(
                """
                INSERT INTO task_events(
                    event_id, timestamp_utc, task_id, title, status, summary,
                    next_actions_json, affected_paths_json, author
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    record["event_id"],
                    record["timestamp_utc"],
                    record["task_id"],
                    record["title"],
                    record["status"],
                    record["summary"],
                    json.dumps(record["next_actions"], ensure_ascii=True, sort_keys=True),
                    json.dumps(record["affected_paths"], ensure_ascii=True, sort_keys=True),
                    record["author"],
                ),
            )
        conn.commit()
    finally:
        conn.close()


def append_jsonl_record(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True, sort_keys=True))
        handle.write("\n")


def add_decision(
    paths: MemoryPaths,
    *,
    topic: str,
    status: str,
    statement: str,
    rationale: str,
    evidence_refs: list[str],
    affected_paths: list[str],
    supersedes: list[str],
    author: str,
    timestamp: str | None,
) -> dict[str, Any]:
    if status not in DECISION_STATUSES:
        raise ValueError(f"unsupported decision status: {status}")
    timestamp_utc = utc_now(timestamp)
    record = {
        "schema_version": SCHEMA_VERSION,
        "decision_id": make_decision_id(topic, statement, timestamp_utc),
        "timestamp_utc": timestamp_utc,
        "topic": topic.strip(),
        "status": status,
        "statement": statement.strip(),
        "rationale": rationale.strip(),
        "evidence_refs": normalize_string_list(evidence_refs, "evidence_refs"),
        "affected_paths": normalize_path_strings(affected_paths),
        "supersedes": normalize_string_list(supersedes, "supersedes"),
        "author": author.strip(),
    }
    errors = validate_decision_record(record, paths.decision_log, 1)
    if errors:
        raise ValueError("\n".join(errors))
    append_jsonl_record(paths.decision_log, record)
    return record


def add_task_event(
    paths: MemoryPaths,
    *,
    task_id: str,
    title: str,
    status: str,
    summary: str,
    next_actions: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict[str, Any]:
    if status not in TASK_STATUSES:
        raise ValueError(f"unsupported task status: {status}")
    timestamp_utc = utc_now(timestamp)
    normalized_task_id = slugify(task_id)
    record = {
        "schema_version": SCHEMA_VERSION,
        "event_id": make_task_event_id(normalized_task_id, summary, timestamp_utc),
        "timestamp_utc": timestamp_utc,
        "task_id": normalized_task_id,
        "title": title.strip(),
        "status": status,
        "summary": summary.strip(),
        "next_actions": normalize_string_list(next_actions, "next_actions"),
        "affected_paths": normalize_path_strings(affected_paths),
        "author": author.strip(),
    }
    errors = validate_task_record(record, paths.task_log, 1)
    if errors:
        raise ValueError("\n".join(errors))
    append_jsonl_record(paths.task_log, record)
    return record


def refresh_handoff_summary(paths: MemoryPaths, recent_limit: int = 5) -> Path:
    context = render_context(paths, recent_limit=recent_limit)
    lines = context.splitlines()
    summary_lines = ["# Derived Handoff Summary", "", "Generated from canonical memory files.", ""]
    summary_lines.extend(lines[2:])
    paths.handoff_summary_path.parent.mkdir(parents=True, exist_ok=True)
    paths.handoff_summary_path.write_text("\n".join(summary_lines).strip() + "\n", encoding="utf-8")
    return paths.handoff_summary_path


def print_errors(errors: list[str]) -> int:
    for error in errors:
        print(error, file=sys.stderr)
    return 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Repo-scoped Codex memory utilities")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("init", help="Scaffold the Codex memory files if they are missing")
    subparsers.add_parser("validate", help="Validate canonical memory files")

    build_index_parser = subparsers.add_parser("build-index", help="Build the derived SQLite index")
    build_index_parser.add_argument("--print-path", action="store_true", help="Print the index path after success")

    context_parser = subparsers.add_parser("context", help="Render a compact context briefing")
    context_parser.add_argument("--recent", type=int, default=5, help="Number of recent records to include")

    decision_parser = subparsers.add_parser("add-decision", help="Append a durable decision record")
    decision_parser.add_argument("--topic", required=True)
    decision_parser.add_argument("--status", required=True, choices=sorted(DECISION_STATUSES))
    decision_parser.add_argument("--statement", required=True)
    decision_parser.add_argument("--rationale", required=True)
    decision_parser.add_argument("--evidence-ref", action="append", default=[])
    decision_parser.add_argument("--affected-path", action="append", default=[])
    decision_parser.add_argument("--supersedes", action="append", default=[])
    decision_parser.add_argument("--author", default="codex")
    decision_parser.add_argument("--timestamp", help="ISO timestamp for deterministic scripting/tests")

    task_parser = subparsers.add_parser("add-task-event", help="Append a task event record")
    task_parser.add_argument("--task-id", required=True)
    task_parser.add_argument("--title", required=True)
    task_parser.add_argument("--status", required=True, choices=sorted(TASK_STATUSES))
    task_parser.add_argument("--summary", required=True)
    task_parser.add_argument("--next-action", action="append", default=[])
    task_parser.add_argument("--affected-path", action="append", default=[])
    task_parser.add_argument("--author", default="codex")
    task_parser.add_argument("--timestamp", help="ISO timestamp for deterministic scripting/tests")

    refresh_parser = subparsers.add_parser("refresh-handoff", help="Write a derived handoff summary under work/")
    refresh_parser.add_argument("--recent", type=int, default=5, help="Number of recent records to include")
    refresh_parser.add_argument("--print-path", action="store_true", help="Print the output path after success")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    paths = MemoryPaths.defaults()

    try:
        if args.command == "init":
            init_memory(paths)
            print(paths.docs_dir)
            return 0
        if args.command == "validate":
            errors = validate_all(paths)
            if errors:
                return print_errors(errors)
            print("ok")
            return 0
        if args.command == "build-index":
            build_index(paths)
            if args.print_path:
                print(paths.db_path)
            return 0
        if args.command == "context":
            print(render_context(paths, recent_limit=args.recent), end="")
            return 0
        if args.command == "add-decision":
            record = add_decision(
                paths,
                topic=args.topic,
                status=args.status,
                statement=args.statement,
                rationale=args.rationale,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                supersedes=args.supersedes,
                author=args.author,
                timestamp=args.timestamp,
            )
            print(record["decision_id"])
            return 0
        if args.command == "add-task-event":
            record = add_task_event(
                paths,
                task_id=args.task_id,
                title=args.title,
                status=args.status,
                summary=args.summary,
                next_actions=args.next_action,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
            print(record["event_id"])
            return 0
        if args.command == "refresh-handoff":
            output_path = refresh_handoff_summary(paths, recent_limit=args.recent)
            if args.print_path:
                print(output_path)
            return 0
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
