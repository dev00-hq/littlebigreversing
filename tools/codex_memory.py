#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
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
    "platform_windows",
    "platform_linux",
    "architecture",
)
MARKDOWN_SPECS = {
    "README.md": (("Workflow", "Commands", "Write Rules", "Budgets"), None),
    "project_brief.md": (("Purpose", "Repo Map", "Canonical Sources", "Invariants", "Non-Goals"), 2048),
    "current_focus.md": (
        ("Current Priorities", "Active Streams", "Blocked Items", "Next Actions", "Relevant Subsystem Packs"),
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
    "policies": {"required": ("status", "topic", "statement", "rationale", "supersedes"), "short": ("topic", "statement"), "long": ("rationale",), "list": ("supersedes",)},
    "subsystem_facts": {"required": ("subsystem", "status", "fact", "rationale", "supersedes"), "short": ("fact",), "long": ("rationale",), "list": ("supersedes",)},
    "investigations": {"required": ("subsystem", "status", "question", "current_best_answer", "confidence", "next_probe"), "short": ("question", "next_probe"), "long": ("current_best_answer",), "list": ()},
    "compat_events": {"required": ("subsystem", "status", "title", "summary"), "short": ("title", "summary"), "long": (), "list": ()},
    "task_events": {"required": ("stream", "status", "summary", "next_actions"), "short": ("stream", "summary"), "long": (), "list": ("next_actions",)},
}
COMMON_FIELDS = ("schema_version", "record_id", "timestamp_utc", "author", "affected_paths", "evidence_refs")


@dataclass(frozen=True)
class MemoryPaths:
    repo_root: Path
    docs_dir: Path
    subsystem_dir: Path

    @classmethod
    def defaults(cls, repo_root: Path = DEFAULT_REPO_ROOT) -> "MemoryPaths":
        repo_root = repo_root.resolve()
        docs_dir = repo_root / "docs" / "codex_memory"
        return cls(repo_root=repo_root, docs_dir=docs_dir, subsystem_dir=docs_dir / "subsystems")

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
        return repo_path.startswith(self.path) if self.is_prefix() else repo_path == self.path


def parse_timestamp(value: str) -> str:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"invalid ISO timestamp: {value}") from exc
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp must include timezone: {value}")
    return parsed.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def utc_now(value: str | None) -> str:
    return parse_timestamp(value) if value else datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def stable_hash(payload) -> str:
    text = json.dumps(payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def make_id(kind: str, timestamp_utc: str, stable_fields: dict[str, str]) -> str:
    compact = timestamp_utc.replace("-", "").replace(":", "").replace("+00:00", "Z")
    return f"{PREFIXES[kind]}-{compact}-{stable_hash(stable_fields)[:10]}"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


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


def validate_markdown(path: Path, required: tuple[str, ...], budget: int | None) -> list[str]:
    if not path.exists():
        return [f"missing file: {path}"]
    content = read_text(path)
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


def load_index(paths: MemoryPaths) -> tuple[list[str], list[Rule]]:
    parsed = sections(read_text(paths.subsystem_dir / "INDEX.md"))
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


def resolve_subsystems(repo_path: str, rules: list[Rule]) -> list[str]:
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


def validate_record(kind: str, record: dict, path: Path, line_no: int, subsystems: set[str]) -> list[str]:
    errors = []
    for field in COMMON_FIELDS + FIELD_RULES[kind]["required"]:
        if field not in record:
            errors.append(f"{path}:{line_no}: missing field {field}")
    if errors:
        return errors
    if record["schema_version"] != SCHEMA_VERSION:
        errors.append(f"{path}:{line_no}: unsupported schema_version {record['schema_version']}")
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
        errors.append(f"{path}:{line_no}: unsupported {kind[:-1]} status {record['status']}")
    if "subsystem" in record and record["subsystem"] not in subsystems:
        errors.append(f"{path}:{line_no}: unknown subsystem {record['subsystem']}")
    if kind == "investigations" and record["confidence"] not in {"low", "medium", "high"}:
        errors.append(f"{path}:{line_no}: unsupported confidence {record['confidence']}")
    stable_fields = {field: record[field] for field in ID_FIELDS[kind]}
    expected = make_id(kind, record["timestamp_utc"], stable_fields)
    if record["record_id"] != expected:
        errors.append(f"{path}:{line_no}: record_id does not match canonical form {expected}")
    return errors


def parse_focus_subsystems(paths: MemoryPaths) -> list[str]:
    body = sections(read_text(paths.docs_dir / "current_focus.md"))["Relevant Subsystem Packs"]
    result = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        if not line.startswith("- "):
            raise ValueError(f"current_focus relevant subsystem line must be a bullet: {raw}")
        name = line[2:].strip().strip("`")
        if not re.fullmatch(r"[a-z0-9_]+", name):
            raise ValueError(f"invalid subsystem name in current_focus: {name}")
        result.append(name)
    return result


def validate_all(paths: MemoryPaths) -> list[str]:
    errors = []
    for rel in OBSOLETE_PATHS:
        if (paths.repo_root / rel).exists():
            errors.append(f"obsolete v1 path still present: {paths.repo_root / rel}")
    for name, (required, budget) in MARKDOWN_SPECS.items():
        errors.extend(validate_markdown(paths.docs_dir / name, required, budget))
    errors.extend(validate_markdown(paths.subsystem_dir / "INDEX.md", INDEX_SECTIONS, None))
    subsystem_names = sorted(path.stem for path in paths.subsystem_dir.glob("*.md") if path.name != "INDEX.md")
    subsystem_set = set(subsystem_names)
    if subsystem_set != set(EXPECTED_SUBSYSTEMS):
        missing = sorted(set(EXPECTED_SUBSYSTEMS) - subsystem_set)
        extra = sorted(subsystem_set - set(EXPECTED_SUBSYSTEMS))
        if missing:
            errors.append(f"{paths.subsystem_dir}: missing required subsystem packs: {', '.join(missing)}")
        if extra:
            errors.append(f"{paths.subsystem_dir}: unexpected subsystem packs: {', '.join(extra)}")
    for name in subsystem_names:
        errors.extend(validate_markdown(paths.subsystem_path(name), SUBSYSTEM_SECTIONS, SUBSYSTEM_BUDGET))
    if errors:
        return errors
    try:
        pack_names, rules = load_index(paths)
    except ValueError as exc:
        return [str(exc)]
    if set(pack_names) != subsystem_set:
        errors.append(f"{paths.subsystem_dir / 'INDEX.md'}: pack list must match subsystem files exactly")
    for rule in rules:
        if not (paths.repo_root / rule.path.rstrip("/")).exists():
            errors.append(f"{paths.subsystem_dir / 'INDEX.md'}: mapping target does not exist: {rule.path}")
    for i, left in enumerate(rules):
        for right in rules[i + 1 :]:
            if rule_overlap(left, right):
                errors.append(f"{paths.subsystem_dir / 'INDEX.md'}: ambiguous mapping between {left.subsystem}:{left.path} and {right.subsystem}:{right.path}")
    try:
        for name in parse_focus_subsystems(paths):
            if name not in subsystem_set:
                errors.append(f"{paths.docs_dir / 'current_focus.md'}: unknown subsystem in Relevant Subsystem Packs: {name}")
    except ValueError as exc:
        errors.append(f"{paths.docs_dir / 'current_focus.md'}: {exc}")
    for filename in HISTORY_FILES:
        kind = filename.replace(".jsonl", "")
        try:
            rows = load_jsonl(paths.history_path(filename))
        except ValueError as exc:
            errors.append(str(exc))
            continue
        for line_no, record in rows:
            errors.extend(validate_record(kind, record, paths.history_path(filename), line_no, subsystem_set))
    return errors


def select_subsystems(paths: MemoryPaths, names: list[str], repo_paths: list[str]) -> list[str]:
    pack_names, rules = load_index(paths)
    allowed = set(pack_names)
    selected = []
    for name in names:
        name = normalize_text(name, "subsystem")
        if name not in allowed:
            raise ValueError(f"unknown subsystem: {name}")
        if name not in selected:
            selected.append(name)
    for repo_path in repo_paths:
        matches = resolve_subsystems(repo_path, rules)
        if not matches:
            raise ValueError(f"no subsystem mapping for path: {repo_path}")
        if len(matches) > 1:
            raise ValueError(f"ambiguous subsystem mapping for path {repo_path}: {', '.join(matches)}")
        if matches[0] not in selected:
            selected.append(matches[0])
    return selected


def history_entries(paths: MemoryPaths, selected: set[str]) -> list[str]:
    _, rules = load_index(paths)
    entries = []
    for filename in HISTORY_FILES:
        kind = filename.replace(".jsonl", "")
        for _, record in load_jsonl(paths.history_path(filename)):
            relevant = record.get("subsystem") in selected
            if not relevant:
                for affected in record.get("affected_paths", []):
                    if any(name in selected for name in resolve_subsystems(affected, rules)):
                        relevant = True
                        break
            if not relevant:
                continue
            if kind == "policies":
                text = f"{record['topic']}: {record['statement']} ({record['status']})"
            elif kind == "subsystem_facts":
                text = f"{record['subsystem']}: {record['fact']} ({record['status']})"
            elif kind == "investigations":
                text = f"{record['subsystem']}: {record['question']} ({record['status']}, {record['confidence']})"
            elif kind == "compat_events":
                text = f"{record['subsystem']}: {record['title']} ({record['status']})"
            else:
                text = f"{record['stream']}: {record['summary']} ({record['status']})"
            entries.append((record["timestamp_utc"], f"- {record['timestamp_utc']} [{kind}] {text}"))
    entries.sort(key=lambda item: item[0])
    return [item[1] for item in entries]


def render_context(paths: MemoryPaths, subsystem_names: list[str] | None = None, repo_paths: list[str] | None = None, include_history: int = 0) -> str:
    errors = validate_all(paths)
    if errors:
        raise ValueError("\n".join(errors))
    subsystem_names = subsystem_names or []
    repo_paths = repo_paths or []
    selected = select_subsystems(paths, subsystem_names, repo_paths)
    parts = [read_text(paths.docs_dir / "project_brief.md").strip(), "", read_text(paths.docs_dir / "current_focus.md").strip()]
    for name in selected:
        parts.extend(["", read_text(paths.subsystem_path(name)).strip()])
    if include_history > 0:
        targets = set(selected or parse_focus_subsystems(paths))
        items = history_entries(paths, targets)
        if items:
            parts.extend(["", "## Recent History", *items[-include_history:]])
    return "\n".join(parts).strip() + "\n"


def append_record(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=True, sort_keys=True))
        handle.write("\n")


def build_record(paths: MemoryPaths, kind: str, timestamp: str | None, author: str, affected_paths: list[str], evidence_refs: list[str], **fields) -> dict:
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
    errors = validate_all(paths)
    if errors:
        raise ValueError("\n".join(errors))
    kind = filename.replace(".jsonl", "")
    record_errors = validate_record(kind, record, paths.history_path(filename), 1, set(load_index(paths)[0]))
    if record_errors:
        raise ValueError("\n".join(record_errors))
    append_record(paths.history_path(filename), record)
    return record


def add_policy(paths: MemoryPaths, *, topic: str, status: str, statement: str, rationale: str, supersedes: list[str], evidence_refs: list[str], affected_paths: list[str], author: str, timestamp: str | None) -> dict:
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


def add_fact(paths: MemoryPaths, *, subsystem: str, status: str, fact: str, rationale: str, supersedes: list[str], evidence_refs: list[str], affected_paths: list[str], author: str, timestamp: str | None) -> dict:
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


def add_investigation(paths: MemoryPaths, *, subsystem: str, status: str, question: str, current_best_answer: str, confidence: str, next_probe: str, evidence_refs: list[str], affected_paths: list[str], author: str, timestamp: str | None) -> dict:
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
        current_best_answer=normalize_text(current_best_answer, "current_best_answer", 600),
        confidence=confidence,
        next_probe=normalize_text(next_probe, "next_probe"),
    )
    return write_record(paths, "investigations.jsonl", record)


def add_compat_event(paths: MemoryPaths, *, subsystem: str, status: str, title: str, summary: str, evidence_refs: list[str], affected_paths: list[str], author: str, timestamp: str | None) -> dict:
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


def add_task_event(paths: MemoryPaths, *, stream: str, status: str, summary: str, next_actions: list[str], evidence_refs: list[str], affected_paths: list[str], author: str, timestamp: str | None) -> dict:
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
    context = sub.add_parser("context", help="Render project/current focus plus selected subsystem packs")
    context.add_argument("--subsystem", action="append", default=[])
    context.add_argument("--path", action="append", default=[])
    context.add_argument("--include-history", type=int, default=0)

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
    fact.add_argument("--status", required=True, choices=sorted(STATUSES["subsystem_facts"]))
    fact.add_argument("--fact", required=True)
    fact.add_argument("--rationale", required=True)
    fact.add_argument("--supersedes", action="append", default=[])
    fact.add_argument("--evidence-ref", action="append", default=[])
    fact.add_argument("--affected-path", action="append", default=[])
    fact.add_argument("--author", default="codex")
    fact.add_argument("--timestamp")

    investigation = sub.add_parser("add-investigation", help="Append an investigation record")
    investigation.add_argument("--subsystem", required=True)
    investigation.add_argument("--status", required=True, choices=sorted(STATUSES["investigations"]))
    investigation.add_argument("--question", required=True)
    investigation.add_argument("--current-best-answer", required=True)
    investigation.add_argument("--confidence", required=True, choices=["high", "low", "medium"])
    investigation.add_argument("--next-probe", required=True)
    investigation.add_argument("--evidence-ref", action="append", default=[])
    investigation.add_argument("--affected-path", action="append", default=[])
    investigation.add_argument("--author", default="codex")
    investigation.add_argument("--timestamp")

    compat = sub.add_parser("add-compat-event", help="Append a compatibility event record")
    compat.add_argument("--subsystem", required=True)
    compat.add_argument("--status", required=True, choices=sorted(STATUSES["compat_events"]))
    compat.add_argument("--title", required=True)
    compat.add_argument("--summary", required=True)
    compat.add_argument("--evidence-ref", action="append", default=[])
    compat.add_argument("--affected-path", action="append", default=[])
    compat.add_argument("--author", default="codex")
    compat.add_argument("--timestamp")

    task = sub.add_parser("add-task-event", help="Append a task event record")
    task.add_argument("--stream", required=True)
    task.add_argument("--status", required=True, choices=sorted(STATUSES["task_events"]))
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
            print(render_context(paths, args.subsystem, args.path, args.include_history), end="")
            return 0
        if args.command == "add-policy":
            record = add_policy(paths, topic=args.topic, status=args.status, statement=args.statement, rationale=args.rationale, supersedes=args.supersedes, evidence_refs=args.evidence_ref, affected_paths=args.affected_path, author=args.author, timestamp=args.timestamp)
        elif args.command == "add-fact":
            record = add_fact(paths, subsystem=args.subsystem, status=args.status, fact=args.fact, rationale=args.rationale, supersedes=args.supersedes, evidence_refs=args.evidence_ref, affected_paths=args.affected_path, author=args.author, timestamp=args.timestamp)
        elif args.command == "add-investigation":
            record = add_investigation(paths, subsystem=args.subsystem, status=args.status, question=args.question, current_best_answer=args.current_best_answer, confidence=args.confidence, next_probe=args.next_probe, evidence_refs=args.evidence_ref, affected_paths=args.affected_path, author=args.author, timestamp=args.timestamp)
        elif args.command == "add-compat-event":
            record = add_compat_event(paths, subsystem=args.subsystem, status=args.status, title=args.title, summary=args.summary, evidence_refs=args.evidence_ref, affected_paths=args.affected_path, author=args.author, timestamp=args.timestamp)
        else:
            record = add_task_event(paths, stream=args.stream, status=args.status, summary=args.summary, next_actions=args.next_action, evidence_refs=args.evidence_ref, affected_paths=args.affected_path, author=args.author, timestamp=args.timestamp)
        print(record["record_id"])
        return 0
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
