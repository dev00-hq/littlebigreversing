#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
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
            normalize_text(record[field], field)
        except ValueError as exc:
            errors.append(f"{path}:{line_no}: {exc}")
    for field in FIELD_RULES[kind]["long"]:
        try:
            normalize_text(record[field], field, 600)
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
                normalize_text(item, field)
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


def load_validated_data(paths: MemoryPaths) -> ValidatedMemoryData:
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
                )
            )
        errors.extend(validate_append_only_history_file(paths, f"{kind}.jsonl"))

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


def build_snapshot(paths: MemoryPaths) -> MemorySnapshot:
    validated = load_validated_data(paths)
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
