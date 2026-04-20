from __future__ import annotations

import argparse
import ctypes
import json
from ctypes import wintypes
from pathlib import Path


PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
MEM_COMMIT = 0x1000
PAGE_GUARD = 0x0100
PAGE_NOACCESS = 0x0001

DEFAULT_PROCESS_NAME = "LBA2.EXE"
DEFAULT_MIN_LENGTH = 24
DEFAULT_MAX_MATCHES = 32
MAX_REGION_READ = 16 * 1024 * 1024


kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)


class MEMORY_BASIC_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BaseAddress", ctypes.c_void_p),
        ("AllocationBase", ctypes.c_void_p),
        ("AllocationProtect", wintypes.DWORD),
        ("RegionSize", ctypes.c_size_t),
        ("State", wintypes.DWORD),
        ("Protect", wintypes.DWORD),
        ("Type", wintypes.DWORD),
    ]


kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
kernel32.CloseHandle.restype = wintypes.BOOL
kernel32.ReadProcessMemory.argtypes = [
    wintypes.HANDLE,
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_size_t),
]
kernel32.ReadProcessMemory.restype = wintypes.BOOL
kernel32.VirtualQueryEx.argtypes = [
    wintypes.HANDLE,
    ctypes.c_void_p,
    ctypes.POINTER(MEMORY_BASIC_INFORMATION),
    ctypes.c_size_t,
]
kernel32.VirtualQueryEx.restype = ctypes.c_size_t

psapi.EnumProcesses.argtypes = [ctypes.POINTER(wintypes.DWORD), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
psapi.EnumProcesses.restype = wintypes.BOOL
psapi.GetModuleBaseNameW.argtypes = [wintypes.HANDLE, wintypes.HMODULE, wintypes.LPWSTR, wintypes.DWORD]
psapi.GetModuleBaseNameW.restype = wintypes.DWORD


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan live LBA2.EXE memory for decoded dialog strings and dump matching readable text."
    )
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already running LBA2.EXE pid.")
    target.add_argument(
        "--process-name",
        default=DEFAULT_PROCESS_NAME,
        help="Exact process name to attach to when --attach-pid is not provided.",
    )
    parser.add_argument(
        "--substring",
        required=True,
        help="Case-insensitive substring to search for in extracted readable strings.",
    )
    parser.add_argument(
        "--min-length",
        type=int,
        default=DEFAULT_MIN_LENGTH,
        help="Minimum string length to keep while scanning readable process memory.",
    )
    parser.add_argument(
        "--max-matches",
        type=int,
        default=DEFAULT_MAX_MATCHES,
        help="Maximum number of matching strings to return.",
    )
    parser.add_argument(
        "--out",
        help="Optional JSON output path. Defaults to stdout.",
    )
    return parser.parse_args()


def extract_ascii_strings(data: bytes, min_length: int) -> list[tuple[int, str]]:
    matches: list[tuple[int, str]] = []
    start: int | None = None
    current = bytearray()
    for index, value in enumerate(data):
        if 0x20 <= value <= 0x7E:
            if start is None:
                start = index
            current.append(value)
            continue
        if start is not None and len(current) >= min_length:
            matches.append((start, current.decode("ascii", errors="ignore")))
        start = None
        current.clear()
    if start is not None and len(current) >= min_length:
        matches.append((start, current.decode("ascii", errors="ignore")))
    return matches


def enumerate_processes() -> list[int]:
    capacity = 4096
    while True:
        process_ids = (wintypes.DWORD * capacity)()
        bytes_returned = wintypes.DWORD()
        if not psapi.EnumProcesses(process_ids, ctypes.sizeof(process_ids), ctypes.byref(bytes_returned)):
            raise OSError(ctypes.get_last_error(), "EnumProcesses failed")
        count = bytes_returned.value // ctypes.sizeof(wintypes.DWORD)
        if count < capacity:
            return [int(process_ids[index]) for index in range(count)]
        capacity *= 2


def process_name_for_pid(pid: int) -> str | None:
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return None
    try:
        buffer = ctypes.create_unicode_buffer(260)
        if psapi.GetModuleBaseNameW(handle, None, buffer, len(buffer)) == 0:
            return None
        return buffer.value
    finally:
        kernel32.CloseHandle(handle)


def resolve_target_pid(pid: int | None, process_name: str | None) -> tuple[int, str]:
    if pid is not None:
        name = process_name_for_pid(pid)
        if name is None:
            raise RuntimeError(f"unable to resolve process name for pid {pid}")
        return pid, name
    if process_name is None:
        raise RuntimeError("either --attach-pid or --process-name is required")
    target = process_name.lower()
    for candidate in enumerate_processes():
        name = process_name_for_pid(candidate)
        if name and name.lower() == target:
            return candidate, name
    raise RuntimeError(f"process not found: {process_name}")


def open_process_for_read(pid: int):
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        raise OSError(ctypes.get_last_error(), f"OpenProcess failed for pid {pid}")
    return handle


def iter_committed_regions(process_handle):
    mbi = MEMORY_BASIC_INFORMATION()
    address = 0
    while kernel32.VirtualQueryEx(
        process_handle, ctypes.c_void_p(address), ctypes.byref(mbi), ctypes.sizeof(mbi)
    ):
        base = int(mbi.BaseAddress or 0)
        size = int(mbi.RegionSize)
        if size <= 0:
            break
        readable = (
            int(mbi.State) == MEM_COMMIT
            and (int(mbi.Protect) & PAGE_GUARD) == 0
            and (int(mbi.Protect) & PAGE_NOACCESS) == 0
        )
        if readable:
            yield base, min(size, MAX_REGION_READ)
        address = base + size


def read_region(process_handle, base: int, size: int) -> bytes | None:
    buffer = (ctypes.c_char * size)()
    bytes_read = ctypes.c_size_t()
    if not kernel32.ReadProcessMemory(
        process_handle,
        ctypes.c_void_p(base),
        buffer,
        size,
        ctypes.byref(bytes_read),
    ):
        return None
    if bytes_read.value == 0:
        return None
    return bytes(buffer[: bytes_read.value])


def scan_process_for_strings(
    *,
    pid: int,
    substring: str,
    min_length: int,
    max_matches: int,
) -> dict[str, object]:
    process_handle = open_process_for_read(pid)
    substring_folded = substring.casefold()
    results: list[dict[str, object]] = []
    try:
        for base, size in iter_committed_regions(process_handle):
            data = read_region(process_handle, base, size)
            if data is None:
                continue
            for relative_offset, text in extract_ascii_strings(data, min_length):
                if substring_folded not in text.casefold():
                    continue
                results.append(
                    {
                        "address": f"0x{base + relative_offset:08X}",
                        "region_base": f"0x{base:08X}",
                        "region_size": size,
                        "text": text,
                    }
                )
                if len(results) >= max_matches:
                    return {"pid": pid, "substring": substring, "matches": results}
        return {"pid": pid, "substring": substring, "matches": results}
    finally:
        kernel32.CloseHandle(process_handle)


def main() -> int:
    args = parse_args()
    target_pid, target_name = resolve_target_pid(args.attach_pid, args.process_name)
    payload = scan_process_for_strings(
        pid=target_pid,
        substring=args.substring,
        min_length=args.min_length,
        max_matches=args.max_matches,
    )
    payload["process_name"] = target_name
    rendered = json.dumps(payload, indent=2)
    if args.out:
        output_path = Path(args.out)
        output_path.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
