from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import time
from contextlib import contextmanager, nullcontext
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from collections.abc import Iterator
from typing import Any

from life_trace_windows import CaptureError, WindowCapture, WindowInput
from life_trace_shared import DEFAULT_GAME_EXE
from scenes.load_game import (
    default_source_save_path,
    direct_launch_argv,
    wait_for_adeline_splash,
    wait_for_post_splash_transition,
)
from secret_room_door_watch import (
    DEFAULT_PROCESS_NAME,
    LIST_VAR_GAME_GLOBAL,
    LIST_VAR_GAME_SLOT_SIZE,
    ProcessReader,
    WatchField,
    find_pid_by_name,
)


DEFAULT_OUT_DIR = Path("work/live_proofs/phase5_magic_ball_probe")
DEFAULT_SAVE_NAME = "new-game-cellar.LBA"
AUTOSAVE_NAME = "autosave.lba"
AUTOSAVE_HIDDEN_SUFFIX = ".phase5_magic_ball_probe_hidden"

FLAG_BALLE_MAGIQUE = 1
TAB_INV_GLOBAL = 0x004BA46C
TAB_INV_SLOT_SIZE = 0x16
TAB_INV_FLAG_INV_OFFSET = 0x0C
TAB_INV_IDOBJ3D_OFFSET = 0x10
MAGIC_LEVEL_GLOBAL = 0x0049A0A4
MAGIC_POINT_GLOBAL = 0x0049A0A5
ACTIVE_CUBE_GLOBAL = 0x00497F04
HERO_COUNT_GLOBAL = 0x0049A198
HERO_X_GLOBAL = 0x0049A1DA
HERO_Y_GLOBAL = 0x0049A1DE
HERO_Z_GLOBAL = 0x0049A1E2
HERO_BETA_GLOBAL = 0x0049A1EA

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
    WatchField("magic_ball_inv_flags", TAB_INV_GLOBAL + (FLAG_BALLE_MAGIQUE * TAB_INV_SLOT_SIZE) + TAB_INV_FLAG_INV_OFFSET),
    WatchField("magic_ball_inv_model_id", TAB_INV_GLOBAL + (FLAG_BALLE_MAGIQUE * TAB_INV_SLOT_SIZE) + TAB_INV_IDOBJ3D_OFFSET, 2),
)


@dataclass(frozen=True)
class ScreenshotRecord:
    label: str
    path: str
    title: str


def write_jsonl(path: Path, row: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, separators=(",", ":")) + "\n")


def capture(capture_tool: WindowCapture, input_tool: WindowInput, pid: int, out_dir: Path, label: str) -> ScreenshotRecord:
    path = out_dir / f"{label}.png"
    window = capture_tool.wait_for_window(pid, timeout_sec=10.0)
    input_tool._activate_window(window.hwnd)
    window = capture_tool.capture(pid, path, timeout_sec=10.0)
    return ScreenshotRecord(label=label, path=str(path), title=window.title)


def snapshot(reader: ProcessReader) -> dict[str, int]:
    return {field.name: reader.read_int(field.address, field.size) for field in WATCH_FIELDS}


def changed_fields(previous: dict[str, int], current: dict[str, int]) -> dict[str, dict[str, int]]:
    changes: dict[str, dict[str, int]] = {}
    for key, value in current.items():
        old = previous.get(key)
        if old != value:
            changes[key] = {"before": int(old) if old is not None else None, "after": int(value)}  # type: ignore[arg-type]
    return changes


def summarize(rows: list[dict[str, Any]], screenshots: list[ScreenshotRecord], *, pid: int, out_dir: Path, launched_save: str | None) -> dict[str, Any]:
    snapshots = [row for row in rows if row.get("phase") in {"initial", "change", "final"}]
    initial = snapshots[0]["snapshot"] if snapshots else {}
    final = snapshots[-1]["snapshot"] if snapshots else {}
    flag_changes = [
        row
        for row in rows
        if row.get("phase") == "change"
        and "magic_ball_flag" in row.get("changes", {})
    ]
    promoted_signal = any(
        int(row["changes"]["magic_ball_flag"]["before"]) == 0
        and int(row["changes"]["magic_ball_flag"]["after"]) > 0
        for row in flag_changes
        if row["changes"]["magic_ball_flag"].get("before") is not None
    )
    model_changed = any(
        "magic_ball_inv_model_id" in row.get("changes", {})
        for row in rows
        if row.get("phase") == "change"
    )
    return {
        "verdict": "magic_ball_pickup_observed" if promoted_signal else "magic_ball_pickup_not_observed",
        "pid": pid,
        "launched_save": launched_save,
        "out_dir": str(out_dir),
        "initial": initial,
        "final": final,
        "magic_ball_flag_changes": flag_changes,
        "observed_magic_ball_flag_0_to_positive": promoted_signal,
        "observed_magic_ball_inventory_model_change": model_changed,
        "screenshots": [asdict(record) for record in screenshots],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Watch the early-cellar magic ball pickup state in original LBA2."
    )
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already-running LBA2.EXE pid.")
    target.add_argument("--process-name", default=DEFAULT_PROCESS_NAME, help="Resolve an already-running process by exact name.")
    target.add_argument("--launch-save", help="Launch LBA2 with this source save staged into SAVE.")
    parser.add_argument("--launch", help="Path to LBA2.EXE when using --launch-save.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory for JSONL, summary, and screenshots.")
    parser.add_argument("--duration-sec", type=float, default=30.0, help="Polling duration.")
    parser.add_argument("--poll-sec", type=float, default=0.05, help="Polling interval.")
    parser.add_argument("--no-screenshots", action="store_true", help="Skip before/change/final screenshots.")
    parser.add_argument("--keep-alive", action="store_true", help="Leave a launched process running.")
    return parser.parse_args()


@contextmanager
def hidden_autosave(save_dir: Path) -> Iterator[None]:
    autosave_path = save_dir / AUTOSAVE_NAME
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    hidden_path = save_dir / f"{AUTOSAVE_NAME}{AUTOSAVE_HIDDEN_SUFFIX}-{timestamp}"
    if not autosave_path.exists():
        yield
        return
    if hidden_path.exists():
        raise RuntimeError(
            f"Refusing to hide {autosave_path}; hidden autosave already exists at {hidden_path}."
        )
    autosave_path.rename(hidden_path)
    try:
        yield
    finally:
        if autosave_path.exists():
            preserved_path = save_dir / f"{AUTOSAVE_NAME}.generated-during-phase5-magic-ball-{timestamp}"
            autosave_path.rename(preserved_path)
        hidden_path.rename(autosave_path)


def stage_runtime_save(source_save: Path, save_dir: Path) -> Path:
    if not source_save.exists():
        raise RuntimeError(f"Save file does not exist: {source_save}")
    save_dir.mkdir(parents=True, exist_ok=True)
    runtime_save = save_dir / source_save.name
    if source_save.resolve() != runtime_save.resolve():
        shutil.copy2(source_save, runtime_save)
    return Path("SAVE") / source_save.name


def launch_from_save(args: argparse.Namespace, capture_tool: WindowCapture, input_tool: WindowInput) -> tuple[subprocess.Popen[bytes], str]:
    try:
        existing_pid = find_pid_by_name(DEFAULT_PROCESS_NAME)
    except RuntimeError:
        existing_pid = None
    if existing_pid is not None:
        raise RuntimeError(
            f"--launch-save requires no existing {DEFAULT_PROCESS_NAME}; "
            f"found pid {existing_pid}. Close the running game or use --attach-pid."
        )

    save_path = Path(args.launch_save) if args.launch_save else default_source_save_path(DEFAULT_SAVE_NAME)
    launch_path = Path(args.launch) if args.launch else DEFAULT_GAME_EXE
    runtime_save_arg = stage_runtime_save(save_path, launch_path.parent / "SAVE")
    argv = direct_launch_argv(launch_path, runtime_save_arg)
    process = subprocess.Popen(argv, cwd=str(launch_path.parent))
    splash_checksum = wait_for_adeline_splash(
        capture_tool,
        process.pid,
        startup_window_timeout_sec=25.0,
        splash_timeout_sec=8.0,
    )
    window = capture_tool.wait_for_window(process.pid, timeout_sec=25.0)
    input_tool.send_enter(window.hwnd)
    wait_for_post_splash_transition(
        capture_tool,
        process.pid,
        startup_window_timeout_sec=25.0,
        splash_checksum=splash_checksum,
        post_splash_timeout_sec=8.0,
    )
    time.sleep(2.0)
    return process, str(runtime_save_arg)


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "events.jsonl"
    summary_path = out_dir / "summary.json"
    jsonl_path.write_text("", encoding="utf-8")
    capture_tool = WindowCapture()
    input_tool = WindowInput()
    process: subprocess.Popen[bytes] | None = None
    launched_save: str | None = None
    screenshots: list[ScreenshotRecord] = []
    rows: list[dict[str, Any]] = []

    autosave_context = (
        hidden_autosave((Path(args.launch) if args.launch else DEFAULT_GAME_EXE).parent / "SAVE")
        if args.launch_save
        else nullcontext()
    )

    try:
        with autosave_context:
            if args.launch_save:
                process, launched_save = launch_from_save(args, capture_tool, input_tool)
                pid = process.pid
            else:
                pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name)

            reader = ProcessReader(pid)
            try:
                current = snapshot(reader)
                row = {"t": 0.0, "phase": "initial", "snapshot": current}
                rows.append(row)
                write_jsonl(jsonl_path, row)
                if not args.no_screenshots:
                    screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "01_initial"))

                start = time.monotonic()
                last = current
                change_screenshot_taken = False
                while time.monotonic() - start < max(0.1, args.duration_sec):
                    time.sleep(max(0.01, args.poll_sec))
                    current = snapshot(reader)
                    changes = changed_fields(last, current)
                    if changes:
                        row = {
                            "t": round(time.monotonic() - start, 3),
                            "phase": "change",
                            "changes": changes,
                            "snapshot": current,
                        }
                        rows.append(row)
                        write_jsonl(jsonl_path, row)
                        if (
                            not args.no_screenshots
                            and not change_screenshot_taken
                            and "magic_ball_flag" in changes
                        ):
                            try:
                                screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "02_magic_ball_flag_change"))
                            except CaptureError as error:
                                write_jsonl(jsonl_path, {"phase": "screenshot_error", "label": "02_magic_ball_flag_change", "error": str(error)})
                            change_screenshot_taken = True
                        last = current

                final = snapshot(reader)
                row = {"t": round(time.monotonic() - start, 3), "phase": "final", "snapshot": final}
                rows.append(row)
                write_jsonl(jsonl_path, row)
                if not args.no_screenshots:
                    screenshots.append(capture(capture_tool, input_tool, pid, out_dir, "03_final"))
            finally:
                reader.close()

        summary = summarize(rows, screenshots, pid=pid, out_dir=out_dir, launched_save=launched_save)
        summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps(summary, indent=2))
        return 0 if summary["verdict"] == "magic_ball_pickup_observed" else 1
    finally:
        if process is not None and not args.keep_alive:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
