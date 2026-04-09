#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class CheckResult:
    category: str
    name: str
    status: str
    details: str = ""
    required: bool = True


def find_first_existing_path(candidates: list[str]) -> Path | None:
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return path
    return None


def resolve_command_path(name: str) -> Path | None:
    resolved = shutil.which(name)
    if resolved is None:
        return None
    return Path(resolved)


def resolve_cdb_path() -> Path | None:
    command = resolve_command_path("cdb.exe") or resolve_command_path("cdb")
    if command is not None:
        return command

    candidate = find_first_existing_path(
        [
            r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe",
            r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe",
            r"C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe",
            r"C:\Program Files\Windows Kits\10\Debuggers\x86\cdb.exe",
        ]
    )
    if candidate is not None:
        return candidate

    windows_apps = Path(r"C:\Program Files\WindowsApps")
    if windows_apps.exists():
        for install_dir in sorted(windows_apps.glob("Microsoft.WinDbg_*"), reverse=True):
            candidate = find_first_existing_path(
                [
                    str(install_dir / "amd64" / "cdb.exe"),
                    str(install_dir / "x86" / "cdb.exe"),
                    str(install_dir / "arm64" / "cdb.exe"),
                ]
            )
            if candidate is not None:
                return candidate

    return None


def resolve_zig_details() -> CheckResult:
    zig = resolve_command_path("zig")
    if zig is None:
        return CheckResult(category="Modern build", name="Zig", status="Missing")

    details = str(zig)
    try:
        completed = subprocess.run(
            [str(zig), "version"],
            capture_output=True,
            text=True,
            check=False,
        )
        version = completed.stdout.strip()
        if completed.returncode == 0 and version:
            details = f"{zig} (zig {version})"
    except OSError:
        pass

    return CheckResult(category="Modern build", name="Zig", status="OK", details=details)


def build_results() -> list[CheckResult]:
    results: list[CheckResult] = []

    paths = [
        ("Repo root", REPO_ROOT),
        ("Historic source tree", REPO_ROOT / "reference" / "lba2-classic"),
        ("MBN tools", REPO_ROOT / "reference" / "littlebigreversing" / "mbn_tools"),
        ("Extracted CD data", REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2"),
        ("Porting report", REPO_ROOT / "docs" / "PORTING_REPORT.md"),
        ("Ghidra", Path(r"D:\repos\reverse\ghidra")),
        ("Detect It Easy", Path(r"D:\repos\reverse\Detect-It-Easy")),
        ("PE-bear", Path(r"D:\repos\reverse\PE-bear_0.7.1_qt6.8_x64_win_vs22\PE-bear.exe")),
    ]
    for name, path in paths:
        results.append(
            CheckResult(
                category="Paths",
                name=name,
                status="OK" if path.exists() else "Missing",
                details=str(path),
            )
        )

    modern_tools = [
        ("Visual Studio vcvars", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        ])),
        ("CMake", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        ])),
        ("Ninja", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
        ])),
        ("MSBuild", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
        ])),
        ("MSVC cl", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x64\cl.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64\cl.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64\cl.exe",
        ])),
        ("MASM ml", find_first_existing_path([
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\bin\Hostx64\x86\ml.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x86\ml.exe",
            r"C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x86\ml.exe",
        ])),
    ]
    for name, path in modern_tools:
        results.append(
            CheckResult(
                category="Modern build",
                name=name,
                status="OK" if path is not None else "Missing",
                details=str(path) if path is not None else "",
            )
        )
    results.append(resolve_zig_details())

    for name, command in (
        ("Python", resolve_command_path("python")),
        ("Java", resolve_command_path("java")),
        ("Git", resolve_command_path("git")),
        ("7-Zip", resolve_command_path("7z")),
    ):
        results.append(
            CheckResult(
                category="General tools",
                name=name,
                status="OK" if command is not None else "Missing",
                details=str(command) if command is not None else "",
            )
        )

    optional_tools = [
        ("Runtime debugging", "CDB", resolve_cdb_path()),
        ("Reference build", "DOSBox runtime", find_first_existing_path([
            str(REPO_ROOT / "reference" / "lba2-classic" / "Speedrun" / "Windows" / "DOSBOX" / "DOSBox.exe"),
            str(REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "DOSBOX" / "DOSBox.exe"),
        ])),
        ("Reference build", "DOSBox-X", find_first_existing_path([
            r"C:\Program Files\DOSBox-X\dosbox-x.exe",
            r"C:\Program Files (x86)\DOSBox-X\dosbox-x.exe",
            r"D:\repos\reverse\DOSBox-X\dosbox-x.exe",
        ])),
        ("Reference build", "OpenWatcom", find_first_existing_path([
            r"C:\WATCOM\BINNT64\wmake.exe",
            r"C:\WATCOM\BINNT\wmake.exe",
            r"C:\OpenWatcom\BINNT64\wmake.exe",
            r"C:\OpenWatcom\BINNT\wmake.exe",
        ])),
        ("Reference build", "x64dbg", find_first_existing_path([
            r"D:\repos\reverse\x64dbg\x64dbg.exe",
            r"D:\repos\reverse\x64dbg",
        ])),
        ("Modern port", "SDL2 headers", find_first_existing_path([
            str(REPO_ROOT / "vcpkg_installed" / "x64-windows" / "include" / "SDL2" / "SDL.h"),
            r"C:\SDL2\include\SDL.h",
            r"C:\SDL2\include\SDL2\SDL.h",
            r"C:\vcpkg\installed\x64-windows\include\SDL2\SDL.h",
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg\installed\x64-windows\include\SDL2\SDL.h",
        ])),
        ("Modern port", "SDL2 library", find_first_existing_path([
            str(REPO_ROOT / "vcpkg_installed" / "x64-windows" / "lib" / "SDL2.lib"),
            r"C:\SDL2\lib\x64\SDL2.lib",
            r"C:\vcpkg\installed\x64-windows\lib\SDL2.lib",
            r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg\installed\x64-windows\lib\SDL2.lib",
        ])),
    ]
    for category, name, path in optional_tools:
        required = category == "Modern port"
        results.append(
            CheckResult(
                category=category,
                name=name,
                status="OK" if path is not None else "Missing",
                details=str(path) if path is not None else "",
                required=required,
            )
        )

    return sorted(results, key=lambda item: (item.category, item.name))


def print_table(results: list[CheckResult]) -> None:
    headers = ("Category", "Name", "Status", "Details")
    widths = [
        len(headers[0]),
        len(headers[1]),
        len(headers[2]),
        len(headers[3]),
    ]
    for result in results:
        widths[0] = max(widths[0], len(result.category))
        widths[1] = max(widths[1], len(result.name))
        widths[2] = max(widths[2], len(result.status))
        widths[3] = max(widths[3], len(result.details))

    print(
        f"{headers[0]:<{widths[0]}}  {headers[1]:<{widths[1]}}  "
        f"{headers[2]:<{widths[2]}}  {headers[3]}"
    )
    print(
        f"{'-' * widths[0]}  {'-' * widths[1]}  "
        f"{'-' * widths[2]}  {'-' * widths[3]}"
    )
    for result in results:
        print(
            f"{result.category:<{widths[0]}}  {result.name:<{widths[1]}}  "
            f"{result.status:<{widths[2]}}  {result.details}"
        )


def main() -> int:
    results = build_results()
    missing_required = [result for result in results if result.status == "Missing" and result.required]
    missing_optional = [result for result in results if result.status == "Missing" and not result.required]

    print()
    print("LBA2 environment check")
    print(f"Repo: {REPO_ROOT}")
    print()
    print_table(results)
    print()

    if not missing_required:
        print("No missing required items detected for the canonical Windows Zig port workflow.")
    else:
        print("Missing required items detected:")
        for result in missing_required:
            print(f"  - [{result.category}] {result.name}")

    print()
    if missing_optional:
        print("Optional runtime/reference tools not installed:")
        for result in missing_optional:
            print(f"  - [{result.category}] {result.name}")
        print()

    print("Required checks for the canonical path:")
    print("  - Zig on PATH")
    print("  - Visual Studio toolchain")
    print("  - SDL2 development package")
    print("  - Extracted CD data")
    print()
    print("Canonical Windows runtime-debug path:")
    print("  - staged local Frida repo")
    print("  - CDB for detached Gate 3 debugger sessions")
    print()
    print("Optional installs for reference-track work:")
    print("  - x64dbg for historical/debugger-comparison reference only")
    print("  - DOSBox-X for DOS-side runtime investigation")
    print("  - OpenWatcom for historic-build experiments")
    print()
    print(r"Use py -3 .\scripts\dev-shell.py shell before running canonical Zig/MSVC commands.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
