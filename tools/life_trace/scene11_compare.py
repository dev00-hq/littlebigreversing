from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from scenes.scene11 import (
    build_scene11_comparison_report,
    load_scene11_run_summary,
)


def resolve_summary_path(path_text: str) -> Path:
    candidate = Path(path_text).resolve()
    if candidate.is_dir():
        candidate = candidate / "scene11_summary.json"
    if not candidate.exists():
        raise RuntimeError(f"scene11 comparison input does not exist: {candidate}")
    return candidate


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Scene11 debugger run summaries and apply the runtime-contract decision rule."
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="Scene11 run bundle directories or scene11_summary.json files.",
    )
    parser.add_argument(
        "--output",
        help="Optional path for the comparison JSON report. Defaults to stdout.",
    )
    args = parser.parse_args(argv)
    if len(args.inputs) < 2:
        parser.error("scene11 comparison requires at least two inputs")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    summaries = tuple(load_scene11_run_summary(resolve_summary_path(value)) for value in args.inputs)
    report = build_scene11_comparison_report(summaries)
    rendered = json.dumps(report.payload, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
    if args.output:
        output_path = Path(args.output).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(rendered, encoding="utf-8")
    else:
        sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
