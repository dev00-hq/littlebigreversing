#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ZIG_VERSION = "0.16.0"


class DevShellError(RuntimeError):
    pass


def repo_env(repo_root: Path) -> dict[str, str]:
    return {
        "LBA2_REPO_ROOT": str(repo_root),
        "LBA2_ORIGINAL_CD_ROOT": str(
            repo_root / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2"
        ),
        "LBA2_SOURCE_ROOT": str(repo_root / "reference" / "lba2-classic"),
        "LBA2_MBN_TOOLS_ROOT": str(repo_root / "reference" / "littlebigreversing" / "mbn_tools"),
    }


def repo_zig_root(repo_root: Path) -> Path | None:
    candidate = repo_root / "work" / "toolchains" / f"zig-x86_64-windows-{ZIG_VERSION}"
    zig_exe = candidate / "zig.exe"
    return candidate if zig_exe.exists() else None


def get_env_value(environment: dict[str, str], name: str) -> str | None:
    expected = name.upper()
    for key, value in environment.items():
        if key.upper() == expected:
            return value
    return None


def update_environment_case_insensitive(target: dict[str, str], updates: dict[str, str]) -> None:
    existing_keys = {key.upper(): key for key in target}
    for key, value in updates.items():
        original_key = existing_keys.get(key.upper())
        if original_key is None:
            target[key] = value
            existing_keys[key.upper()] = key
        else:
            target[original_key] = value


def prepend_environment_path(target: dict[str, str], path: Path) -> None:
    current_path = get_env_value(target, "PATH") or ""
    updated_path = f"{path}{os.pathsep}{current_path}" if current_path else str(path)
    update_environment_case_insensitive(target, {"PATH": updated_path})


def find_first_existing_path(candidates: list[str]) -> Path | None:
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return path
    return None


def get_vcvars_candidate(arch: str) -> Path:
    file_name = "vcvars64.bat" if arch == "x64" else "vcvars32.bat"
    candidate = find_first_existing_path(
        [
            fr"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\{file_name}",
            fr"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\{file_name}",
            fr"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\{file_name}",
        ]
    )
    if candidate is None:
        raise DevShellError(f"Could not find a Visual Studio vcvars script for arch {arch!r}.")
    return candidate


def import_batch_environment(batch_file: Path) -> dict[str, str]:
    temp_script_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            suffix=".cmd",
            delete=False,
        ) as handle:
            handle.write("@echo off\n")
            handle.write(f'call "{batch_file}" >nul\n')
            handle.write("set\n")
            temp_script_path = Path(handle.name)

        completed = subprocess.run(
            ["cmd.exe", "/d", "/c", str(temp_script_path)],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        if temp_script_path is not None:
            temp_script_path.unlink(missing_ok=True)

    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        details = f"\n{stderr}" if stderr else ""
        raise DevShellError(f"Failed to import Visual Studio environment from {batch_file}.{details}")

    imported_env: dict[str, str] = {}
    for line in completed.stdout.splitlines():
        separator = line.find("=")
        if separator < 1:
            continue
        imported_env[line[:separator]] = line[separator + 1 :]
    return imported_env


def build_environment(arch: str) -> tuple[dict[str, str], Path]:
    vcvars = get_vcvars_candidate(arch)
    environment = os.environ.copy()
    update_environment_case_insensitive(environment, import_batch_environment(vcvars))
    update_environment_case_insensitive(environment, repo_env(REPO_ROOT))
    zig_root = repo_zig_root(REPO_ROOT)
    if zig_root is not None:
        prepend_environment_path(environment, zig_root)
        update_environment_case_insensitive(environment, {"LBA2_ZIG_ROOT": str(zig_root)})
    return environment, vcvars


def resolve_tool_path(name: str, environment: dict[str, str]) -> str | None:
    return shutil.which(name, path=get_env_value(environment, "PATH"))


def resolve_command_path_for_exec(command: list[str], environment: dict[str, str]) -> list[str]:
    if not command:
        return command

    executable = command[0]
    if Path(executable).anchor or "\\" in executable or "/" in executable:
        return command

    resolved = resolve_tool_path(executable, environment)
    if resolved is None:
        return command

    updated = list(command)
    updated[0] = resolved
    return updated


def resolve_workdir(path_text: str | None) -> Path:
    if not path_text:
        return REPO_ROOT
    candidate = Path(path_text)
    if not candidate.is_absolute():
        candidate = REPO_ROOT / candidate
    return candidate.resolve()


def resolve_shell_program(program: str | None) -> str:
    candidates = [program] if program else ["powershell.exe", "pwsh.exe"]
    for candidate in candidates:
        if candidate is None:
            continue
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    expected = program if program else "powershell.exe or pwsh.exe"
    raise DevShellError(f"Could not find {expected} on PATH.")


def print_summary(environment: dict[str, str], vcvars: Path, arch: str) -> None:
    print("Developer shell configured via Python.")
    print(f"  Arch: {arch}")
    print(f"  vcvars: {vcvars}")
    print(f"  Repo: {REPO_ROOT}")
    print()
    for tool in ("zig", "cl", "cmake", "ninja", "msbuild", "python", "java"):
        tool_path = resolve_tool_path(tool, environment)
        if tool_path:
            print(f"  {tool:<8} {tool_path}")
        else:
            print(f"  {tool:<8} <not found in PATH>")
    print()
    print("Environment variables set:")
    for variable in repo_env(REPO_ROOT):
        print(f"  {variable}")
    print()


def cmd_show(args: argparse.Namespace) -> int:
    environment, vcvars = build_environment(args.arch)
    if not args.quiet:
        print_summary(environment, vcvars, args.arch)
    return 0


def cmd_shell(args: argparse.Namespace) -> int:
    environment, vcvars = build_environment(args.arch)
    if not args.quiet:
        print_summary(environment, vcvars, args.arch)

    workdir = resolve_workdir(args.cwd)
    shell_program = resolve_shell_program(args.program)
    command = [shell_program, "-NoExit", "-Command", f'Set-Location -LiteralPath "{workdir}"']
    completed = subprocess.run(command, env=environment, check=False)
    return int(completed.returncode)


def normalize_exec_command(command: list[str]) -> list[str]:
    if command and command[0] == "--":
        return command[1:]
    return command


def cmd_exec(args: argparse.Namespace) -> int:
    command = normalize_exec_command(args.command)
    if not command:
        raise DevShellError("exec requires a command after '--'.")

    environment, _ = build_environment(args.arch)
    workdir = resolve_workdir(args.cwd)
    completed = subprocess.run(
        resolve_command_path_for_exec(command, environment),
        cwd=workdir,
        env=environment,
        check=False,
    )
    return int(completed.returncode)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Configure the canonical Windows Zig/MSVC environment for this repo."
    )
    parser.add_argument("--arch", choices=("x64", "x86"), default="x64")
    parser.add_argument("--quiet", action="store_true", help="Suppress the configuration summary.")

    subparsers = parser.add_subparsers(dest="subcommand")

    subparsers.add_parser("show", help="Validate and print the configured toolchain summary.")

    shell_parser = subparsers.add_parser("shell", help="Launch a child PowerShell session with the repo environment.")
    shell_parser.add_argument(
        "--cwd",
        help="Working directory for the child shell. Defaults to the repo root.",
    )
    shell_parser.add_argument(
        "--program",
        choices=("powershell.exe", "pwsh.exe"),
        help="Explicit shell program to launch.",
    )

    exec_parser = subparsers.add_parser("exec", help="Run a command inside the configured repo environment.")
    exec_parser.add_argument(
        "--cwd",
        help="Working directory for the command. Defaults to the repo root.",
    )
    exec_parser.add_argument("command", nargs=argparse.REMAINDER)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.subcommand is None:
        args.subcommand = "show"

    if args.subcommand == "show":
        return cmd_show(args)
    if args.subcommand == "shell":
        return cmd_shell(args)
    if args.subcommand == "exec":
        return cmd_exec(args)
    raise DevShellError(f"Unsupported subcommand: {args.subcommand}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DevShellError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
