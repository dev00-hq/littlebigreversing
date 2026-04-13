from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path


class DebuggerReadError(RuntimeError):
    pass


def resolve_cdb_path(explicit_path: str | None) -> Path:
    candidates: list[Path] = []
    if explicit_path:
        candidates.append(Path(explicit_path))

    which = shutil.which("cdb.exe") or shutil.which("cdb")
    if which:
        candidates.append(Path(which))

    candidates.extend(
        [
            Path(r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"),
            Path(r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe"),
            Path(r"C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe"),
            Path(r"C:\Program Files\Windows Kits\10\Debuggers\x86\cdb.exe"),
        ]
    )

    windows_apps = Path(r"C:\Program Files\WindowsApps")
    if windows_apps.exists():
        for install_dir in sorted(windows_apps.glob("Microsoft.WinDbg_*"), reverse=True):
            candidates.extend(
                [
                    install_dir / "amd64" / "cdb.exe",
                    install_dir / "x86" / "cdb.exe",
                    install_dir / "arm64" / "cdb.exe",
                ]
            )

    seen: set[str] = set()
    for candidate in candidates:
        candidate_text = str(candidate)
        if candidate_text in seen:
            continue
        seen.add(candidate_text)
        if candidate.exists():
            return candidate

    raise DebuggerReadError("unable to locate cdb.exe; pass --cdb-path with an explicit debugger path")


def run_cdb_commands(
    cdb_path: Path,
    pid: int,
    commands: list[str],
    *,
    timeout_sec: float = 60.0,
) -> str:
    debugger_commands = [".load wow64exts", "!wow64exts.sw", *commands, "q"]
    completed = subprocess.run(
        [
            str(cdb_path),
            "-pv",
            "-p",
            str(pid),
            "-c",
            "; ".join(debugger_commands),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_sec,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or "<no output>"
        raise DebuggerReadError(
            f"cdb command failed ({completed.returncode}) for pid {pid}: {detail}"
        )
    return completed.stdout


def parse_cdb_dword(output: str, address: int) -> int:
    pattern = re.compile(
        rf"(?im)^(?:[0-9a-f]{{8}}`)?{address:08x}\s+([0-9a-f]{{8}})\b"
    )
    match = pattern.search(output)
    if match is None:
        raise DebuggerReadError(f"cdb output did not contain a dword read for 0x{address:08X}")
    return int(match.group(1), 16)


def parse_cdb_word(output: str, address: int) -> int:
    pattern = re.compile(
        rf"(?im)^(?:[0-9a-f]{{8}}`)?{address:08x}\s+([0-9a-f]{{4}})\b"
    )
    match = pattern.search(output)
    if match is None:
        raise DebuggerReadError(f"cdb output did not contain a word read for 0x{address:08X}")
    return int(match.group(1), 16)


def parse_cdb_bytes(output: str, address: int, count: int) -> bytes:
    line_pattern = re.compile(
        r"(?im)^(?:[0-9a-f]{8}`)?([0-9a-f]{8})\s+((?:[0-9a-f]{2}\s+){1,16})"
    )
    collected: list[int] = []
    expected = address & 0xFFFFFFFF
    current = expected
    started = False

    for line in output.splitlines():
        match = line_pattern.match(line.strip())
        if match is None:
            continue
        line_address = int(match.group(1), 16)
        if not started:
            if line_address != expected:
                continue
            started = True
        elif line_address != current:
            break

        tokens = re.findall(r"\b[0-9A-Fa-f]{2}\b", match.group(2))
        collected.extend(int(token, 16) for token in tokens)
        current = (expected + len(collected)) & 0xFFFFFFFF
        if len(collected) >= count:
            return bytes(collected[:count])

    raise DebuggerReadError(
        f"cdb output did not contain {count} bytes starting at 0x{address:08X}"
    )


class CdbMemoryReader:
    def __init__(
        self,
        cdb_path: Path,
        pid: int,
        *,
        timeout_sec: float = 60.0,
    ) -> None:
        self.cdb_path = cdb_path
        self.pid = pid
        self.timeout_sec = timeout_sec

    def read_scalars(
        self,
        *,
        dword_addresses: tuple[int, ...],
        word_addresses: tuple[int, ...],
    ) -> tuple[dict[int, int], dict[int, int]]:
        commands = [f"dd {address:08x} L1" for address in dword_addresses]
        commands.extend(f"dw {address:08x} L1" for address in word_addresses)
        output = run_cdb_commands(
            self.cdb_path,
            self.pid,
            commands,
            timeout_sec=self.timeout_sec,
        )
        dwords = {address: parse_cdb_dword(output, address) for address in dword_addresses}
        words = {address: parse_cdb_word(output, address) for address in word_addresses}
        return dwords, words

    def read_bytes(self, address: int, count: int) -> bytes:
        output = run_cdb_commands(
            self.cdb_path,
            self.pid,
            [f"db {address:08x} L{count}"],
            timeout_sec=self.timeout_sec,
        )
        return parse_cdb_bytes(output, address, count)
