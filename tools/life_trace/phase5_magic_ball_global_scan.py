from __future__ import annotations

import argparse
import contextlib
import json
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Iterator

from life_trace_shared import DEFAULT_GAME_EXE
from life_trace_windows import WindowCapture, WindowInput
from phase5_magic_ball_throw_probe import active_extras, snapshot_globals
from phase5_magic_ball_tralu_sequence import object_changes, object_snapshots
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition
from secret_room_door_watch import ProcessReader


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAVE = DEFAULT_GAME_EXE.parent / "SAVE" / "tralu-attack.LBA"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_magic_ball_global_scan"
VK_OEM_PERIOD = 0xBE
VK_1 = 0x31
VK_F5 = 0x74


def write_jsonl(path: Path, row: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, separators=(",", ":")) + "\n")


def list_running_lba2_pids() -> list[int]:
    completed = subprocess.run(
        ["tasklist", "/FI", "IMAGENAME eq LBA2.EXE", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    pids: list[int] = []
    for line in completed.stdout.splitlines():
        fields = [field.strip().strip('"') for field in line.split(",")]
        if len(fields) >= 2:
            try:
                pids.append(int(fields[1]))
            except ValueError:
                pass
    return pids


def kill_existing_lba2() -> None:
    if list_running_lba2_pids():
        subprocess.run(["taskkill", "/IM", "LBA2.EXE", "/F"], capture_output=True, text=True, check=False)
        time.sleep(0.5)


@contextlib.contextmanager
def hidden_autosave(save_dir: Path) -> Iterator[dict[str, Any]]:
    autosave_path = save_dir / "autosave.lba"
    state: dict[str, Any] = {"hidden": False}
    if not autosave_path.exists():
        try:
            yield state
        finally:
            if autosave_path.exists():
                preserved = save_dir / f"autosave.lba.generated-phase5-magic-ball-global-scan-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
                autosave_path.replace(preserved)
                state["preserved_generated"] = str(preserved)
        return

    hidden_path = save_dir / f"autosave.lba.phase5-magic-ball-global-scan-hidden-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    autosave_path.replace(hidden_path)
    state = {"hidden": True, "hidden_path": str(hidden_path)}
    try:
        yield state
    finally:
        if autosave_path.exists():
            preserved = save_dir / f"autosave.lba.generated-phase5-magic-ball-global-scan-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            autosave_path.replace(preserved)
            state["preserved_generated"] = str(preserved)
        hidden_path.replace(autosave_path)


def stage_save(source_save: Path, save_dir: Path) -> Path:
    if not source_save.exists():
        raise RuntimeError(f"save does not exist: {source_save}")
    save_dir.mkdir(parents=True, exist_ok=True)
    runtime_save = save_dir / source_save.name
    if source_save.resolve() != runtime_save.resolve():
        shutil.copy2(source_save, runtime_save)
    return Path("SAVE") / source_save.name


def hold_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float) -> None:
    input_tool.key_down(hwnd, virtual_key)
    time.sleep(hold_sec)
    input_tool.key_up(virtual_key)


def press_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float = 0.05) -> None:
    hold_key(input_tool, hwnd, virtual_key, hold_sec)
    time.sleep(0.05)


def read_s32(reader: ProcessReader, address: int) -> int:
    value = reader.read_int(address, 4)
    return value - 0x100000000 if value >= 0x80000000 else value


def read_u8(reader: ProcessReader, address: int) -> int:
    return reader.read_int(address, 1)


def scan_window(reader: ProcessReader, start: int, end: int) -> dict[str, Any]:
    s32 = {f"0x{address:08X}": read_s32(reader, address) for address in range(start, end, 4)}
    u8 = {f"0x{address:08X}": read_u8(reader, address) for address in range(start, end)}
    return {"s32": s32, "u8": u8}


def wait_for_loaded_state(reader: ProcessReader, *, timeout_sec: float, poll_sec: float) -> None:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        globals_row = snapshot_globals(reader)
        if globals_row["magic_level"] > 0 and globals_row["magic_point"] > 0:
            return
        time.sleep(max(0.005, poll_sec))
    raise RuntimeError("loaded save globals did not become readable")


def summarize(timeline_path: Path) -> dict[str, Any]:
    rows = [json.loads(line) for line in timeline_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    scans = [row for row in rows if row.get("phase") == "scan"]
    by_address: dict[str, list[int]] = {}
    for row in scans:
        for address, value in row["window"]["s32"].items():
            by_address.setdefault(address, []).append(value)

    candidates: list[dict[str, Any]] = []
    for address, values in by_address.items():
        if -1 in values and any(0 <= value < 50 for value in values):
            candidates.append({"address": address, "values": values})

    life_events: list[dict[str, Any]] = []
    for row in rows:
        if row.get("phase") != "object_change":
            continue
        for change in row["changes"]:
            if "life_point" in change["changes"]:
                life_events.append({"t": row["t"], "index": change["index"], "fields": change["changes"]})

    return {"candidate_magic_ball_s32": candidates, "life_events": life_events}


def run(args: argparse.Namespace) -> dict[str, Any]:
    exe = Path(args.exe).resolve()
    save = Path(args.save).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    timeline_path = out_dir / "timeline.jsonl"
    timeline_path.write_text("", encoding="utf-8")

    kill_existing_lba2()
    capture = WindowCapture()
    input_tool = WindowInput()
    process: subprocess.Popen[bytes] | None = None
    with hidden_autosave(exe.parent / "SAVE") as autosave_state:
        staged_save = stage_save(save, exe.parent / "SAVE")
        process = subprocess.Popen(direct_launch_argv(exe, staged_save), cwd=str(exe.parent))
        try:
            splash_checksum = wait_for_adeline_splash(
                capture,
                process.pid,
                startup_window_timeout_sec=25.0,
                splash_timeout_sec=args.splash_timeout_sec,
            )
            window = capture.wait_for_window(process.pid, timeout_sec=25.0)
            write_jsonl(timeline_path, {"phase": "splash_ready", "pid": process.pid, "autosave": autosave_state})
            input_tool.send_enter(window.hwnd)
            wait_for_post_splash_transition(
                capture,
                process.pid,
                startup_window_timeout_sec=25.0,
                splash_checksum=splash_checksum,
                post_splash_timeout_sec=args.post_splash_timeout_sec,
            )

            reader = ProcessReader(process.pid)
            try:
                wait_for_loaded_state(reader, timeout_sec=args.loaded_state_timeout_sec, poll_sec=args.poll_sec)
                if args.ready_delay_sec > 0:
                    time.sleep(args.ready_delay_sec)
                start = time.monotonic()
                previous_objects = object_snapshots(reader)
                write_jsonl(
                    timeline_path,
                    {
                        "phase": "scan",
                        "label": "before_throw",
                        "t": 0.0,
                        "globals": snapshot_globals(reader),
                        "active_extras": active_extras(reader),
                        "window": scan_window(reader, args.scan_start, args.scan_end),
                    },
                )
                if args.set_normal_mode:
                    press_key(input_tool, window.hwnd, VK_F5)
                    write_jsonl(
                        timeline_path,
                        {
                            "phase": "set_normal_mode",
                            "t": round(time.monotonic() - start, 3),
                            "globals": snapshot_globals(reader),
                        },
                    )
                if args.select_magic_ball:
                    press_key(input_tool, window.hwnd, VK_1)
                    write_jsonl(
                        timeline_path,
                        {
                            "phase": "selected_magic_ball",
                            "t": round(time.monotonic() - start, 3),
                            "globals": snapshot_globals(reader),
                            "window": scan_window(reader, args.scan_start, args.scan_end),
                        },
                    )
                hold_key(input_tool, window.hwnd, VK_OEM_PERIOD, args.hold_sec)
                write_jsonl(timeline_path, {"phase": "first_throw_released", "t": round(time.monotonic() - start, 3)})

                next_scan = time.monotonic()
                end = time.monotonic() + args.observe_sec
                while time.monotonic() < end:
                    now = time.monotonic()
                    current_objects = object_snapshots(reader)
                    changes = object_changes(previous_objects, current_objects)
                    if changes:
                        write_jsonl(timeline_path, {"phase": "object_change", "t": round(now - start, 3), "changes": changes})
                    previous_objects = current_objects
                    if now >= next_scan:
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "scan",
                                "label": "during",
                                "t": round(now - start, 3),
                                "globals": snapshot_globals(reader),
                                "active_extras": active_extras(reader),
                                "window": scan_window(reader, args.scan_start, args.scan_end),
                            },
                        )
                        next_scan = now + args.scan_interval_sec
                    time.sleep(max(0.005, args.poll_sec))
            finally:
                reader.close()
        finally:
            if process is not None and not args.leave_running:
                process.terminate()
                try:
                    process.wait(timeout=3.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5.0)

    summary = {
        "schema": "phase5-magic-ball-global-scan-v1",
        "save": str(save),
        "scan_start": f"0x{args.scan_start:08X}",
        "scan_end": f"0x{args.scan_end:08X}",
        "timeline": str(timeline_path),
        **summarize(timeline_path),
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scan nearby globals for live MagicBall sentinel transitions.")
    parser.add_argument("--exe", default=str(DEFAULT_GAME_EXE))
    parser.add_argument("--save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--hold-sec", type=float, default=0.75)
    parser.add_argument("--observe-sec", type=float, default=6.0)
    parser.add_argument("--poll-sec", type=float, default=0.02)
    parser.add_argument("--scan-interval-sec", type=float, default=0.1)
    parser.add_argument("--scan-start", type=lambda value: int(value, 0), default=0x0049A080)
    parser.add_argument("--scan-end", type=lambda value: int(value, 0), default=0x0049A140)
    parser.add_argument("--loaded-state-timeout-sec", type=float, default=2.0)
    parser.add_argument("--ready-delay-sec", type=float, default=0.0)
    parser.add_argument("--splash-timeout-sec", type=float, default=15.0)
    parser.add_argument("--post-splash-timeout-sec", type=float, default=8.0)
    parser.add_argument("--leave-running", action="store_true")
    parser.add_argument("--set-normal-mode", action="store_true")
    parser.add_argument("--select-magic-ball", action="store_true")
    return parser.parse_args()


def main() -> int:
    print(json.dumps(run(parse_args()), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
