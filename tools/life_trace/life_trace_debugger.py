from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any


class DebuggerReadError(RuntimeError):
    pass


def resolve_cdb_agent_command() -> list[str]:
    launcher = shutil.which("cdb-agent")
    if launcher:
        return [launcher]
    raise DebuggerReadError(
        "unable to locate cdb-agent; install D:\\repos\\cdb-agent or put cdb-agent on PATH"
    )


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


def run_cdb_agent_json(
    launcher: list[str],
    command_args: list[str],
    *,
    timeout_sec: float = 60.0,
) -> dict[str, Any]:
    completed = subprocess.run(
        [*launcher, "--json", *command_args],
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_sec,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or "<no output>"
        raise DebuggerReadError(
            f"cdb-agent command failed ({completed.returncode}) for {' '.join(command_args)}: {detail}"
        )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise DebuggerReadError(
            f"cdb-agent command returned invalid JSON for {' '.join(command_args)}"
        ) from exc
    if not isinstance(payload, dict):
        raise DebuggerReadError(
            f"cdb-agent command returned an unexpected payload for {' '.join(command_args)}"
        )
    return payload


def parse_cdb_agent_rows(payload: dict[str, Any], command_name: str) -> list[dict[str, Any]]:
    rows = payload.get("rows")
    if not isinstance(rows, list):
        raise DebuggerReadError(f"cdb-agent {command_name} did not return a rows list")
    normalized: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise DebuggerReadError(f"cdb-agent {command_name} returned a non-dict row")
        normalized.append(row)
    return normalized


def collect_cdb_agent_bytes(rows: list[dict[str, Any]], address: int, count: int) -> bytes:
    collected: list[int] = []
    expected = address & 0xFFFFFFFF
    current = expected
    started = False

    for row in rows:
        try:
            row_address = int(row["address"])
        except (KeyError, TypeError, ValueError) as exc:
            raise DebuggerReadError("cdb-agent memory bytes row is missing an integer address") from exc
        byte_values = row.get("bytes")
        if not isinstance(byte_values, list) or any(not isinstance(value, int) for value in byte_values):
            raise DebuggerReadError("cdb-agent memory bytes row is missing an integer byte list")

        if not started:
            if row_address != expected:
                continue
            started = True
        elif row_address != current:
            break

        collected.extend(byte_values)
        current = (expected + len(collected)) & 0xFFFFFFFF
        if len(collected) >= count:
            return bytes(collected[:count])

    raise DebuggerReadError(
        f"cdb-agent memory bytes did not contain {count} bytes starting at 0x{address:08X}"
    )


class CdbMemoryReader:
    def __init__(
        self,
        cdb_path: Path,
        pid: int,
        *,
        timeout_sec: float = 60.0,
        cdb_agent_command: list[str] | None = None,
    ) -> None:
        self.cdb_path = cdb_path
        self.pid = pid
        self.timeout_sec = timeout_sec
        self.cdb_agent_command = resolve_cdb_agent_command() if cdb_agent_command is None else list(cdb_agent_command)

    def _base_command_args(self) -> list[str]:
        return [
            "--pid",
            str(self.pid),
            "--cdb-path",
            str(self.cdb_path),
            "--wow64",
            "--timeout-sec",
            str(self.timeout_sec),
        ]

    def read_scalars(
        self,
        *,
        dword_addresses: tuple[int, ...],
        word_addresses: tuple[int, ...],
    ) -> tuple[dict[int, int], dict[int, int]]:
        dwords: dict[int, int] = {}
        if dword_addresses:
            payload = run_cdb_agent_json(
                self.cdb_agent_command,
                [
                    "memory",
                    "dword",
                    *self._base_command_args(),
                    *[f"0x{address:08X}" for address in dword_addresses],
                ],
                timeout_sec=self.timeout_sec,
            )
            for row in parse_cdb_agent_rows(payload, "memory dword"):
                try:
                    address = int(row["address"])
                    value = int(row["value"])
                except (KeyError, TypeError, ValueError) as exc:
                    raise DebuggerReadError("cdb-agent memory dword row is missing integer address/value fields") from exc
                dwords[address] = value

        words: dict[int, int] = {}
        if word_addresses:
            payload = run_cdb_agent_json(
                self.cdb_agent_command,
                [
                    "memory",
                    "word",
                    *self._base_command_args(),
                    *[f"0x{address:08X}" for address in word_addresses],
                ],
                timeout_sec=self.timeout_sec,
            )
            for row in parse_cdb_agent_rows(payload, "memory word"):
                try:
                    address = int(row["address"])
                    value = int(row["value"])
                except (KeyError, TypeError, ValueError) as exc:
                    raise DebuggerReadError("cdb-agent memory word row is missing integer address/value fields") from exc
                words[address] = value

        missing_dwords = [address for address in dword_addresses if address not in dwords]
        if missing_dwords:
            missing = ", ".join(f"0x{address:08X}" for address in missing_dwords)
            raise DebuggerReadError(f"cdb-agent memory dword did not return addresses: {missing}")

        missing_words = [address for address in word_addresses if address not in words]
        if missing_words:
            missing = ", ".join(f"0x{address:08X}" for address in missing_words)
            raise DebuggerReadError(f"cdb-agent memory word did not return addresses: {missing}")

        return dwords, words

    def read_bytes(self, address: int, count: int) -> bytes:
        payload = run_cdb_agent_json(
            self.cdb_agent_command,
            [
                "memory",
                "bytes",
                *self._base_command_args(),
                "--count",
                str(count),
                f"0x{address:08X}",
            ],
            timeout_sec=self.timeout_sec,
        )
        return collect_cdb_agent_bytes(parse_cdb_agent_rows(payload, "memory bytes"), address, count)
