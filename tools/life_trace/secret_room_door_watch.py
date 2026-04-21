from __future__ import annotations

import argparse
import ctypes
import json
import struct
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
DEFAULT_PROCESS_NAME = "LBA2.EXE"


@dataclass(frozen=True)
class WatchField:
    name: str
    address: int
    size: int = 4


WATCH_FIELDS = (
    WatchField("scene_kind", 0x00497040),
    WatchField("transition_mode", 0x00497F08),
    WatchField("transition_variant", 0x00497F18),
    WatchField("active_cube", 0x00497F04),
    WatchField("new_cube", 0x0047561C),
    WatchField("new_pos_x", 0x00497F1C),
    WatchField("new_pos_y", 0x00497F20),
    WatchField("new_pos_z", 0x00497F24),
    WatchField("nb_little_keys", 0x0049A0A6, 1),
    WatchField("hero_count", 0x0049A198),
    WatchField("hero_x", 0x0049A1DA),
    WatchField("hero_y", 0x0049A1DE),
    WatchField("hero_z", 0x0049A1E2),
    WatchField("hero_beta", 0x0049A1EA),
    WatchField("candidate_x", 0x0049A0A8),
    WatchField("candidate_y", 0x0049A0AC),
    WatchField("candidate_z", 0x0049A0B0),
)


@dataclass(frozen=True)
class WatchZone:
    index: int
    kind: str
    num: int
    name: str
    bounds: tuple[int, int, int, int, int, int]


WATCH_ZONES = (
    WatchZone(
        index=0,
        kind="change_cube",
        num=0,
        name="scene2_secret_room_door_cube0",
        bounds=(9728, 1024, 512, 10239, 2815, 1535),
    ),
    WatchZone(
        index=1,
        kind="change_cube_trap",
        num=19,
        name="scene3_tralu_zone1_not_cellar",
        bounds=(3584, 3328, 8704, 4608, 4608, 9216),
    ),
    WatchZone(
        index=8,
        kind="change_cube_trap",
        num=20,
        name="scene3_tralu_zone8_not_cellar",
        bounds=(27136, 1536, 7680, 28160, 3072, 8192),
    ),
)


class ProcessReadError(RuntimeError):
    pass


class ProcessReader:
    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self.handle = self.kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())

    def close(self) -> None:
        if self.handle:
            self.kernel32.CloseHandle(self.handle)
            self.handle = 0

    def read_int(self, address: int, size: int) -> int:
        if size not in {1, 4}:
            raise ValueError(f"unsupported read size: {size}")
        buffer = ctypes.create_string_buffer(size)
        read = ctypes.c_size_t()
        ok = self.kernel32.ReadProcessMemory(
            self.handle,
            ctypes.c_void_p(address),
            buffer,
            size,
            ctypes.byref(read),
        )
        if not ok or read.value != size:
            raise ctypes.WinError(ctypes.get_last_error())
        if size == 1:
            return buffer.raw[0]
        return struct.unpack("<i", buffer.raw)[0]

    def __enter__(self) -> "ProcessReader":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Watch the live LBA2 secret-room door transition globals and hero-zone membership. "
            "Use this for the scene-2 cellar door seam, not the rejected scene-3 Tralu zones."
        )
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--attach-pid", type=int, help="Attach to an already running LBA2.EXE pid.")
    target.add_argument("--process-name", help="Exact process name to resolve, usually LBA2.EXE.")
    parser.add_argument("--out", required=True, help="JSONL output path.")
    parser.add_argument("--duration-sec", type=float, default=0.0, help="Watch duration. 0 means run until interrupted.")
    parser.add_argument("--poll-sec", type=float, default=0.05, help="Polling interval.")
    parser.add_argument("--once", action="store_true", help="Write one snapshot and exit.")
    return parser.parse_args(argv)


def find_pid_by_name(process_name: str) -> int:
    target = process_name.lower()
    completed = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or "<no output>"
        raise ProcessReadError(f"tasklist failed: {detail}")

    matches: list[int] = []
    for raw_line in completed.stdout.splitlines():
        columns = [part.strip('"') for part in raw_line.split('","')]
        if len(columns) < 2:
            continue
        name, pid_text = columns[0], columns[1]
        if name.lower() != target:
            continue
        try:
            matches.append(int(pid_text))
        except ValueError as exc:
            raise ProcessReadError(f"tasklist returned a non-integer pid for {name}: {pid_text}") from exc

    if not matches:
        raise ProcessReadError(f"process not found: {process_name}")
    if len(matches) > 1:
        raise ProcessReadError(f"multiple {process_name} processes found; pass --attach-pid")
    return matches[0]


def zone_contains(zone: WatchZone, x: int, y: int, z: int) -> bool:
    x0, y0, z0, x1, y1, z1 = zone.bounds
    return x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1


def zone_membership(x: int, y: int, z: int, zones: Iterable[WatchZone] = WATCH_ZONES) -> list[dict[str, object]]:
    clamped_y = max(0, y)
    return [
        {
            "index": zone.index,
            "type": zone.kind,
            "num": zone.num,
            "name": zone.name,
        }
        for zone in zones
        if zone_contains(zone, x, clamped_y, z)
    ]


def snapshot(read_int: Callable[[int, int], int], zones: Iterable[WatchZone] = WATCH_ZONES) -> dict[str, object]:
    values = {field.name: read_int(field.address, field.size) for field in WATCH_FIELDS}
    values["zones"] = zone_membership(
        int(values["hero_x"]),
        int(values["hero_y"]),
        int(values["hero_z"]),
        zones,
    )
    return values


def record_key(row: dict[str, object]) -> tuple[object, ...]:
    zones = row.get("zones", [])
    return (
        row["active_cube"],
        row["new_cube"],
        row["transition_mode"],
        row["transition_variant"],
        row["new_pos_x"],
        row["new_pos_y"],
        row["new_pos_z"],
        row["nb_little_keys"],
        row["hero_x"],
        row["hero_y"],
        row["hero_z"],
        tuple((zone["index"], zone["type"], zone["num"]) for zone in zones),  # type: ignore[index]
    )


def watch(reader: ProcessReader, out_path: Path, *, duration_sec: float, poll_sec: float, once: bool) -> int:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    deadline = None if duration_sec <= 0 else started + duration_sec
    last_key: tuple[object, ...] | None = None
    rows_written = 0

    with out_path.open("a", encoding="utf-8") as handle:
        while True:
            row = {
                "t": round(time.time() - started, 3),
                **snapshot(reader.read_int),
            }
            key = record_key(row)
            if key != last_key:
                handle.write(json.dumps(row, separators=(",", ":")) + "\n")
                handle.flush()
                rows_written += 1
                last_key = key

            if once:
                return rows_written
            if deadline is not None and time.time() >= deadline:
                return rows_written
            time.sleep(max(0.001, poll_sec))


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name or DEFAULT_PROCESS_NAME)
    with ProcessReader(pid) as reader:
        watch(
            reader,
            Path(args.out),
            duration_sec=max(0.0, args.duration_sec),
            poll_sec=max(0.001, args.poll_sec),
            once=bool(args.once),
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
