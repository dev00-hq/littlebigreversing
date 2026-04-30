from __future__ import annotations

import argparse
import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from life_trace_windows import CaptureError, WindowCapture, WindowInput
from secret_room_door_watch import (
    DEFAULT_PROCESS_NAME,
    LIST_VAR_GAME_GLOBAL,
    LIST_VAR_GAME_SLOT_SIZE,
    ProcessReader,
    WatchField,
    find_pid_by_name,
)


DEFAULT_OUT_DIR = Path("work/live_proofs/phase5_magic_ball_throw_probe")

FLAG_BALLE_MAGIQUE = 1
MAGIC_LEVEL_GLOBAL = 0x0049A0A4
MAGIC_POINT_GLOBAL = 0x0049A0A5
ACTIVE_CUBE_GLOBAL = 0x00497F04
HERO_COUNT_GLOBAL = 0x0049A198
HERO_X_GLOBAL = 0x0049A1DA
HERO_Y_GLOBAL = 0x0049A1DE
HERO_Z_GLOBAL = 0x0049A1E2
HERO_BETA_GLOBAL = 0x0049A1EA

# SaveGame persists these fields after ActionNormal. The addresses are pinned from the
# current original-runtime proof lane and are evidence-only until promoted.
ACTION_NORMAL_GLOBAL = 0x0049A0F8
MAGIC_BALL_GLOBAL = 0x0049A0FC
MAGIC_BALL_TYPE_GLOBAL = 0x0049A100
MAGIC_BALL_COUNT_GLOBAL = 0x0049A101
MAGIC_BALL_FLAGS_GLOBAL = 0x0049A104

LIST_EXTRA_GLOBAL = 0x004A7428
EXTRA_STRIDE = 0x44
MAX_EXTRAS = 50

EXTRA_OFFSETS = {
    "pos_x": (0x00, 4),
    "pos_y": (0x04, 4),
    "pos_z": (0x08, 4),
    "org_x": (0x0C, 4),
    "org_y": (0x10, 4),
    "org_z": (0x14, 4),
    "sprite": (0x20, 2),
    "vx": (0x22, 2),
    "vy": (0x24, 2),
    "vz": (0x26, 2),
    "flags": (0x28, 4),
    "timer": (0x2C, 4),
    "body": (0x30, 2),
    "beta": (0x32, 2),
    "timeout": (0x34, 2),
    "divers": (0x36, 2),
    "poids": (0x38, 1),
    "hit_force": (0x39, 1),
    "owner": (0x3A, 1),
    "new_force": (0x3B, 1),
}

WATCH_FIELDS = (
    WatchField("active_cube", ACTIVE_CUBE_GLOBAL),
    WatchField("hero_count", HERO_COUNT_GLOBAL),
    WatchField("hero_x", HERO_X_GLOBAL),
    WatchField("hero_y", HERO_Y_GLOBAL),
    WatchField("hero_z", HERO_Z_GLOBAL),
    WatchField("hero_beta", HERO_BETA_GLOBAL),
    WatchField("magic_level", MAGIC_LEVEL_GLOBAL, 1),
    WatchField("magic_point", MAGIC_POINT_GLOBAL, 1),
    WatchField("magic_ball_flag", LIST_VAR_GAME_GLOBAL + (FLAG_BALLE_MAGIQUE * LIST_VAR_GAME_SLOT_SIZE), 2),
    WatchField("action_normal", ACTION_NORMAL_GLOBAL, 1),
    WatchField("magic_ball_index", MAGIC_BALL_GLOBAL),
    WatchField("magic_ball_type", MAGIC_BALL_TYPE_GLOBAL, 1),
    WatchField("magic_ball_count", MAGIC_BALL_COUNT_GLOBAL, 1),
    WatchField("magic_ball_flags", MAGIC_BALL_FLAGS_GLOBAL),
)


@dataclass(frozen=True)
class ScreenshotRecord:
    label: str
    path: str
    title: str


def write_jsonl(path: Path, row: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, separators=(",", ":")) + "\n")


def read_sized(reader: ProcessReader, address: int, size: int) -> int:
    value = reader.read_int(address, size)
    if size == 2 and value >= 0x8000:
        return value - 0x10000
    if size == 4 and value >= 0x80000000:
        return value - 0x100000000
    return value


def snapshot_globals(reader: ProcessReader) -> dict[str, int]:
    return {field.name: read_sized(reader, field.address, field.size) for field in WATCH_FIELDS}


def extra_snapshot(reader: ProcessReader, index: int) -> dict[str, int]:
    base = LIST_EXTRA_GLOBAL + index * EXTRA_STRIDE
    row = {"index": index}
    for name, (offset, size) in EXTRA_OFFSETS.items():
        row[name] = read_sized(reader, base + offset, size)
    return row


def active_extras(reader: ProcessReader) -> list[dict[str, int]]:
    rows: list[dict[str, int]] = []
    for index in range(MAX_EXTRAS):
        row = extra_snapshot(reader, index)
        if row["sprite"] >= 0:
            rows.append(row)
    return rows


def snapshot(reader: ProcessReader) -> dict[str, Any]:
    return {
        "globals": snapshot_globals(reader),
        "active_extras": active_extras(reader),
    }


def changed_fields(previous: dict[str, int], current: dict[str, int]) -> dict[str, dict[str, int]]:
    changes: dict[str, dict[str, int]] = {}
    for key, value in current.items():
        old = previous.get(key)
        if old != value:
            changes[key] = {"before": int(old) if old is not None else None, "after": int(value)}
    return changes


def extras_signature(extras: list[dict[str, int]]) -> list[list[int]]:
    return [
        [
            row["index"],
            row["sprite"],
            row["pos_x"],
            row["pos_y"],
            row["pos_z"],
            row["vx"],
            row["vy"],
            row["vz"],
            row["flags"],
            row["timeout"],
            row["divers"],
        ]
        for row in extras
    ]


def capture(capture_tool: WindowCapture, input_tool: WindowInput, pid: int, out_dir: Path, label: str) -> ScreenshotRecord:
    path = out_dir / f"{label}.png"
    window = capture_tool.wait_for_window(pid, timeout_sec=10.0)
    input_tool._activate_window(window.hwnd)
    window = capture_tool.capture(pid, path, timeout_sec=10.0)
    return ScreenshotRecord(label=label, path=str(path), title=window.title)


def summarize(rows: list[dict[str, Any]], screenshots: list[ScreenshotRecord], *, pid: int, out_dir: Path) -> dict[str, Any]:
    snapshots = [row for row in rows if row.get("phase") in {"initial", "change", "final"}]
    initial = snapshots[0]["snapshot"] if snapshots else {}
    final = snapshots[-1]["snapshot"] if snapshots else {}
    magic_ball_index_changes = [
        row
        for row in rows
        if row.get("phase") == "change"
        and "magic_ball_index" in row.get("global_changes", {})
    ]
    extra_changes = [row for row in rows if row.get("phase") == "change" and row.get("extras_changed")]
    return {
        "verdict": "magic_ball_throw_activity_observed" if magic_ball_index_changes or extra_changes else "magic_ball_throw_activity_not_observed",
        "pid": pid,
        "out_dir": str(out_dir),
        "initial": initial,
        "final": final,
        "magic_ball_index_changes": magic_ball_index_changes,
        "extra_change_count": len(extra_changes),
        "extra_changes": extra_changes[:20],
        "screenshots": [asdict(record) for record in screenshots],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Watch original-runtime Magic Ball throw globals and extra-table rows.")
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already-running LBA2.EXE pid.")
    target.add_argument("--process-name", default=DEFAULT_PROCESS_NAME, help="Resolve an already-running process by exact name.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory for JSONL, summary, and screenshots.")
    parser.add_argument("--duration-sec", type=float, default=20.0, help="Polling duration.")
    parser.add_argument("--poll-sec", type=float, default=0.02, help="Polling interval.")
    parser.add_argument("--no-screenshots", action="store_true", help="Skip before/change/final screenshots.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "events.jsonl"
    summary_path = out_dir / "summary.json"
    jsonl_path.write_text("", encoding="utf-8")

    pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name)
    reader = ProcessReader(pid)
    capture_tool = WindowCapture()
    input_tool = WindowInput()
    screenshots: list[ScreenshotRecord] = []
    rows: list[dict[str, Any]] = []

    try:
        current = snapshot(reader)
        row = {"t": 0.0, "phase": "initial", "snapshot": current}
        rows.append(row)
        write_jsonl(jsonl_path, row)
        if not args.no_screenshots:
            screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "01_initial"))

        start = time.monotonic()
        last_globals = current["globals"]
        last_extras_signature = extras_signature(current["active_extras"])
        change_screenshot_taken = False
        while time.monotonic() - start < max(0.1, args.duration_sec):
            time.sleep(max(0.01, args.poll_sec))
            current = snapshot(reader)
            global_changes = changed_fields(last_globals, current["globals"])
            current_extras_signature = extras_signature(current["active_extras"])
            extras_changed = current_extras_signature != last_extras_signature
            if global_changes or extras_changed:
                row = {
                    "t": round(time.monotonic() - start, 3),
                    "phase": "change",
                    "global_changes": global_changes,
                    "extras_changed": extras_changed,
                    "snapshot": current,
                }
                rows.append(row)
                write_jsonl(jsonl_path, row)
                if not args.no_screenshots and not change_screenshot_taken and (
                    "magic_ball_index" in global_changes or extras_changed
                ):
                    try:
                        screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "02_throw_activity"))
                    except CaptureError as error:
                        write_jsonl(jsonl_path, {"phase": "screenshot_error", "label": "02_throw_activity", "error": str(error)})
                    change_screenshot_taken = True
                last_globals = current["globals"]
                last_extras_signature = current_extras_signature

        final = snapshot(reader)
        row = {"t": round(time.monotonic() - start, 3), "phase": "final", "snapshot": final}
        rows.append(row)
        write_jsonl(jsonl_path, row)
        if not args.no_screenshots:
            screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "03_final"))
    finally:
        reader.close()

    summary = summarize(rows, screenshots, pid=pid, out_dir=out_dir)
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if summary["verdict"] == "magic_ball_throw_activity_observed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
