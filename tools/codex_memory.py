#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path

SCHEMA_VERSION = "codex-memory-v2"
DEFAULT_REPO_ROOT = Path(__file__).resolve().parent.parent
EXPECTED_SUBSYSTEMS = (
    "assets",
    "mbn_corpus",
    "phase0_baseline",
    "scene_decode",
    "life_scripts",
    "backgrounds",
    "intelligence",
    "platform_windows",
    "platform_linux",
    "architecture",
)
MARKDOWN_SPECS = {
    "README.md": (("Workflow", "Commands", "Write Rules", "Budgets"), None),
    "project_brief.md": (
        ("Purpose", "Repo Map", "Canonical Sources", "Invariants", "Non-Goals"),
        2048,
    ),
    "current_focus.md": (
        (
            "Current Priorities",
            "Active Streams",
            "Blocked Items",
            "Next Actions",
            "Relevant Subsystem Packs",
        ),
        3072,
    ),
}
INDEX_SECTIONS = ("Pack List", "Path Mapping Rules")
SUBSYSTEM_SECTIONS = (
    "Purpose",
    "Invariants",
    "Current Parity Status",
    "Known Traps",
    "Canonical Entry Points",
    "Important Files",
    "Test / Probe Commands",
    "Open Unknowns",
)
SUBSYSTEM_BUDGET = 4096
HISTORY_FILES = (
    "policies.jsonl",
    "subsystem_facts.jsonl",
    "investigations.jsonl",
    "compat_events.jsonl",
    "task_events.jsonl",
)
CONTEXT_EXCLUDED_PATH_PREFIXES = ("sidequest/", "LM_TASKS/")
CONTEXT_EXCLUDED_TASK_STREAMS = {"prompt-refresh", "windows-debug-workflow"}
CONTEXT_EXCLUDED_TASK_STREAM_PREFIXES = ("lm-",)
CONTEXT_EXCLUDED_TASK_STATUSES = {"planned", "in_progress"}
OBSOLETE_PATHS = (
    "docs/codex_memory/handoff.md",
    "docs/codex_memory/decision_log.jsonl",
    "docs/codex_memory/task_log.jsonl",
    "work/codex_memory",
)
STATUSES = {
    "policies": {"accepted", "active", "superseded", "rejected"},
    "subsystem_facts": {"current", "provisional", "superseded", "rejected"},
    "investigations": {"open", "blocked", "resolved", "rejected"},
    "compat_events": {"active", "retired", "removed"},
    "task_events": {"planned", "in_progress", "blocked", "completed", "cancelled"},
}
ID_FIELDS = {
    "policies": ("topic", "statement"),
    "subsystem_facts": ("subsystem", "fact"),
    "investigations": ("subsystem", "question"),
    "compat_events": ("subsystem", "title"),
    "task_events": ("stream", "summary"),
}
PREFIXES = {
    "policies": "policy",
    "subsystem_facts": "fact",
    "investigations": "investigation",
    "compat_events": "compat",
    "task_events": "task",
}
FIELD_RULES = {
    "policies": {
        "required": ("status", "topic", "statement", "rationale", "supersedes"),
        "short": ("topic", "statement"),
        "long": ("rationale",),
        "list": ("supersedes",),
    },
    "subsystem_facts": {
        "required": ("subsystem", "status", "fact", "rationale", "supersedes"),
        "short": ("fact",),
        "long": ("rationale",),
        "list": ("supersedes",),
    },
    "investigations": {
        "required": (
            "subsystem",
            "status",
            "question",
            "current_best_answer",
            "confidence",
            "next_probe",
        ),
        "short": ("question", "next_probe"),
        "long": ("current_best_answer",),
        "list": (),
    },
    "compat_events": {
        "required": ("subsystem", "status", "title", "summary"),
        "short": ("title", "summary"),
        "long": (),
        "list": (),
    },
    "task_events": {
        "required": ("stream", "status", "summary", "next_actions"),
        "short": ("stream", "summary"),
        "long": (),
        "list": ("next_actions",),
    },
}
COMMON_FIELDS = (
    "schema_version",
    "record_id",
    "timestamp_utc",
    "author",
    "affected_paths",
    "evidence_refs",
)
HISTORY_MODES = ("recent", "relevant")
LESSON_PREFIXES = ("fact", "trap", "decision", "evidence", "policy")
LESSON_STATUSES = ("active", "draft", "superseded", "rejected")
LESSON_CONFIDENCES = ("low", "medium", "high")
LESSON_REQUIRED_METADATA = ("Status", "Confidence", "Last verified")
LESSON_OPTIONAL_METADATA = (
    "Tags",
    "Related tests",
    "Related files",
    "Evidence refs",
    "Supersedes",
    "Superseded by",
)
GENERATED_MARKER = "GENERATED FILE. DO NOT EDIT."
DEFAULT_STALE_DAYS = 30
DEFAULT_BRIEFING_EVENTS = 5
DEFAULT_BRIEFING_MAX_BYTES = 12000
DEFAULT_BRIEFING_MAX_LESSONS = 8
DEFAULT_BRIEFING_MAX_ISSUES = 12
ARCHITECTURE_DOC_CHURN_PATHS = frozenset(
    {
        "docs/PROMPT.md",
        "docs/codex_memory/current_focus.md",
        "docs/codex_memory/subsystems/architecture.md",
        "ISSUES.md",
    }
)
TOKEN_PATTERN = re.compile(r"[a-z0-9]+")


@dataclass(frozen=True)
class MemoryPaths:
    repo_root: Path
    docs_dir: Path
    subsystem_dir: Path

    @classmethod
    def defaults(cls, repo_root: Path = DEFAULT_REPO_ROOT) -> "MemoryPaths":
        repo_root = repo_root.resolve()
        docs_dir = repo_root / "docs" / "codex_memory"
        return cls(
            repo_root=repo_root,
            docs_dir=docs_dir,
            subsystem_dir=docs_dir / "subsystems",
        )

    def history_path(self, filename: str) -> Path:
        return self.docs_dir / filename

    def subsystem_path(self, name: str) -> Path:
        return self.subsystem_dir / f"{name}.md"

    @property
    def generated_dir(self) -> Path:
        return self.docs_dir / "generated"

    @property
    def lessons_path(self) -> Path:
        return self.docs_dir / "lessons.md"


@dataclass(frozen=True)
class Rule:
    subsystem: str
    path: str

    def is_prefix(self) -> bool:
        return self.path.endswith("/")

    def matches(self, repo_path: str) -> bool:
        return (
            repo_path.startswith(self.path)
            if self.is_prefix()
            else repo_path == self.path
        )


@dataclass(frozen=True)
class ValidatedMemoryData:
    paths: MemoryPaths
    doc_texts: dict[str, str]
    subsystem_texts: dict[str, str]
    pack_names: tuple[str, ...]
    rules: tuple[Rule, ...]
    focus_subsystems: tuple[str, ...]
    history_rows: dict[str, tuple[tuple[int, dict], ...]]


@dataclass(frozen=True)
class HistoryEntry:
    kind: str
    record: dict
    timestamp_utc: str
    rendered_line: str
    record_text: str
    subsystem: str | None
    affected_paths: tuple[str, ...]
    evidence_refs: tuple[str, ...]
    mapped_subsystems: frozenset[str]
    text_tokens: frozenset[str]
    path_tokens: frozenset[str]
    excluded_by_default: bool


@dataclass(frozen=True)
class Lesson:
    id: str
    type: str
    status: str
    confidence: str
    last_verified: str
    tags: tuple[str, ...]
    related_tests: tuple[str, ...]
    related_files: tuple[str, ...]
    evidence_refs: tuple[str, ...]
    supersedes: tuple[str, ...]
    superseded_by: tuple[str, ...]
    heading: str
    body: str
    text: str


@dataclass(frozen=True)
class MemorySnapshot:
    paths: MemoryPaths
    pack_names: tuple[str, ...]
    rules: tuple[Rule, ...]
    focus_subsystems: tuple[str, ...]
    project_brief: str
    current_focus: str
    subsystem_docs: dict[str, str]
    history_entries: tuple[HistoryEntry, ...]
    exact_affected_path_index: dict[str, tuple[int, ...]]
    exact_evidence_ref_index: dict[str, tuple[int, ...]]
    path_prefix_index: dict[str, tuple[int, ...]]
    evidence_prefix_index: dict[str, tuple[int, ...]]
    subsystem_index: dict[str, tuple[int, ...]]
    inferred_subsystem_index: dict[str, tuple[int, ...]]


def parse_timestamp(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"invalid ISO timestamp: {value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp must include timezone: {value}")
    return (
        parsed.astimezone(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def utc_now(value: str | None) -> str:
    return (
        parse_timestamp(value)
        if value
        else datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def stable_hash(payload) -> str:
    text = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def source_hash(payload) -> str:
    return "sha256:" + stable_hash(payload)


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(item) for item in argv)


def make_id(kind: str, timestamp_utc: str, stable_fields: dict[str, str]) -> str:
    compact = timestamp_utc.replace("-", "").replace(":", "").replace("+00:00", "Z")
    return f"{PREFIXES[kind]}-{compact}-{stable_hash(stable_fields)[:10]}"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def read_optional_text(path: Path) -> str | None:
    if not path.exists():
        return None
    return read_text(path)


def normalize_text(value: str, field_name: str, max_len: int = 240) -> str:
    value = value.strip()
    if not value:
        raise ValueError(f"{field_name} must be a non-empty string")
    if len(value) > max_len:
        raise ValueError(f"{field_name} exceeds {max_len} characters")
    return value


def normalize_path(value: str) -> str:
    value = value.strip().replace("\\", "/")
    had_trailing_slash = value.endswith("/")
    if not value:
        raise ValueError("path values must not be empty")
    path = Path(value)
    if path.is_absolute():
        raise ValueError(f"path must be repo-relative, not absolute: {value}")
    if any(part == ".." for part in path.parts):
        raise ValueError(f"path must stay inside repo: {value}")
    value = path.as_posix()
    return f"{value}/" if had_trailing_slash and not value.endswith("/") else value


def normalize_paths(values: list[str]) -> list[str]:
    result = []
    for value in values:
        result.append(normalize_path(value))
    return result


def normalize_list(values: list[str], field_name: str) -> list[str]:
    return [normalize_text(value, field_name) for value in values]


def sections(content: str) -> dict[str, str]:
    result: dict[str, list[str]] = {}
    current = None
    for line in content.splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            result[current] = []
        elif current is not None:
            result[current].append(line)
    return {name: "\n".join(lines).strip() for name, lines in result.items()}


def first_section_body(content: str, heading: str) -> str:
    marker = f"## {heading}"
    if marker not in content:
        return ""
    lines = content.split(marker, 1)[1].splitlines()[1:]
    result = []
    for line in lines:
        if line.startswith("## "):
            break
        result.append(line)
    return "\n".join(result).strip()


def compact_excerpt(text: str, max_chars: int) -> str:
    normalized = "\n".join(line.rstrip() for line in text.strip().splitlines())
    if len(normalized) <= max_chars:
        return normalized
    return normalized[: max_chars - 15].rstrip() + "\n\n[excerpt trimmed]"


def validate_markdown_content(
    path: Path, content: str | None, required: tuple[str, ...], budget: int | None
) -> list[str]:
    if content is None:
        return [f"missing file: {path}"]
    errors = [] if content.startswith("# ") else [f"{path}: missing top-level heading"]
    parsed = sections(content)
    for name in required:
        if name not in parsed or not parsed[name]:
            errors.append(f"{path}: missing or empty ## {name}")
    if budget is not None and len(content.encode("utf-8")) > budget:
        errors.append(f"{path}: exceeds {budget} byte budget")
    return errors


def split_csv_metadata(value: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in value.split(",") if item.strip())


def parse_lessons(content: str) -> tuple[list[Lesson], list[str]]:
    if content.strip() == "":
        return [], []
    errors = [] if content.lstrip().startswith("# ") else [
        "lessons.md: missing top-level heading"
    ]
    lesson_blocks: list[tuple[int, str, list[str]]] = []
    current_line = 0
    current_heading: str | None = None
    current_lines: list[str] = []
    for line_no, line in enumerate(content.splitlines(), start=1):
        if line.startswith("### "):
            if current_heading is not None:
                lesson_blocks.append((current_line, current_heading, current_lines))
            current_line = line_no
            current_heading = line[4:].strip()
            current_lines = []
        elif current_heading is not None:
            current_lines.append(line)
    if current_heading is not None:
        lesson_blocks.append((current_line, current_heading, current_lines))

    lessons: list[Lesson] = []
    seen_ids: set[str] = set()
    for line_no, heading, raw_lines in lesson_blocks:
        lesson_errors: list[str] = []
        lesson_id = heading
        match = re.fullmatch(
            rf"({'|'.join(LESSON_PREFIXES)})\.[a-z0-9][a-z0-9._-]*", lesson_id
        )
        if not match:
            lesson_errors.append(
                f"lessons.md:{line_no}: lesson heading must be a stable id with one of these prefixes: {', '.join(prefix + '.' for prefix in LESSON_PREFIXES)}"
            )
            errors.extend(lesson_errors)
            continue
        if lesson_id in seen_ids:
            lesson_errors.append(f"lessons.md:{line_no}: duplicate lesson id {lesson_id}")
        else:
            seen_ids.add(lesson_id)

        metadata: dict[str, str] = {}
        body_start = 0
        for index, raw in enumerate(raw_lines):
            line = raw.strip()
            if not line:
                continue
            meta_match = re.fullmatch(r"([A-Za-z][A-Za-z ]+):\s*(.*)", line)
            if not meta_match:
                body_start = index
                break
            key, value = meta_match.groups()
            if key not in LESSON_REQUIRED_METADATA + LESSON_OPTIONAL_METADATA:
                lesson_errors.append(f"lessons.md:{line_no + index}: unsupported metadata field {key}")
            if key in metadata:
                lesson_errors.append(f"lessons.md:{line_no + index}: duplicate metadata field {key}")
            metadata[key] = value.strip()
            body_start = index + 1

        for key in LESSON_REQUIRED_METADATA:
            if not metadata.get(key):
                lesson_errors.append(f"lessons.md:{line_no}: missing required metadata {key}:")
        status = metadata.get("Status", "")
        if status and status not in LESSON_STATUSES:
            lesson_errors.append(
                f"lessons.md:{line_no}: Status must be one of {', '.join(LESSON_STATUSES)}"
            )
        confidence = metadata.get("Confidence", "")
        if confidence and confidence not in LESSON_CONFIDENCES:
            lesson_errors.append(
                f"lessons.md:{line_no}: Confidence must be one of {', '.join(LESSON_CONFIDENCES)}"
            )
        last_verified = metadata.get("Last verified", "")
        if last_verified:
            try:
                date.fromisoformat(last_verified)
            except ValueError:
                lesson_errors.append(
                    f"lessons.md:{line_no}: Last verified must parse as YYYY-MM-DD"
                )

        body = "\n".join(raw_lines[body_start:]).strip()
        if not body:
            lesson_errors.append(f"lessons.md:{line_no}: lesson body must not be empty")
        if "example" in lesson_id.lower() or "should be removed" in body.lower():
            lesson_errors.append(f"lessons.md:{line_no}: placeholder/example lesson content is not allowed")

        if not any(
            metadata.get(key)
            for key in ("Related tests", "Related files", "Evidence refs", "Supersedes")
        ):
            lesson_errors.append(
                f"lessons.md:{line_no}: lesson needs provenance via Related tests:, Related files:, Evidence refs:, or Supersedes:"
            )

        if lesson_errors:
            errors.extend(lesson_errors)
        else:
            lessons.append(
                Lesson(
                    id=lesson_id,
                    type=match.group(1),
                    status=status,
                    confidence=confidence,
                    last_verified=last_verified,
                    tags=split_csv_metadata(metadata.get("Tags", "")),
                    related_tests=split_csv_metadata(metadata.get("Related tests", "")),
                    related_files=split_csv_metadata(metadata.get("Related files", "")),
                    evidence_refs=split_csv_metadata(metadata.get("Evidence refs", "")),
                    supersedes=split_csv_metadata(metadata.get("Supersedes", "")),
                    superseded_by=split_csv_metadata(metadata.get("Superseded by", "")),
                    heading=heading,
                    body=body,
                    text="\n".join(raw_lines).strip(),
                )
            )
    return lessons, errors


def validate_lessons(paths: MemoryPaths) -> tuple[list[Lesson], list[str]]:
    content = read_optional_text(paths.lessons_path)
    if content is None:
        return [], [f"missing file: {paths.lessons_path}"]
    lessons, errors = parse_lessons(content)
    return lessons, [error.replace("lessons.md", str(paths.lessons_path)) for error in errors]


def parse_named_bullets(body: str, label: str) -> dict[str, str]:
    parsed = {}
    rx = re.compile(r"^- `([a-z0-9_]+)`: (.+)$")
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        match = rx.match(line)
        if not match:
            raise ValueError(f"{label}: unsupported line format: {raw}")
        name, value = match.groups()
        if name in parsed:
            raise ValueError(f"{label}: duplicate entry for {name}")
        parsed[name] = value.strip()
    return parsed


def load_index_from_text(index_text: str) -> tuple[list[str], list[Rule]]:
    parsed = sections(index_text)
    packs = parse_named_bullets(parsed["Pack List"], "Pack List")
    mapping = parse_named_bullets(parsed["Path Mapping Rules"], "Path Mapping Rules")
    rules = []
    for subsystem, body in mapping.items():
        if subsystem not in packs:
            raise ValueError(f"Path Mapping Rules: unknown subsystem {subsystem}")
        for token in re.findall(r"`([^`]+)`", body):
            token = token.strip()
            if not token:
                raise ValueError("Path Mapping Rules: empty mapping token")
            token = token.replace("\\", "/")
            if Path(token).is_absolute() or ".." in Path(token).parts:
                raise ValueError(f"Path Mapping Rules: invalid repo path {token}")
            rules.append(Rule(subsystem, token))
    return list(packs.keys()), rules


def load_index(paths: MemoryPaths) -> tuple[list[str], list[Rule]]:
    return load_index_from_text(read_text(paths.subsystem_dir / "INDEX.md"))


def rule_overlap(left: Rule, right: Rule) -> bool:
    if left.subsystem == right.subsystem:
        return False
    if left.path == right.path:
        return True
    if left.is_prefix() and right.is_prefix():
        return left.path.startswith(right.path) or right.path.startswith(left.path)
    if left.is_prefix():
        return right.path.startswith(left.path)
    if right.is_prefix():
        return left.path.startswith(right.path)
    return False


def resolve_subsystems(
    repo_path: str, rules: list[Rule] | tuple[Rule, ...]
) -> list[str]:
    repo_path = normalize_path(repo_path)
    return sorted({rule.subsystem for rule in rules if rule.matches(repo_path)})


def load_jsonl(path: Path) -> list[tuple[int, dict]]:
    if not path.exists():
        raise ValueError(f"missing file: {path}")
    rows = []
    with path.open(encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid JSON: {exc.msg}") from exc
            if not isinstance(payload, dict):
                raise ValueError(f"{path}:{line_no}: record must be an object")
            rows.append((line_no, payload))
    return rows


def non_empty_jsonl_lines(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if line.strip()]


def git_head_text(paths: MemoryPaths, repo_relative_path: str) -> str | None:
    git_dir = paths.repo_root / ".git"
    if not git_dir.exists():
        return None
    probe = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=paths.repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if probe.returncode != 0 or probe.stdout.strip() != "true":
        return None
    result = subprocess.run(
        ["git", "show", f"HEAD:{repo_relative_path}"],
        cwd=paths.repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def validate_append_only_history_file(paths: MemoryPaths, filename: str) -> list[str]:
    path = paths.history_path(filename)
    repo_relative_path = path.relative_to(paths.repo_root).as_posix()
    head_text = git_head_text(paths, repo_relative_path)
    if head_text is None:
        return []

    head_lines = non_empty_jsonl_lines(head_text)
    current_text = read_text(path)
    current_lines = non_empty_jsonl_lines(current_text)
    mismatch_index = None

    for index, head_line in enumerate(head_lines):
        if index >= len(current_lines) or current_lines[index] != head_line:
            mismatch_index = index
            break

    if mismatch_index is None:
        return []

    return [
        f"{path}:{mismatch_index + 1}: JSONL durable history must stay append-only relative to HEAD"
    ]


def validate_record(
    kind: str,
    record: dict,
    path: Path,
    line_no: int,
    subsystems: set[str],
    *,
    enforce_canonical_id: bool = True,
    enforce_text_limits: bool = True,
) -> list[str]:
    errors = []
    for field in COMMON_FIELDS + FIELD_RULES[kind]["required"]:
        if field not in record:
            errors.append(f"{path}:{line_no}: missing field {field}")
    if errors:
        return errors
    if record["schema_version"] != SCHEMA_VERSION:
        errors.append(
            f"{path}:{line_no}: unsupported schema_version {record['schema_version']}"
        )
    try:
        parse_timestamp(record["timestamp_utc"])
    except ValueError as exc:
        errors.append(f"{path}:{line_no}: {exc}")
    for field in ("author",):
        try:
            normalize_text(record[field], field, 80)
        except ValueError as exc:
            errors.append(f"{path}:{line_no}: {exc}")
    for field in ("affected_paths", "evidence_refs"):
        if not isinstance(record[field], list):
            errors.append(f"{path}:{line_no}: {field} must be a list")
            continue
        for item in record[field]:
            if not isinstance(item, str):
                errors.append(f"{path}:{line_no}: {field} must contain only strings")
                continue
            try:
                normalize_path(item)
            except ValueError as exc:
                errors.append(f"{path}:{line_no}: {exc}")
    for field in FIELD_RULES[kind]["short"]:
        try:
            normalize_text(record[field], field, 240 if enforce_text_limits else 10000)
        except ValueError as exc:
            errors.append(f"{path}:{line_no}: {exc}")
    for field in FIELD_RULES[kind]["long"]:
        try:
            normalize_text(record[field], field, 600 if enforce_text_limits else 10000)
        except ValueError as exc:
            errors.append(f"{path}:{line_no}: {exc}")
    for field in FIELD_RULES[kind]["list"]:
        if not isinstance(record[field], list):
            errors.append(f"{path}:{line_no}: {field} must be a list")
            continue
        for item in record[field]:
            if not isinstance(item, str):
                errors.append(f"{path}:{line_no}: {field} must contain only strings")
                continue
            try:
                normalize_text(item, field, 240 if enforce_text_limits else 10000)
            except ValueError as exc:
                errors.append(f"{path}:{line_no}: {exc}")
    if record["status"] not in STATUSES[kind]:
        errors.append(
            f"{path}:{line_no}: unsupported {kind[:-1]} status {record['status']}"
        )
    if "subsystem" in record and record["subsystem"] not in subsystems:
        errors.append(f"{path}:{line_no}: unknown subsystem {record['subsystem']}")
    if kind == "investigations" and record["confidence"] not in {
        "low",
        "medium",
        "high",
    }:
        errors.append(
            f"{path}:{line_no}: unsupported confidence {record['confidence']}"
        )
    if enforce_canonical_id:
        stable_fields = {field: record[field] for field in ID_FIELDS[kind]}
        expected = make_id(kind, record["timestamp_utc"], stable_fields)
        if record["record_id"] != expected:
            errors.append(
                f"{path}:{line_no}: record_id does not match canonical form {expected}"
            )
    return errors


def parse_focus_subsystems_content(content: str) -> list[str]:
    body = sections(content)["Relevant Subsystem Packs"]
    result = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if not line.startswith("- "):
            raise ValueError(
                f"current_focus relevant subsystem line must be a bullet: {raw}"
            )
        name = line[2:].strip().strip("`")
        if not re.fullmatch(r"[a-z0-9_]+", name):
            raise ValueError(f"invalid subsystem name in current_focus: {name}")
        result.append(name)
    return result


def parse_focus_subsystems(paths: MemoryPaths) -> list[str]:
    return parse_focus_subsystems_content(
        read_text(paths.docs_dir / "current_focus.md")
    )


def lesson_index_payload(paths: MemoryPaths, lessons: list[Lesson]) -> dict:
    lessons_text = read_text(paths.lessons_path)
    return {
        "generated_marker": GENERATED_MARKER,
        "generated_by": "python tools/codex_memory.py index",
        "source_hash": source_hash(
            {
                "lessons.md": lessons_text,
            }
        ),
        "lessons": [
            {
                "id": lesson.id,
                "type": lesson.type,
                "status": lesson.status,
                "confidence": lesson.confidence,
                "last_verified": lesson.last_verified,
                "tags": list(lesson.tags),
                "heading": lesson.heading,
            }
            for lesson in sorted(lessons, key=lambda item: item.id)
        ],
    }


def render_lesson_index(paths: MemoryPaths, lessons: list[Lesson]) -> str:
    payload = lesson_index_payload(paths, lessons)
    return json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True) + "\n"


def generated_header(command: str, hash_value: str) -> str:
    return "\n".join(
        [
            "<!--",
            GENERATED_MARKER,
            "",
            "Generated by:",
            f"  {command}",
            "",
            "Source hash:",
            f"  {hash_value}",
            "-->",
        ]
    )


def stale_report_source_hash(paths: MemoryPaths, days: int, as_of: str) -> str:
    return source_hash(
        {"as_of": as_of, "days": days, "lessons.md": read_text(paths.lessons_path)}
    )


def render_stale_report(paths: MemoryPaths, lessons: list[Lesson], days: int, as_of: str) -> str:
    today = date.fromisoformat(as_of)
    stale: list[Lesson] = []
    drafts: list[Lesson] = []
    missing_provenance: list[Lesson] = []
    missing_related_files: list[tuple[Lesson, str]] = []
    for lesson in sorted(lessons, key=lambda item: item.id):
        if lesson.status == "draft":
            drafts.append(lesson)
        if lesson.status == "active":
            verified = date.fromisoformat(lesson.last_verified)
            if (today - verified).days > days:
                stale.append(lesson)
        if not (
            lesson.related_tests
            or lesson.related_files
            or lesson.evidence_refs
            or lesson.supersedes
        ):
            missing_provenance.append(lesson)
        for related in (*lesson.related_tests, *lesson.related_files, *lesson.evidence_refs):
            if related.startswith("http://") or related.startswith("https://"):
                continue
            try:
                normalized = normalize_path(related)
            except ValueError:
                continue
            if not (paths.repo_root / normalized).exists():
                missing_related_files.append((lesson, related))

    command = f"python tools/codex_memory.py stale-scan --days {days} --as-of {as_of}"
    parts = [
        "# Lessons Stale Report",
        "",
        generated_header(command, stale_report_source_hash(paths, days, as_of)),
        "",
        f"As of: {as_of}",
        f"Threshold: {days} days",
        "",
        "## Active Lessons Needing Review",
        "",
    ]
    if stale:
        parts.extend(
            f"- `{lesson.id}` last verified {lesson.last_verified}"
            for lesson in stale
        )
    else:
        parts.append("- None.")
    parts.extend(["", "## Draft Lessons", ""])
    if drafts:
        parts.extend(f"- `{lesson.id}`" for lesson in drafts)
    else:
        parts.append("- None.")
    parts.extend(["", "## Missing Provenance", ""])
    if missing_provenance:
        parts.extend(f"- `{lesson.id}`" for lesson in missing_provenance)
    else:
        parts.append("- None.")
    parts.extend(["", "## Missing Related Paths", ""])
    if missing_related_files:
        parts.extend(
            f"- `{lesson.id}` references `{related}`"
            for lesson, related in missing_related_files
        )
    else:
        parts.append("- None.")
    return "\n".join(parts).rstrip() + "\n"


def task_events_tail(paths: MemoryPaths, count: int) -> list[dict]:
    rows = load_jsonl(paths.history_path("task_events.jsonl"))
    return [record for _, record in rows[-count:]]


def briefing_source_payload(
    paths: MemoryPaths,
    task: str,
    event_count: int,
    repo_paths: list[str],
    subsystem_names: list[str],
    tags: list[str],
    lesson_ids: list[str],
    max_bytes: int,
) -> dict:
    source_files = [
        "docs/codex_memory/project_brief.md",
        "docs/codex_memory/current_focus.md",
        "docs/codex_memory/lessons.md",
        "docs/codex_memory/task_events.jsonl",
        "ISSUES.md",
    ]
    return {
        "task": task,
        "event_count": event_count,
        "repo_paths": repo_paths,
        "subsystems": subsystem_names,
        "tags": tags,
        "lesson_ids": lesson_ids,
        "max_bytes": max_bytes,
        "sources": {
            name: read_optional_text(paths.repo_root / name) or ""
            for name in source_files
        },
    }


def task_keywords(task: str) -> frozenset[str]:
    return frozenset(token for token in TOKEN_PATTERN.findall(task.lower()) if len(token) > 2)


def normalize_query_values(values: list[str], field_name: str) -> list[str]:
    result = []
    for value in values:
        normalized = normalize_text(value, field_name, 240)
        if normalized not in result:
            result.append(normalized)
    return result


def selected_subsystems_for_briefing(
    snapshot: MemorySnapshot, subsystem_names: list[str], repo_paths: list[str]
) -> list[str]:
    if not subsystem_names and not repo_paths:
        return []
    return select_subsystems(snapshot, subsystem_names, repo_paths)


def lesson_relevance(
    lesson: Lesson,
    task_tokens: frozenset[str],
    repo_paths: list[str],
    subsystem_names: list[str],
    tags: list[str],
    lesson_ids: list[str],
) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    if lesson.id in lesson_ids:
        score += 100
        reasons.append(f"explicit lesson `{lesson.id}`")
    tag_matches = sorted(set(tags) & set(lesson.tags))
    if tag_matches:
        score += 80 + 5 * len(tag_matches)
        reasons.append("tag match " + ", ".join(f"`{tag}`" for tag in tag_matches))
    for repo_path in repo_paths:
        related = (*lesson.related_files, *lesson.related_tests, *lesson.evidence_refs)
        if repo_path in related:
            score += 70
            reasons.append(f"exact path match `{repo_path}`")
            break
        if any(repo_path.startswith(path.rstrip("/")) or path.rstrip("/").startswith(repo_path) for path in related):
            score += 45
            reasons.append(f"path overlap `{repo_path}`")
            break
    subsystem_matches = sorted(set(subsystem_names) & set(lesson.tags))
    if subsystem_matches:
        score += 35
        reasons.append(
            "subsystem/tag match " + ", ".join(f"`{name}`" for name in subsystem_matches)
        )
    id_tokens = tokenize(lesson.id)
    tag_tokens = tokenize(" ".join(lesson.tags))
    body_tokens = tokenize(lesson.body)
    id_overlap = task_tokens & id_tokens
    tag_overlap = task_tokens & tag_tokens
    body_overlap = task_tokens & body_tokens
    if id_overlap:
        score += 40 + 3 * len(id_overlap)
        reasons.append("id token match " + ", ".join(f"`{token}`" for token in sorted(id_overlap)))
    if tag_overlap:
        score += 35 + 3 * len(tag_overlap)
        reasons.append("tag token match " + ", ".join(f"`{token}`" for token in sorted(tag_overlap)))
    if body_overlap:
        score += min(30, 8 + 2 * len(body_overlap))
        reasons.append("body token match " + ", ".join(f"`{token}`" for token in sorted(body_overlap)[:5]))
    canonical_tokens = {"global", "canonical", "hard", "cut"}
    if lesson.type in {"decision", "policy"} and canonical_tokens & (id_tokens | tag_tokens | body_tokens):
        score += 20
        reasons.append("global/canonical decision")
    return score, reasons


def matching_lessons(
    lessons: list[Lesson],
    task: str,
    repo_paths: list[str],
    subsystem_names: list[str],
    tags: list[str],
    lesson_ids: list[str],
    max_lessons: int = DEFAULT_BRIEFING_MAX_LESSONS,
) -> list[tuple[Lesson, list[str]]]:
    keywords = task_keywords(task)
    explicit = bool(keywords or repo_paths or subsystem_names or tags or lesson_ids)
    selected: list[tuple[int, Lesson, list[str]]] = []
    for lesson in sorted(lessons, key=lambda item: item.id):
        if lesson.status != "active":
            continue
        score, reasons = lesson_relevance(
            lesson, keywords, repo_paths, subsystem_names, tags, lesson_ids
        )
        if score > 0:
            selected.append((score, lesson, reasons))
        elif not explicit and lesson.confidence == "high":
            selected.append((1, lesson, ["default high-confidence active lesson"]))
    selected.sort(key=lambda item: (-item[0], item[1].id))
    return [(lesson, reasons) for _, lesson, reasons in selected[:max_lessons]]


def matching_issue_lines(
    issues_text: str,
    task: str,
    repo_paths: list[str],
    subsystem_names: list[str],
    tags: list[str],
) -> list[tuple[str, list[str]]]:
    keywords = task_keywords(task)
    query_tokens = set(keywords)
    for value in [*repo_paths, *subsystem_names, *tags]:
        query_tokens.update(task_keywords(value))
    if not query_tokens:
        return []
    result: list[tuple[int, str, list[str]]] = []
    for line in issues_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        overlap = query_tokens & set(tokenize(stripped))
        if overlap:
            result.append(
                (
                    len(overlap),
                    stripped,
                    ["token match " + ", ".join(f"`{token}`" for token in sorted(overlap)[:5])],
                )
            )
    result.sort(key=lambda item: (-item[0], item[1]))
    return [(line, reasons) for _, line, reasons in result[:DEFAULT_BRIEFING_MAX_ISSUES]]


def history_record_tokens(record: dict) -> frozenset[str]:
    return tokenize(json.dumps(record, ensure_ascii=True, sort_keys=True))


def matching_task_events(
    paths: MemoryPaths,
    snapshot: MemorySnapshot,
    task: str,
    event_count: int,
    repo_paths: list[str],
    subsystem_names: list[str],
) -> list[tuple[dict, list[str]]]:
    rows = load_jsonl(paths.history_path("task_events.jsonl"))
    if not (task or repo_paths or subsystem_names):
        return [(record, ["recent task event"]) for _, record in rows[-event_count:]]
    selected_subsystems = set(subsystem_names)
    query_tokens = set(task_keywords(task))
    scored: list[tuple[int, int, dict, list[str]]] = []
    for ordinal, (_, record) in enumerate(rows):
        score = 0
        reasons: list[str] = []
        affected = tuple(normalize_path(path) for path in record.get("affected_paths", []))
        evidence = tuple(normalize_path(path) for path in record.get("evidence_refs", []))
        for repo_path in repo_paths:
            if repo_path in affected:
                score += 80
                reasons.append(f"affected path `{repo_path}`")
            if repo_path in evidence:
                score += 70
                reasons.append(f"evidence path `{repo_path}`")
            if any(repo_path.startswith(path.rstrip("/")) or path.rstrip("/").startswith(repo_path) for path in (*affected, *evidence)):
                score += 35
                reasons.append(f"path overlap `{repo_path}`")
        mapped = set()
        for path in (*affected, *evidence):
            mapped.update(resolve_subsystems(path, snapshot.rules))
        subsystem_overlap = selected_subsystems & mapped
        if subsystem_overlap:
            score += 30 + 5 * len(subsystem_overlap)
            reasons.append(
                "subsystem match " + ", ".join(f"`{name}`" for name in sorted(subsystem_overlap))
            )
        token_overlap = query_tokens & set(history_record_tokens(record))
        if token_overlap:
            score += min(25, 5 + 2 * len(token_overlap))
            reasons.append(
                "task token match " + ", ".join(f"`{token}`" for token in sorted(token_overlap)[:5])
            )
        if score:
            scored.append((score, ordinal, record, reasons))
    scored.sort(key=lambda item: (-item[0], -item[1]))
    return [(record, reasons) for _, _, record, reasons in scored[:event_count]]


def retrieval_warnings(
    task: str,
    selected_lessons: list[tuple[Lesson, list[str]]],
    issue_lines: list[tuple[str, list[str]]],
    recent_events: list[tuple[dict, list[str]]],
) -> list[str]:
    matched_tokens: set[str] = set()
    for lesson, _ in selected_lessons:
        matched_tokens.update(tokenize(lesson.id))
        matched_tokens.update(tokenize(" ".join(lesson.tags)))
        matched_tokens.update(tokenize(lesson.body))
    for line, _ in issue_lines:
        matched_tokens.update(tokenize(line))
    for record, _ in recent_events:
        matched_tokens.update(history_record_tokens(record))
    warnings = []
    for token in sorted(task_keywords(task) - matched_tokens):
        warnings.append(f"- No selected lesson, issue, or event matched `{token}`.")
    return warnings


def enforce_briefing_budget(text: str, max_bytes: int) -> str:
    encoded = text.encode("utf-8")
    if len(encoded) <= max_bytes:
        return text
    marker = "\n\n[briefing trimmed to byte budget]\n"
    allowance = max_bytes - len(marker.encode("utf-8"))
    if allowance <= 0:
        raise ValueError("--max-bytes is too small for the generated briefing marker")
    trimmed = encoded[:allowance].decode("utf-8", errors="ignore").rstrip()
    return trimmed + marker


def render_briefing(
    paths: MemoryPaths,
    lessons: list[Lesson],
    task: str,
    event_count: int,
    repo_paths: list[str] | None = None,
    subsystem_names: list[str] | None = None,
    tags: list[str] | None = None,
    lesson_ids: list[str] | None = None,
    max_bytes: int = DEFAULT_BRIEFING_MAX_BYTES,
) -> str:
    repo_paths = [normalize_path(path) for path in (repo_paths or [])]
    subsystem_names = normalize_query_values(subsystem_names or [], "subsystem")
    tags = normalize_query_values(tags or [], "tag")
    lesson_ids = normalize_query_values(lesson_ids or [], "lesson")
    snapshot = build_snapshot(paths, validate_generated=False)
    selected_subsystems = selected_subsystems_for_briefing(
        snapshot, subsystem_names, repo_paths
    )
    payload = briefing_source_payload(
        paths, task, event_count, repo_paths, selected_subsystems, tags, lesson_ids, max_bytes
    )
    project_brief = payload["sources"]["docs/codex_memory/project_brief.md"]
    current_focus = payload["sources"]["docs/codex_memory/current_focus.md"]
    issues = payload["sources"]["ISSUES.md"]
    source_hash_value = source_hash(payload)
    known_lessons = {lesson.id for lesson in lessons}
    unknown_lessons = [lesson_id for lesson_id in lesson_ids if lesson_id not in known_lessons]
    if unknown_lessons:
        raise ValueError(f"unknown lesson id(s): {', '.join(unknown_lessons)}")
    selected_lessons = matching_lessons(
        lessons, task, repo_paths, selected_subsystems, tags, lesson_ids
    )
    issue_lines = matching_issue_lines(issues, task, repo_paths, selected_subsystems, tags)
    recent_events = matching_task_events(
        paths, snapshot, task, event_count, repo_paths, selected_subsystems
    )
    warnings = retrieval_warnings(task, selected_lessons, issue_lines, recent_events)
    command_parts = ["python", "tools/codex_memory.py", "briefing", "--task", task]
    for repo_path in repo_paths:
        command_parts.extend(["--path", repo_path])
    for subsystem in subsystem_names:
        command_parts.extend(["--subsystem", subsystem])
    for tag in tags:
        command_parts.extend(["--tag", tag])
    for lesson_id in lesson_ids:
        command_parts.extend(["--lesson", lesson_id])
    if event_count != DEFAULT_BRIEFING_EVENTS:
        command_parts.extend(["--events", str(event_count)])
    if max_bytes != DEFAULT_BRIEFING_MAX_BYTES:
        command_parts.extend(["--max-bytes", str(max_bytes)])
    parts = [
        "# Generated Task Briefing",
        "",
        generated_header(
            shell_join(command_parts),
            source_hash_value,
        ),
        "",
        "## Task",
        "",
        task or "(no task provided)",
        "",
        "## Project Brief",
        "",
        compact_excerpt(project_brief, 1200),
        "",
        "## Current Focus",
        "",
        compact_excerpt(current_focus, 1800),
        "",
        "## Query",
        "",
        "- Paths: " + (", ".join(f"`{path}`" for path in repo_paths) if repo_paths else "none"),
        "- Subsystems: " + (", ".join(f"`{name}`" for name in selected_subsystems) if selected_subsystems else "none"),
        "- Tags: " + (", ".join(f"`{tag}`" for tag in tags) if tags else "none"),
        "- Lessons: " + (", ".join(f"`{lesson}`" for lesson in lesson_ids) if lesson_ids else "none"),
        "",
        "## Relevant Lessons",
        "",
    ]
    if selected_lessons:
        for lesson, reasons in selected_lessons:
            parts.extend(
                [
                    f"### {lesson.id}",
                    "",
                    f"Status: {lesson.status}",
                    f"Confidence: {lesson.confidence}",
                    f"Last verified: {lesson.last_verified}",
                    "Selected because: " + "; ".join(reasons),
                    "",
                    compact_excerpt(lesson.body, 700),
                    "",
                ]
            )
    else:
        parts.append("- None selected.")
    parts.extend(["", "## Relevant Open Issues", ""])
    if issue_lines:
        for line, reasons in issue_lines:
            parts.append(line)
            parts.append("  Selected because: " + "; ".join(reasons))
    else:
        parts.append("- None selected.")
    parts.extend(["", "## Recent Events", ""])
    if recent_events:
        for record, reasons in recent_events:
            parts.append(
                f"- {record.get('timestamp_utc', '')}: {record.get('stream', '')} - {record.get('summary', '')}"
            )
            parts.append("  Selected because: " + "; ".join(reasons))
    else:
        parts.append("- None.")
    parts.extend(["", "## Retrieval Warnings", ""])
    if warnings:
        parts.extend(warnings)
    else:
        parts.append("- None.")
    parts.extend(
        [
            "",
            "## Required Checks",
            "",
            "- Run `python tools/codex_memory.py validate`.",
            "- Run relevant project tests for touched areas.",
            "- If runtime/gameplay seams are widened, validate promotion packets.",
            "- Do not treat generated task briefing as canonical truth.",
        ]
    )
    return enforce_briefing_budget("\n".join(parts).rstrip() + "\n", max_bytes)


def parse_generated_command(content: str) -> str | None:
    match = re.search(r"Generated by:\n  (.+)\n", content)
    return match.group(1).strip() if match else None


def parse_generated_task(content: str) -> str:
    return first_section_body(content, "Task").strip()


def parse_briefing_generated_args(command: str) -> argparse.Namespace:
    prefix = "python tools/codex_memory.py "
    if not command.startswith(prefix):
        raise ValueError("briefing generated command has unsupported prefix")
    args = parse_args(shlex.split(command[len(prefix) :]))
    if args.command != "briefing":
        raise ValueError("briefing generated command must use briefing")
    return args


def validate_generated_files(paths: MemoryPaths, lessons: list[Lesson]) -> list[str]:
    errors: list[str] = []
    generated = paths.generated_dir
    if not generated.exists():
        return errors
    allowed = {"memory_index.json", "stale_report.md", "task_briefing.md"}
    for path in generated.iterdir():
        if path.name not in allowed:
            errors.append(f"{path}: unexpected generated file")
            continue
        content = read_text(path)
        if GENERATED_MARKER not in content:
            errors.append(f"{path}: missing generated-file marker")
            continue
        if path.name == "memory_index.json":
            expected = render_lesson_index(paths, lessons)
        elif path.name == "stale_report.md":
            command = parse_generated_command(content) or ""
            match = re.fullmatch(
                r"python tools/codex_memory.py stale-scan --days ([0-9]+) --as-of ([0-9]{4}-[0-9]{2}-[0-9]{2})",
                command,
            )
            if not match:
                errors.append(f"{path}: stale report generated command must include --days and --as-of")
                continue
            days = int(match.group(1))
            as_of = match.group(2)
            expected = render_stale_report(paths, lessons, days, as_of)
        else:
            try:
                args = parse_briefing_generated_args(parse_generated_command(content) or "")
                expected = render_briefing(
                    paths,
                    lessons,
                    args.task,
                    args.events,
                    args.path,
                    args.subsystem,
                    args.tag,
                    args.lesson,
                    args.max_bytes,
                )
            except ValueError as exc:
                errors.append(f"{path}: {exc}")
                continue
        if content != expected:
            errors.append(
                f"{path}: generated file is stale; regenerate it with the command in its generated header"
            )
    return errors


def load_validated_data(paths: MemoryPaths, *, validate_generated: bool = True) -> ValidatedMemoryData:
    errors = []
    for rel in OBSOLETE_PATHS:
        if (paths.repo_root / rel).exists():
            errors.append(f"obsolete v1 path still present: {paths.repo_root / rel}")

    doc_texts: dict[str, str | None] = {}
    for name, (required, budget) in MARKDOWN_SPECS.items():
        path = paths.docs_dir / name
        content = read_optional_text(path)
        doc_texts[name] = content
        errors.extend(validate_markdown_content(path, content, required, budget))

    lessons, lesson_errors = validate_lessons(paths)
    errors.extend(lesson_errors)

    index_path = paths.subsystem_dir / "INDEX.md"
    index_text = read_optional_text(index_path)
    errors.extend(
        validate_markdown_content(index_path, index_text, INDEX_SECTIONS, None)
    )

    subsystem_names = sorted(
        path.stem
        for path in paths.subsystem_dir.glob("*.md")
        if path.name != "INDEX.md"
    )
    subsystem_texts: dict[str, str | None] = {}
    subsystem_set = set(subsystem_names)
    expected_subsystems: set[str] = set(EXPECTED_SUBSYSTEMS)
    if subsystem_set != expected_subsystems:
        missing = sorted(expected_subsystems - subsystem_set)
        extra = sorted(subsystem_set - expected_subsystems)

        if missing:
            errors.append(
                f"{paths.subsystem_dir}: missing required subsystem packs: {', '.join(missing)}"
            )
        if extra:
            errors.append(
                f"{paths.subsystem_dir}: unexpected subsystem packs: {', '.join(extra)}"
            )
    for name in subsystem_names:
        path = paths.subsystem_path(name)
        content = read_optional_text(path)
        subsystem_texts[name] = content
        errors.extend(
            validate_markdown_content(
                path, content, SUBSYSTEM_SECTIONS, SUBSYSTEM_BUDGET
            )
        )

    pack_names: list[str] = []
    rules: list[Rule] = []
    if index_text is not None:
        try:
            pack_names, rules = load_index_from_text(index_text)
        except ValueError as exc:
            errors.append(str(exc))

    focus_subsystems: list[str] = []
    current_focus_text = doc_texts.get("current_focus.md")
    if current_focus_text is not None:
        try:
            focus_subsystems = parse_focus_subsystems_content(current_focus_text)
        except ValueError as exc:
            errors.append(f"{paths.docs_dir / 'current_focus.md'}: {exc}")

    if pack_names:
        if set(pack_names) != subsystem_set:
            errors.append(
                f"{paths.subsystem_dir / 'INDEX.md'}: pack list must match subsystem files exactly"
            )
        mapped_subsystems = {rule.subsystem for rule in rules}
        missing_mappings = sorted(subsystem_set - mapped_subsystems)
        if missing_mappings:
            errors.append(
                f"{paths.subsystem_dir / 'INDEX.md'}: missing path mappings for subsystem packs: {', '.join(missing_mappings)}"
            )
        for rule in rules:
            if not (paths.repo_root / rule.path.rstrip("/")).exists():
                errors.append(
                    f"{paths.subsystem_dir / 'INDEX.md'}: mapping target does not exist: {rule.path}"
                )
        for i, left in enumerate(rules):
            for right in rules[i + 1 :]:
                if rule_overlap(left, right):
                    errors.append(
                        f"{paths.subsystem_dir / 'INDEX.md'}: ambiguous mapping between {left.subsystem}:{left.path} and {right.subsystem}:{right.path}"
                    )
        for name in focus_subsystems:
            if name not in subsystem_set:
                errors.append(
                    f"{paths.docs_dir / 'current_focus.md'}: unknown subsystem in Relevant Subsystem Packs: {name}"
                )

    history_rows: dict[str, tuple[tuple[int, dict], ...]] = {}
    for filename in HISTORY_FILES:
        kind = filename.replace(".jsonl", "")
        try:
            rows = load_jsonl(paths.history_path(filename))
        except ValueError as exc:
            errors.append(str(exc))
            rows = []
        history_rows[kind] = tuple(rows)

    for kind, rows in history_rows.items():
        path = paths.history_path(f"{kind}.jsonl")
        repo_relative_path = path.relative_to(paths.repo_root).as_posix()
        head_text = git_head_text(paths, repo_relative_path)
        head_line_count = (
            len(non_empty_jsonl_lines(head_text)) if head_text is not None else 0
        )
        for index, (line_no, record) in enumerate(rows):
            errors.extend(
                validate_record(
                    kind,
                    record,
                    path,
                    line_no,
                    subsystem_set,
                    enforce_canonical_id=index >= head_line_count,
                    enforce_text_limits=index >= head_line_count,
                )
            )
        errors.extend(validate_append_only_history_file(paths, f"{kind}.jsonl"))

    if validate_generated and not lesson_errors:
        errors.extend(validate_generated_files(paths, lessons))

    if errors:
        raise ValueError("\n".join(errors))

    return ValidatedMemoryData(
        paths=paths,
        doc_texts={
            name: content for name, content in doc_texts.items() if content is not None
        },
        subsystem_texts={
            name: content
            for name, content in subsystem_texts.items()
            if content is not None
        },
        pack_names=tuple(pack_names),
        rules=tuple(rules),
        focus_subsystems=tuple(focus_subsystems),
        history_rows=history_rows,
    )


def validate_all(paths: MemoryPaths) -> list[str]:
    try:
        load_validated_data(paths)
    except ValueError as exc:
        return [line for line in str(exc).splitlines() if line]
    return []


def tokenize(value: str) -> frozenset[str]:
    return frozenset(TOKEN_PATTERN.findall(value.lower()))


def history_text(kind: str, record: dict) -> str:
    if kind == "policies":
        return f"{record['topic']}: {record['statement']} ({record['status']})"
    if kind == "subsystem_facts":
        return f"{record['subsystem']}: {record['fact']} ({record['status']})"
    if kind == "investigations":
        return f"{record['subsystem']}: {record['question']} ({record['status']}, {record['confidence']})"
    if kind == "compat_events":
        return f"{record['subsystem']}: {record['title']} ({record['status']})"
    return f"{record['stream']}: {record['summary']} ({record['status']})"


def exclude_from_default_context(kind: str, record: dict) -> bool:
    for field in ("affected_paths", "evidence_refs"):
        for value in record.get(field, []):
            normalized = normalize_path(value)
            if any(
                normalized.startswith(prefix)
                for prefix in CONTEXT_EXCLUDED_PATH_PREFIXES
            ):
                return True
    if kind != "task_events":
        return False
    if record.get("status") in CONTEXT_EXCLUDED_TASK_STATUSES:
        return True
    stream = record.get("stream", "")
    if stream in CONTEXT_EXCLUDED_TASK_STREAMS:
        return True
    return any(
        stream.startswith(prefix) for prefix in CONTEXT_EXCLUDED_TASK_STREAM_PREFIXES
    )


def history_superseded_ids(paths: MemoryPaths) -> set[str]:
    ids = set()
    validated = load_validated_data(paths)
    for rows in validated.history_rows.values():
        for _, record in rows:
            ids.update(record.get("supersedes", []))
    return ids


def build_history_entry(
    kind: str, record: dict, rules: tuple[Rule, ...]
) -> HistoryEntry:
    affected_paths = tuple(record.get("affected_paths", ()))
    evidence_refs = tuple(record.get("evidence_refs", ()))
    mapped_subsystems = set()
    for path in [*affected_paths, *evidence_refs]:
        mapped_subsystems.update(resolve_subsystems(path, rules))
    record_text = history_text(kind, record)
    rendered_line = f"- {record['timestamp_utc']} [{kind}] {record_text}"
    return HistoryEntry(
        kind=kind,
        record=record,
        timestamp_utc=record["timestamp_utc"],
        rendered_line=rendered_line,
        record_text=record_text,
        subsystem=record.get("subsystem"),
        affected_paths=affected_paths,
        evidence_refs=evidence_refs,
        mapped_subsystems=frozenset(mapped_subsystems),
        text_tokens=tokenize(record_text),
        path_tokens=tokenize(" ".join([*affected_paths, *evidence_refs])),
        excluded_by_default=exclude_from_default_context(kind, record),
    )


def build_snapshot(paths: MemoryPaths, *, validate_generated: bool = True) -> MemorySnapshot:
    validated = load_validated_data(paths, validate_generated=validate_generated)
    superseded_ids = set()
    for rows in validated.history_rows.values():
        for _, record in rows:
            superseded_ids.update(record.get("supersedes", []))

    history_entries: list[HistoryEntry] = []
    exact_affected_path_index: dict[str, list[int]] = defaultdict(list)
    exact_evidence_ref_index: dict[str, list[int]] = defaultdict(list)
    path_prefix_index: dict[str, list[int]] = defaultdict(list)
    evidence_prefix_index: dict[str, list[int]] = defaultdict(list)
    subsystem_index: dict[str, list[int]] = defaultdict(list)
    inferred_subsystem_index: dict[str, list[int]] = defaultdict(list)

    for filename in HISTORY_FILES:
        kind = filename.replace(".jsonl", "")
        for _, record in validated.history_rows[kind]:
            if record["record_id"] in superseded_ids:
                continue
            entry = build_history_entry(kind, record, validated.rules)
            index = len(history_entries)
            history_entries.append(entry)
            for path in entry.affected_paths:
                exact_affected_path_index[path].append(index)
                path_prefix_index[path].append(index)
            for path in entry.evidence_refs:
                exact_evidence_ref_index[path].append(index)
                evidence_prefix_index[path].append(index)
            if entry.subsystem is not None:
                subsystem_index[entry.subsystem].append(index)
            else:
                for subsystem in entry.mapped_subsystems:
                    inferred_subsystem_index[subsystem].append(index)

    return MemorySnapshot(
        paths=paths,
        pack_names=validated.pack_names,
        rules=validated.rules,
        focus_subsystems=validated.focus_subsystems,
        project_brief=validated.doc_texts["project_brief.md"].strip(),
        current_focus=validated.doc_texts["current_focus.md"].strip(),
        subsystem_docs={
            name: text.strip() for name, text in validated.subsystem_texts.items()
        },
        history_entries=tuple(history_entries),
        exact_affected_path_index={
            path: tuple(indices) for path, indices in exact_affected_path_index.items()
        },
        exact_evidence_ref_index={
            path: tuple(indices) for path, indices in exact_evidence_ref_index.items()
        },
        path_prefix_index={
            path: tuple(indices) for path, indices in path_prefix_index.items()
        },
        evidence_prefix_index={
            path: tuple(indices) for path, indices in evidence_prefix_index.items()
        },
        subsystem_index={
            name: tuple(indices) for name, indices in subsystem_index.items()
        },
        inferred_subsystem_index={
            name: tuple(indices) for name, indices in inferred_subsystem_index.items()
        },
    )


def ensure_snapshot(source: MemoryPaths | MemorySnapshot) -> MemorySnapshot:
    if isinstance(source, MemorySnapshot):
        return source
    return build_snapshot(source)


def select_subsystems(
    source: MemoryPaths | MemorySnapshot, names: list[str], repo_paths: list[str]
) -> list[str]:
    snapshot = ensure_snapshot(source)
    allowed = set(snapshot.pack_names)
    selected = []
    for name in names:
        name = normalize_text(name, "subsystem")
        if name not in allowed:
            raise ValueError(f"unknown subsystem: {name}")
        if name not in selected:
            selected.append(name)
    for repo_path in repo_paths:
        matches = resolve_subsystems(repo_path, snapshot.rules)
        if not matches:
            raise ValueError(f"no subsystem mapping for path: {repo_path}")
        if len(matches) > 1:
            raise ValueError(
                f"ambiguous subsystem mapping for path {repo_path}: {', '.join(matches)}"
            )
        if matches[0] not in selected:
            selected.append(matches[0])
    return selected


def candidate_history_indices(
    snapshot: MemorySnapshot, selected: set[str], repo_paths: list[str]
) -> list[int]:
    indices = set()
    for subsystem in selected:
        indices.update(snapshot.subsystem_index.get(subsystem, ()))
        indices.update(snapshot.inferred_subsystem_index.get(subsystem, ()))
    for repo_path in repo_paths:
        indices.update(snapshot.exact_affected_path_index.get(repo_path, ()))
        indices.update(snapshot.exact_evidence_ref_index.get(repo_path, ()))
        for prefix, prefix_indices in snapshot.path_prefix_index.items():
            normalized_prefix = prefix.rstrip("/")
            if normalized_prefix and repo_path.startswith(normalized_prefix):
                indices.update(prefix_indices)
        for prefix, prefix_indices in snapshot.evidence_prefix_index.items():
            normalized_prefix = prefix.rstrip("/")
            if normalized_prefix and repo_path.startswith(normalized_prefix):
                indices.update(prefix_indices)
    return list(indices)


def prefix_match_length(entry: HistoryEntry, repo_paths: list[str]) -> int:
    best = 0
    for query_path in repo_paths:
        for path in [*entry.affected_paths, *entry.evidence_refs]:
            prefix = path.rstrip("/")
            if prefix and query_path.startswith(prefix):
                best = max(best, len(prefix))
    return best


def lexical_overlap_score(entry: HistoryEntry, query_tokens: frozenset[str]) -> int:
    return len(query_tokens & (entry.text_tokens | entry.path_tokens))


def relevant_history_sort_key(
    entry: HistoryEntry,
    selected: set[str],
    repo_paths: list[str],
    rules: tuple[Rule, ...],
) -> tuple[int, int, int, int, int, int, int, str]:
    query_tokens = tokenize(" ".join(repo_paths))
    exact_affected = int(any(path in entry.affected_paths for path in repo_paths))
    exact_evidence = int(any(path in entry.evidence_refs for path in repo_paths))
    prefix_length = prefix_match_length(entry, repo_paths)
    direct_subsystem = int(entry.subsystem in selected)
    mapped_subsystem = int(
        entry.subsystem is None and bool(entry.mapped_subsystems & selected)
    )
    lexical_overlap = lexical_overlap_score(entry, query_tokens)

    penalized = False
    if repo_paths and all(not path.startswith("docs/") for path in repo_paths):
        if not (exact_affected or exact_evidence or prefix_length or direct_subsystem):
            selected_paths = [
                path
                for path in [*entry.affected_paths, *entry.evidence_refs]
                if any(name in selected for name in resolve_subsystems(path, rules))
            ]
            penalized = bool(selected_paths) and all(
                path in ARCHITECTURE_DOC_CHURN_PATHS for path in selected_paths
            )

    return (
        exact_affected,
        exact_evidence,
        prefix_length,
        direct_subsystem,
        mapped_subsystem,
        lexical_overlap,
        0 if penalized else 1,
        entry.timestamp_utc,
    )


def history_entries(
    source: MemoryPaths | MemorySnapshot,
    selected: set[str],
    *,
    repo_paths: list[str] | None = None,
    include_excluded: bool = False,
    history_mode: str = "recent",
) -> list[str]:
    if history_mode not in HISTORY_MODES:
        raise ValueError(f"unsupported history mode: {history_mode}")
    snapshot = ensure_snapshot(source)
    normalized_repo_paths = [normalize_path(path) for path in (repo_paths or [])]
    entries = []
    for index in candidate_history_indices(snapshot, selected, normalized_repo_paths):
        entry = snapshot.history_entries[index]
        if not include_excluded and entry.excluded_by_default:
            continue
        entries.append(entry)
    if history_mode == "recent":
        entries.sort(key=lambda item: item.timestamp_utc)
    else:
        entries.sort(
            key=lambda item: relevant_history_sort_key(
                item, selected, normalized_repo_paths, snapshot.rules
            ),
            reverse=True,
        )
    return [entry.rendered_line for entry in entries]


def render_context(
    source: MemoryPaths | MemorySnapshot,
    subsystem_names: list[str] | None = None,
    repo_paths: list[str] | None = None,
    include_history: int = 0,
    include_excluded_history: bool = False,
    history_mode: str = "recent",
) -> str:
    snapshot = ensure_snapshot(source)
    subsystem_names = subsystem_names or []
    repo_paths = repo_paths or []
    selected = select_subsystems(snapshot, subsystem_names, repo_paths)
    parts = [snapshot.project_brief, "", snapshot.current_focus]
    for name in selected:
        parts.extend(["", snapshot.subsystem_docs[name]])
    if include_history > 0:
        targets = set(selected or snapshot.focus_subsystems)
        items = history_entries(
            snapshot,
            targets,
            repo_paths=repo_paths,
            include_excluded=include_excluded_history,
            history_mode=history_mode,
        )
        if items:
            if history_mode == "recent":
                parts.extend(["", "## Recent History", *items[-include_history:]])
            else:
                parts.extend(["", "## Relevant History", *items[:include_history]])
    return "\n".join(parts).strip() + "\n"


def append_record(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True, sort_keys=True))
        handle.write("\n")


def build_record(
    paths: MemoryPaths,
    kind: str,
    timestamp: str | None,
    author: str,
    affected_paths: list[str],
    evidence_refs: list[str],
    **fields,
) -> dict:
    timestamp_utc = utc_now(timestamp)
    record = {
        "schema_version": SCHEMA_VERSION,
        "timestamp_utc": timestamp_utc,
        "author": normalize_text(author, "author", 80),
        "affected_paths": normalize_paths(affected_paths),
        "evidence_refs": normalize_paths(evidence_refs),
        **fields,
    }
    stable = {field: record[field] for field in ID_FIELDS[kind]}
    record["record_id"] = make_id(kind, timestamp_utc, stable)
    return record


def write_record(paths: MemoryPaths, filename: str, record: dict) -> dict:
    snapshot = build_snapshot(paths)
    kind = filename.replace(".jsonl", "")
    record_errors = validate_record(
        kind, record, paths.history_path(filename), 1, set(snapshot.pack_names)
    )
    if record_errors:
        raise ValueError("\n".join(record_errors))
    append_record(paths.history_path(filename), record)
    return record


def add_policy(
    paths: MemoryPaths,
    *,
    topic: str,
    status: str,
    statement: str,
    rationale: str,
    supersedes: list[str],
    evidence_refs: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict:
    if status not in STATUSES["policies"]:
        raise ValueError(f"unsupported policy status: {status}")
    record = build_record(
        paths,
        "policies",
        timestamp,
        author,
        affected_paths,
        evidence_refs,
        status=status,
        topic=normalize_text(topic, "topic", 120),
        statement=normalize_text(statement, "statement"),
        rationale=normalize_text(rationale, "rationale", 600),
        supersedes=normalize_list(supersedes, "supersedes"),
    )
    return write_record(paths, "policies.jsonl", record)


def add_fact(
    paths: MemoryPaths,
    *,
    subsystem: str,
    status: str,
    fact: str,
    rationale: str,
    supersedes: list[str],
    evidence_refs: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict:
    if status not in STATUSES["subsystem_facts"]:
        raise ValueError(f"unsupported fact status: {status}")
    record = build_record(
        paths,
        "subsystem_facts",
        timestamp,
        author,
        affected_paths,
        evidence_refs,
        subsystem=normalize_text(subsystem, "subsystem"),
        status=status,
        fact=normalize_text(fact, "fact"),
        rationale=normalize_text(rationale, "rationale", 600),
        supersedes=normalize_list(supersedes, "supersedes"),
    )
    return write_record(paths, "subsystem_facts.jsonl", record)


def add_investigation(
    paths: MemoryPaths,
    *,
    subsystem: str,
    status: str,
    question: str,
    current_best_answer: str,
    confidence: str,
    next_probe: str,
    evidence_refs: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict:
    if status not in STATUSES["investigations"]:
        raise ValueError(f"unsupported investigation status: {status}")
    if confidence not in {"low", "medium", "high"}:
        raise ValueError(f"unsupported confidence: {confidence}")
    record = build_record(
        paths,
        "investigations",
        timestamp,
        author,
        affected_paths,
        evidence_refs,
        subsystem=normalize_text(subsystem, "subsystem"),
        status=status,
        question=normalize_text(question, "question"),
        current_best_answer=normalize_text(
            current_best_answer, "current_best_answer", 600
        ),
        confidence=confidence,
        next_probe=normalize_text(next_probe, "next_probe"),
    )
    return write_record(paths, "investigations.jsonl", record)


def add_compat_event(
    paths: MemoryPaths,
    *,
    subsystem: str,
    status: str,
    title: str,
    summary: str,
    evidence_refs: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict:
    if status not in STATUSES["compat_events"]:
        raise ValueError(f"unsupported compat_event status: {status}")
    record = build_record(
        paths,
        "compat_events",
        timestamp,
        author,
        affected_paths,
        evidence_refs,
        subsystem=normalize_text(subsystem, "subsystem"),
        status=status,
        title=normalize_text(title, "title"),
        summary=normalize_text(summary, "summary"),
    )
    return write_record(paths, "compat_events.jsonl", record)


def add_task_event(
    paths: MemoryPaths,
    *,
    stream: str,
    status: str,
    summary: str,
    next_actions: list[str],
    evidence_refs: list[str],
    affected_paths: list[str],
    author: str,
    timestamp: str | None,
) -> dict:
    if status not in STATUSES["task_events"]:
        raise ValueError(f"unsupported task_event status: {status}")
    record = build_record(
        paths,
        "task_events",
        timestamp,
        author,
        affected_paths,
        evidence_refs,
        stream=normalize_text(stream, "stream", 120),
        status=status,
        summary=normalize_text(summary, "summary"),
        next_actions=normalize_list(next_actions, "next_actions"),
    )
    return write_record(paths, "task_events.jsonl", record)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Repo-scoped Codex memory utilities")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate", help="Validate the v2 Codex memory tree")
    sub.add_parser("index", help="Generate docs/codex_memory/generated/memory_index.json")
    stale = sub.add_parser("stale-scan", help="Generate docs/codex_memory/generated/stale_report.md")
    stale.add_argument("--days", type=int, default=DEFAULT_STALE_DAYS)
    stale.add_argument("--as-of", default=date.today().isoformat())
    briefing = sub.add_parser("briefing", help="Generate docs/codex_memory/generated/task_briefing.md")
    briefing.add_argument("--task", required=True)
    briefing.add_argument("--path", action="append", default=[])
    briefing.add_argument("--subsystem", action="append", default=[])
    briefing.add_argument("--tag", action="append", default=[])
    briefing.add_argument("--lesson", action="append", default=[])
    briefing.add_argument("--events", type=int, default=DEFAULT_BRIEFING_EVENTS)
    briefing.add_argument("--max-bytes", type=int, default=DEFAULT_BRIEFING_MAX_BYTES)
    context = sub.add_parser(
        "context", help="Render project/current focus plus selected subsystem packs"
    )
    context.add_argument("--subsystem", action="append", default=[])
    context.add_argument("--path", action="append", default=[])
    context.add_argument("--include-history", type=int, default=0)
    context.add_argument(
        "--history-mode",
        default="recent",
        choices=HISTORY_MODES,
        help="Choose chronological recent history or ranked relevant history when --include-history is used.",
    )
    context.add_argument(
        "--include-excluded-history",
        action="store_true",
        help="Include history normally excluded from default canonical pickup, such as sidequest/ or LM task streams.",
    )

    policy = sub.add_parser("add-policy", help="Append a policy record")
    policy.add_argument("--topic", required=True)
    policy.add_argument("--status", required=True, choices=sorted(STATUSES["policies"]))
    policy.add_argument("--statement", required=True)
    policy.add_argument("--rationale", required=True)
    policy.add_argument("--supersedes", action="append", default=[])
    policy.add_argument("--evidence-ref", action="append", default=[])
    policy.add_argument("--affected-path", action="append", default=[])
    policy.add_argument("--author", default="codex")
    policy.add_argument("--timestamp")

    fact = sub.add_parser("add-fact", help="Append a subsystem fact record")
    fact.add_argument("--subsystem", required=True)
    fact.add_argument(
        "--status", required=True, choices=sorted(STATUSES["subsystem_facts"])
    )
    fact.add_argument("--fact", required=True)
    fact.add_argument("--rationale", required=True)
    fact.add_argument("--supersedes", action="append", default=[])
    fact.add_argument("--evidence-ref", action="append", default=[])
    fact.add_argument("--affected-path", action="append", default=[])
    fact.add_argument("--author", default="codex")
    fact.add_argument("--timestamp")

    investigation = sub.add_parser(
        "add-investigation", help="Append an investigation record"
    )
    investigation.add_argument("--subsystem", required=True)
    investigation.add_argument(
        "--status", required=True, choices=sorted(STATUSES["investigations"])
    )
    investigation.add_argument("--question", required=True)
    investigation.add_argument("--current-best-answer", required=True)
    investigation.add_argument(
        "--confidence", required=True, choices=["high", "low", "medium"]
    )
    investigation.add_argument("--next-probe", required=True)
    investigation.add_argument("--evidence-ref", action="append", default=[])
    investigation.add_argument("--affected-path", action="append", default=[])
    investigation.add_argument("--author", default="codex")
    investigation.add_argument("--timestamp")

    compat = sub.add_parser(
        "add-compat-event", help="Append a compatibility event record"
    )
    compat.add_argument("--subsystem", required=True)
    compat.add_argument(
        "--status", required=True, choices=sorted(STATUSES["compat_events"])
    )
    compat.add_argument("--title", required=True)
    compat.add_argument("--summary", required=True)
    compat.add_argument("--evidence-ref", action="append", default=[])
    compat.add_argument("--affected-path", action="append", default=[])
    compat.add_argument("--author", default="codex")
    compat.add_argument("--timestamp")

    task = sub.add_parser("add-task-event", help="Append a task event record")
    task.add_argument("--stream", required=True)
    task.add_argument(
        "--status", required=True, choices=sorted(STATUSES["task_events"])
    )
    task.add_argument("--summary", required=True)
    task.add_argument("--next-action", action="append", default=[])
    task.add_argument("--evidence-ref", action="append", default=[])
    task.add_argument("--affected-path", action="append", default=[])
    task.add_argument("--author", default="codex")
    task.add_argument("--timestamp")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    paths = MemoryPaths.defaults()
    try:
        if args.command == "validate":
            errors = validate_all(paths)
            if errors:
                for error in errors:
                    print(error, file=sys.stderr)
                return 1
            print("ok")
            return 0
        if args.command == "context":
            snapshot = build_snapshot(paths)
            print(
                render_context(
                    snapshot,
                    args.subsystem,
                    args.path,
                    args.include_history,
                    args.include_excluded_history,
                    args.history_mode,
                ),
                end="",
            )
            return 0
        if args.command == "index":
            lessons, errors = validate_lessons(paths)
            if errors:
                raise ValueError("\n".join(errors))
            paths.generated_dir.mkdir(parents=True, exist_ok=True)
            (paths.generated_dir / "memory_index.json").write_text(
                render_lesson_index(paths, lessons), encoding="utf-8"
            )
            print(paths.generated_dir / "memory_index.json")
            return 0
        if args.command == "stale-scan":
            if args.days < 1:
                raise ValueError("--days must be at least 1")
            try:
                date.fromisoformat(args.as_of)
            except ValueError as exc:
                raise ValueError("--as-of must parse as YYYY-MM-DD") from exc
            lessons, errors = validate_lessons(paths)
            if errors:
                raise ValueError("\n".join(errors))
            paths.generated_dir.mkdir(parents=True, exist_ok=True)
            (paths.generated_dir / "stale_report.md").write_text(
                render_stale_report(paths, lessons, args.days, args.as_of), encoding="utf-8"
            )
            print(paths.generated_dir / "stale_report.md")
            return 0
        if args.command == "briefing":
            if args.events < 0:
                raise ValueError("--events must be non-negative")
            if args.max_bytes < 2048:
                raise ValueError("--max-bytes must be at least 2048")
            lessons, errors = validate_lessons(paths)
            if errors:
                raise ValueError("\n".join(errors))
            paths.generated_dir.mkdir(parents=True, exist_ok=True)
            (paths.generated_dir / "task_briefing.md").write_text(
                render_briefing(
                    paths,
                    lessons,
                    args.task,
                    args.events,
                    args.path,
                    args.subsystem,
                    args.tag,
                    args.lesson,
                    args.max_bytes,
                ),
                encoding="utf-8",
            )
            print(paths.generated_dir / "task_briefing.md")
            return 0
        if args.command == "add-policy":
            record = add_policy(
                paths,
                topic=args.topic,
                status=args.status,
                statement=args.statement,
                rationale=args.rationale,
                supersedes=args.supersedes,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
        elif args.command == "add-fact":
            record = add_fact(
                paths,
                subsystem=args.subsystem,
                status=args.status,
                fact=args.fact,
                rationale=args.rationale,
                supersedes=args.supersedes,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
        elif args.command == "add-investigation":
            record = add_investigation(
                paths,
                subsystem=args.subsystem,
                status=args.status,
                question=args.question,
                current_best_answer=args.current_best_answer,
                confidence=args.confidence,
                next_probe=args.next_probe,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
        elif args.command == "add-compat-event":
            record = add_compat_event(
                paths,
                subsystem=args.subsystem,
                status=args.status,
                title=args.title,
                summary=args.summary,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
        else:
            record = add_task_event(
                paths,
                stream=args.stream,
                status=args.status,
                summary=args.summary,
                next_actions=args.next_action,
                evidence_refs=args.evidence_ref,
                affected_paths=args.affected_path,
                author=args.author,
                timestamp=args.timestamp,
            )
        print(record["record_id"])
        return 0
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
