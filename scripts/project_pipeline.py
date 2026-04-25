#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PORT_ROOT = REPO_ROOT / "port"
QUALITY_ROOT = REPO_ROOT / "work" / "quality" / "project-pipeline"

ZIG_VERSION = "0.16.0"
KIMUN_URL = "https://github.com/lnds/kimun.git"
KIMUN_COMMIT = "54d3cf093e7de2cf475e97f8de5095bf666872dc"
LIZARD_URL = "https://github.com/terryyin/lizard.git"
LIZARD_COMMIT = "f5172b15219a311c2f99fb51b3fe79649484239b"


class PipelineError(RuntimeError):
    pass


def run(
    argv: list[str],
    *,
    cwd: Path = REPO_ROOT,
    env: dict[str, str] | None = None,
    stdout_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    print(f"+ {' '.join(argv)}", flush=True)
    completed = subprocess.run(
        argv,
        cwd=str(cwd),
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if stdout_path is not None:
        stdout_path.parent.mkdir(parents=True, exist_ok=True)
        stdout_path.write_text(completed.stdout, encoding="utf-8")
    if completed.returncode != 0:
        if completed.stdout:
            print(completed.stdout, file=sys.stderr)
        if completed.stderr:
            print(completed.stderr, file=sys.stderr)
        raise PipelineError(f"command failed with exit code {completed.returncode}: {' '.join(argv)}")
    return completed


def prepend_path(env: dict[str, str], path: Path) -> dict[str, str]:
    updated = dict(env)
    path_key = next((key for key in updated if key.upper() == "PATH"), "PATH")
    value = f"{path}{os.pathsep}{updated.get(path_key, '')}"
    updated[path_key] = value
    if os.name == "nt":
        updated["Path"] = value
    return updated


def default_zig_root() -> Path | None:
    candidate = REPO_ROOT / "work" / "toolchains" / f"zig-x86_64-windows-{ZIG_VERSION}"
    return candidate if (candidate / "zig.exe").exists() or (candidate / "zig").exists() else None


def zig_executable(zig_root: Path | None) -> str:
    if zig_root is None:
        return "zig"
    exe_name = "zig.exe" if os.name == "nt" else "zig"
    return str(zig_root / exe_name)


def resolve_zig_env(args: argparse.Namespace) -> dict[str, str]:
    env = dict(os.environ)
    zig_root = Path(args.zig_root).resolve() if args.zig_root else default_zig_root()
    if zig_root is not None:
        env = prepend_path(env, zig_root)

    completed = run([zig_executable(zig_root), "version"], env=env, stdout_path=QUALITY_ROOT / "zig-version.txt")
    version = completed.stdout.strip()
    if version != ZIG_VERSION:
        raise PipelineError(
            f"expected Zig {ZIG_VERSION}, found {version!r}. "
            f"Put Zig {ZIG_VERSION} first on PATH or pass --zig-root."
        )
    return env


def ensure_git_checkout(path: Path, url: str, commit: str) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", url, str(path)])
    run(["git", "fetch", "--quiet", "origin", commit], cwd=path)
    run(["git", "checkout", "--quiet", "--detach", commit], cwd=path)
    actual = run(["git", "rev-parse", "HEAD"], cwd=path).stdout.strip()
    if actual != commit:
        raise PipelineError(f"{path} is at {actual}, expected {commit}")


def bootstrap_tools() -> None:
    kimun_src = REPO_ROOT / "work" / "external_tools" / "kimun"
    kimun_root = REPO_ROOT / "work" / "external_tools" / "kimun-install"
    lizard_src = REPO_ROOT / "work" / "external_tools" / "lizard"

    ensure_git_checkout(kimun_src, KIMUN_URL, KIMUN_COMMIT)
    ensure_git_checkout(lizard_src, LIZARD_URL, LIZARD_COMMIT)

    env = dict(os.environ)
    if os.name == "nt":
        env["RUSTFLAGS"] = "-C link-arg=advapi32.lib"
    run(["cargo", "install", "--path", str(kimun_src), "--root", str(kimun_root), "--force"], env=env)
    run([sys.executable, "-m", "pip", "install", "--user", f"git+{LIZARD_URL}@{LIZARD_COMMIT}"])


def resolve_kimun_bin() -> Path:
    env_bin = os.environ.get("KIMUN_BIN")
    candidates = []
    if env_bin:
        candidates.append(Path(env_bin))
    exe_name = "km.exe" if os.name == "nt" else "km"
    candidates.append(REPO_ROOT / "work" / "external_tools" / "kimun-install" / "bin" / exe_name)
    path_hit = shutil.which("km")
    if path_hit:
        candidates.append(Path(path_hit))
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise PipelineError("Kimun km binary not found. Run with --bootstrap-tools or set KIMUN_BIN.")


def assert_lizard_available() -> None:
    completed = run([sys.executable, "-m", "lizard", "--version"], stdout_path=QUALITY_ROOT / "lizard-version.txt")
    if "1.22.1" not in completed.stdout:
        raise PipelineError(f"expected lizard 1.22.1 from {LIZARD_COMMIT}, got {completed.stdout.strip()!r}")


def run_zig_pipeline(env: dict[str, str]) -> None:
    run([sys.executable, "scripts/dev-shell.py", "exec", "--cwd", "port", "--", "zig", "build"], env=env)
    run([sys.executable, "scripts/dev-shell.py", "exec", "--cwd", "port", "--", "zig", "build", "test-fast"], env=env)


def run_metrics(kimun_bin: Path) -> dict[str, object]:
    QUALITY_ROOT.mkdir(parents=True, exist_ok=True)
    source_root = PORT_ROOT / "src"
    common_kimun_filters = [
        "--include-ext",
        "zig",
        "--exclude",
        "generated/**",
        "--exclude",
        "sidequest_*.zig",
    ]

    score = run(
        [str(kimun_bin), "score", str(source_root), "--format", "json", *common_kimun_filters],
        stdout_path=QUALITY_ROOT / "kimun-score.json",
    )
    dups = run(
        [str(kimun_bin), "dups", str(source_root), "--format", "json", "--min-lines", "8", *common_kimun_filters],
        stdout_path=QUALITY_ROOT / "kimun-dups.json",
    )
    lizard = run(
        [
            sys.executable,
            "-m",
            "lizard",
            str(source_root),
            "-l",
            "zig",
            "-x",
            "*/generated/*",
            "-x",
            "*/sidequest_*",
            "--csv",
        ],
        stdout_path=QUALITY_ROOT / "lizard.csv",
    )

    return {
        "kimun_score_bytes": len(score.stdout),
        "kimun_dups_bytes": len(dups.stdout),
        "lizard_csv_bytes": len(lizard.stdout),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the canonical Zig and static-analysis project pipeline.")
    parser.add_argument("--zig-root", help=f"Directory containing Zig {ZIG_VERSION}; defaults to work/toolchains when present.")
    parser.add_argument("--bootstrap-tools", action="store_true", help="Clone/build pinned Kimun and install pinned Lizard before running.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        QUALITY_ROOT.mkdir(parents=True, exist_ok=True)
        if args.bootstrap_tools:
            bootstrap_tools()

        zig_env = resolve_zig_env(args)
        kimun_bin = resolve_kimun_bin()
        assert_lizard_available()
        run_zig_pipeline(zig_env)
        metrics = run_metrics(kimun_bin)

        summary = {
            "zig_version": ZIG_VERSION,
            "kimun": {"url": KIMUN_URL, "commit": KIMUN_COMMIT, "binary": str(kimun_bin)},
            "lizard": {"url": LIZARD_URL, "commit": LIZARD_COMMIT},
            "artifacts": str(QUALITY_ROOT),
            "metrics": metrics,
        }
        (QUALITY_ROOT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"pipeline complete: {QUALITY_ROOT}")
        return 0
    except PipelineError as exc:
        print(f"pipeline failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
