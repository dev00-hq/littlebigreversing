#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GENERATED_PREFIXES = (
    "docs/codex_memory/generated/",
    "work/quality/",
)
REBUILDABLE_PREFIXES = (
    "work/",
)
USER_WORK_PREFIXES = (
    "tools/lba2_save_loader.py",
    "tools/lba2_build_preview_cache.py",
)
HARD_CUT_SCAN_PREFIXES = (
    "port/",
    "tools/",
)
HARD_CUT_TERMS = (
    "compat",
    "fallback",
    "legacy",
    "migration",
    "shim",
    "temporary",
)
ALLOWED_SCAN_PATHS = {
    "tools/cleanup_agent_audit.py",
    "tools/test_cleanup_agent_audit.py",
}


@dataclass(frozen=True)
class GitStatusItem:
    code: str
    path: str


@dataclass(frozen=True)
class Finding:
    rule_id: str
    severity: str
    path: str
    line: int | None
    message: str
    remediation: str

    def as_dict(self) -> dict[str, object]:
        return {
            "rule_id": self.rule_id,
            "severity": self.severity,
            "path": self.path,
            "line": self.line,
            "message": self.message,
            "remediation": self.remediation,
        }


def run(argv: list[str], *, cwd: Path = REPO_ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        check=False,
    )


def normalize_repo_path(path: str) -> str:
    return path.strip().replace("\\", "/")


def parse_git_status_porcelain(output: str) -> list[GitStatusItem]:
    items: list[GitStatusItem] = []
    for raw in output.splitlines():
        if not raw:
            continue
        code = raw[:2]
        path = normalize_repo_path(raw[3:])
        if " -> " in path:
            path = normalize_repo_path(path.split(" -> ", 1)[1])
        items.append(GitStatusItem(code=code, path=path))
    return items


def category_for_path(path: str) -> str:
    if any(path == prefix for prefix in USER_WORK_PREFIXES):
        return "user_work"
    if any(path.startswith(prefix) for prefix in GENERATED_PREFIXES):
        return "generated"
    if any(path.startswith(prefix) for prefix in REBUILDABLE_PREFIXES):
        return "rebuildable_work"
    return "canonical"


def grouped_status(items: list[GitStatusItem]) -> dict[str, list[dict[str, str]]]:
    groups: dict[str, list[dict[str, str]]] = {
        "canonical": [],
        "generated": [],
        "rebuildable_work": [],
        "user_work": [],
    }
    for item in items:
        groups[category_for_path(item.path)].append({"code": item.code, "path": item.path})
    return {key: value for key, value in groups.items() if value}


def iter_tracked_scan_paths() -> list[str]:
    completed = run(["git", "ls-files", *HARD_CUT_SCAN_PREFIXES])
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "git ls-files failed")
    return [
        normalize_repo_path(path)
        for path in completed.stdout.splitlines()
        if normalize_repo_path(path) not in ALLOWED_SCAN_PATHS
    ]


def dirty_scan_paths(items: list[GitStatusItem]) -> list[str]:
    paths = []
    for item in items:
        if item.path in ALLOWED_SCAN_PATHS:
            continue
        if category_for_path(item.path) != "canonical":
            continue
        if any(item.path.startswith(prefix) for prefix in HARD_CUT_SCAN_PREFIXES):
            path = REPO_ROOT / item.path
            if path.is_file():
                paths.append(item.path)
    return paths


def scan_hard_cut_terms(paths: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    lowered_terms = tuple(term.lower() for term in HARD_CUT_TERMS)
    for repo_path in paths:
        path = REPO_ROOT / repo_path
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_no, line in enumerate(lines, start=1):
            lowered = line.lower()
            hits = [term for term in lowered_terms if term in lowered]
            if not hits:
                continue
            findings.append(
                Finding(
                    rule_id="hard_cut_term_review",
                    severity="warning",
                    path=repo_path,
                    line=line_no,
                    message=f"Hard-cut-sensitive term(s) present: {', '.join(sorted(set(hits)))}.",
                    remediation="Review manually. Keep only if this is an explicit rejection/trap, diagnostic text, or documented exception with deletion criteria.",
                )
            )
    return findings


def command_verdict(argv: list[str]) -> dict[str, object]:
    completed = run(argv)
    return {
        "command": argv,
        "ok": completed.returncode == 0,
        "exit_code": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def build_report(*, run_validation: bool, scan_all: bool = False) -> dict[str, object]:
    status = run(["git", "status", "--porcelain"])
    if status.returncode != 0:
        raise RuntimeError(status.stderr.strip() or "git status failed")

    items = parse_git_status_porcelain(status.stdout)
    scan_paths = iter_tracked_scan_paths() if scan_all else dirty_scan_paths(items)
    findings = scan_hard_cut_terms(scan_paths)
    report: dict[str, object] = {
        "schema": "cleanup-agent-audit-v1",
        "mode": "read_only",
        "git_status": {
            "dirty": bool(items),
            "groups": grouped_status(items),
        },
        "findings": [finding.as_dict() for finding in findings],
        "scan": {
            "scope": "all_tracked" if scan_all else "dirty_canonical",
            "paths": scan_paths,
        },
        "policy": {
            "may_edit": False,
            "canonical_owner": "human_or_task_agent",
            "hard_cut_note": "Audit reports cleanup candidates only; it must not add compatibility shims, migrate states, or delete evidence automatically.",
        },
    }

    if run_validation:
        report["validation"] = {
            "codex_memory": command_verdict([sys.executable, "tools/codex_memory.py", "validate"]),
            "promotion_packets": command_verdict([sys.executable, "tools/validate_promotion_packets.py"]),
        }

    return report


def render_markdown(report: dict[str, object]) -> str:
    status = report["git_status"]
    lines = [
        "# Cleanup Agent Audit",
        "",
        f"- schema: `{report['schema']}`",
        f"- mode: `{report['mode']}`",
        f"- dirty worktree: `{str(status['dirty']).lower()}`",
        "",
        "## Policy",
        "",
        f"- may edit: `{str(report['policy']['may_edit']).lower()}`",
        f"- canonical owner: `{report['policy']['canonical_owner']}`",
        f"- hard-cut note: {report['policy']['hard_cut_note']}",
    ]

    groups = status["groups"]
    lines.extend(["", "## Worktree Groups", ""])
    if not groups:
        lines.append("- clean")
    else:
        for name, entries in groups.items():
            lines.append(f"- `{name}`")
            for entry in entries:
                lines.append(f"  - `{entry['code']}` `{entry['path']}`")

    validation = report.get("validation")
    if isinstance(validation, dict):
        lines.extend(["", "## Validation", ""])
        for name, verdict in validation.items():
            state = "ok" if verdict["ok"] else "failed"
            lines.append(f"- `{name}`: `{state}`")

    findings = report["findings"]
    lines.extend(["", "## Findings", ""])
    if not findings:
        lines.append("- none")
    else:
        for finding in findings:
            line = "" if finding["line"] is None else f":{finding['line']}"
            lines.append(
                f"- `{finding['severity']}` `{finding['rule_id']}` "
                f"`{finding['path']}{line}` - {finding['message']}"
            )

    return "\n".join(lines) + "\n"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read-only cleanup-agent audit for repo hygiene.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip memory and promotion-packet validation checks.",
    )
    parser.add_argument(
        "--scan-all",
        action="store_true",
        help="Scan all tracked port/tools files for hard-cut-sensitive terms; default scans dirty canonical files only.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        report = build_report(run_validation=not args.skip_validation, scan_all=args.scan_all)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_markdown(report), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
