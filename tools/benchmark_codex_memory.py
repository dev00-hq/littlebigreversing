#!/usr/bin/env python3
from __future__ import annotations

import argparse
import statistics
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import codex_memory


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark Codex memory CLI and in-process context rendering")
    parser.add_argument("--iterations", type=int, default=10, help="Number of samples per measurement")
    parser.add_argument("--python-command", default="python3", help="Python command used for subprocess CLI timing")
    parser.add_argument("--subsystem", action="append", default=[], help="Repeatable subsystem filter passed through to context")
    parser.add_argument("--path", action="append", default=[], help="Repeatable repo-relative path filter passed through to context")
    parser.add_argument("--include-history", type=int, default=0, help="History rows requested from context")
    parser.add_argument(
        "--history-mode",
        default="recent",
        choices=codex_memory.HISTORY_MODES,
        help="History selection mode passed through when --include-history is used",
    )
    parser.add_argument(
        "--include-excluded-history",
        action="store_true",
        help="Include normally excluded history in both CLI and in-process render timings",
    )
    args = parser.parse_args(argv)
    if args.iterations <= 0:
        raise SystemExit("--iterations must be positive")
    return args


def context_command(args: argparse.Namespace) -> list[str]:
    command = [args.python_command, "tools/codex_memory.py", "context"]
    for subsystem in args.subsystem:
        command.extend(["--subsystem", subsystem])
    for repo_path in args.path:
        command.extend(["--path", repo_path])
    if args.include_history > 0:
        command.extend(["--include-history", str(args.include_history)])
    if args.history_mode != "recent":
        command.extend(["--history-mode", args.history_mode])
    if args.include_excluded_history:
        command.append("--include-excluded-history")
    return command


def measure_ms(callback, iterations: int) -> list[float]:
    samples = []
    for _ in range(iterations):
        started = time.perf_counter()
        callback()
        samples.append((time.perf_counter() - started) * 1000.0)
    return samples


def summarize(label: str, samples: list[float]) -> str:
    median = statistics.median(samples)
    minimum = min(samples)
    maximum = max(samples)
    mean = statistics.fmean(samples)
    return f"{label}: median={median:.3f} ms mean={mean:.3f} ms min={minimum:.3f} ms max={maximum:.3f} ms samples={len(samples)}"


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    repo_root = Path(__file__).resolve().parent.parent
    paths = codex_memory.MemoryPaths.defaults(repo_root)
    command = context_command(args)

    cli_samples = measure_ms(
        lambda: subprocess.run(
            command,
            cwd=repo_root,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ),
        args.iterations,
    )
    snapshot_samples = measure_ms(lambda: codex_memory.build_snapshot(paths), args.iterations)
    snapshot = codex_memory.build_snapshot(paths)
    render_samples = measure_ms(
        lambda: codex_memory.render_context(
            snapshot,
            subsystem_names=args.subsystem,
            repo_paths=args.path,
            include_history=args.include_history,
            include_excluded_history=args.include_excluded_history,
            history_mode=args.history_mode,
        ),
        args.iterations,
    )

    print(f"command: {' '.join(command)}")
    print(summarize("cli_context", cli_samples))
    print(summarize("build_snapshot", snapshot_samples))
    print(summarize("render_context", render_samples))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
