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
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition
from secret_room_door_watch import ProcessReader


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAVE = DEFAULT_GAME_EXE.parent / "SAVE" / "tralu-attack.LBA"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_magic_ball_tralu_sequence"

VK_OEM_PERIOD = 0xBE
VK_1 = 0x31
VK_F5 = 0x74
OBJECT_BASE = 0x0049A19C
OBJECT_STRIDE = 0x21B
MAX_OBJECTS = 100

OBJECT_OFFSETS = {
    "gen_body": (0x00, 1),
    "col": (0x01, 1),
    "gen_anim": (0x04, 2),
    "next_gen_anim": (0x06, 2),
    "info": (0x14, 4),
    "info1": (0x18, 4),
    "info2": (0x1C, 4),
    "info3": (0x20, 4),
    "hit_by": (0x30, 1),
    "hit_force": (0x31, 1),
    "life_point": (0x32, 2),
    "option_flags": (0x34, 2),
    "x": (0x3E, 4),
    "y": (0x42, 4),
    "z": (0x46, 4),
    "beta": (0x4E, 4),
    "offset_track": (0x1E8, 2),
    "label_track": (0x1FC, 2),
    "memo_label_track": (0x1FE, 2),
    "memo_comportement": (0x200, 2),
    "obj_col": (0x1FA, 1),
    "flags": (0x204, 4),
    "work_flags": (0x208, 4),
    "exe_switch_func": (0x20E, 1),
    "exe_switch_type_answer": (0x20F, 1),
    "exe_switch_value": (0x210, 4),
}


def read_sized(reader: ProcessReader, address: int, size: int) -> int:
    value = reader.read_int(address, size)
    if size == 2 and value >= 0x8000:
        return value - 0x10000
    if size == 4 and value >= 0x80000000:
        return value - 0x100000000
    return value


def object_snapshot(reader: ProcessReader, index: int) -> dict[str, int]:
    base = OBJECT_BASE + index * OBJECT_STRIDE
    row = {"index": index}
    for name, (offset, size) in OBJECT_OFFSETS.items():
        row[name] = read_sized(reader, base + offset, size)
    return row


def object_snapshots(reader: ProcessReader) -> list[dict[str, int]]:
    return [object_snapshot(reader, index) for index in range(MAX_OBJECTS)]


def interesting_object(row: dict[str, int]) -> bool:
    return row["index"] == 0 or row["gen_body"] != 255 or row["life_point"] > 0 or row["hit_by"] != 255


def object_changes(before: list[dict[str, int]], after: list[dict[str, int]]) -> list[dict[str, Any]]:
    changes: list[dict[str, Any]] = []
    before_by_index = {row["index"]: row for row in before}
    for row in after:
        previous = before_by_index[row["index"]]
        fields: dict[str, dict[str, int]] = {}
        for field, value in row.items():
            if field == "index":
                continue
            old = previous[field]
            if old != value:
                fields[field] = {"before": old, "after": value}
        if fields and (interesting_object(row) or interesting_object(previous)):
            changes.append({"index": row["index"], "changes": fields, "after": row})
    return changes


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
                preserved = save_dir / f"autosave.lba.generated-phase5-tralu-sequence-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
                autosave_path.replace(preserved)
                state["preserved_generated"] = str(preserved)
        return

    hidden_path = save_dir / f"autosave.lba.phase5-tralu-sequence-hidden-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    autosave_path.replace(hidden_path)
    state = {"hidden": True, "hidden_path": str(hidden_path)}
    try:
        yield state
    finally:
        if autosave_path.exists():
            preserved = save_dir / f"autosave.lba.generated-phase5-tralu-sequence-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
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


def press_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float = 0.08) -> None:
    hold_key(input_tool, hwnd, virtual_key, hold_sec)
    time.sleep(0.15)


def wait_for_loaded_state(reader: ProcessReader, *, timeout_sec: float, poll_sec: float) -> dict[str, int]:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        globals_row = snapshot_globals(reader)
        hero = object_snapshot(reader, 0)
        if globals_row["magic_point"] > 0 and hero["life_point"] > 0:
            return globals_row
        time.sleep(max(0.005, poll_sec))
    raise RuntimeError(f"loaded save state did not become readable within {timeout_sec:g} seconds")


def summarize_life(timeline_path: Path) -> dict[str, Any]:
    life_events: list[dict[str, Any]] = []
    for line in timeline_path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("phase") != "object_change":
            continue
        for change in row["changes"]:
            fields = change["changes"]
            if "life_point" in fields or "hit_force" in fields or "hit_by" in fields:
                life_events.append({"t": row["t"], "index": change["index"], "fields": fields})
    return {"life_events": life_events}


def projectile_active(reader: ProcessReader) -> bool:
    return any(extra["sprite"] >= 0 for extra in active_extras(reader))


def wait_for_projectile_cycle(
    reader: ProcessReader,
    timeline_path: Path,
    start: float,
    *,
    timeout_sec: float,
    poll_sec: float,
) -> dict[str, float | None]:
    deadline = time.monotonic() + timeout_sec
    saw_active = False
    first_active_t: float | None = None
    clear_t: float | None = None
    while time.monotonic() < deadline:
        active = projectile_active(reader)
        t = round(time.monotonic() - start, 3)
        if active and not saw_active:
            saw_active = True
            first_active_t = t
            write_jsonl(timeline_path, {"phase": "first_projectile_active", "t": t})
        if saw_active and not active:
            clear_t = t
            write_jsonl(timeline_path, {"phase": "first_projectile_cleared", "t": t})
            return {"first_active_t": first_active_t, "clear_t": clear_t}
        time.sleep(max(0.005, poll_sec))
    write_jsonl(timeline_path, {"phase": "first_projectile_cycle_timeout", "t": round(time.monotonic() - start, 3)})
    return {"first_active_t": first_active_t, "clear_t": clear_t}


def find_life_drop(changes: list[dict[str, Any]], index: int) -> dict[str, int] | None:
    for change in changes:
        if change["index"] != index:
            continue
        life_change = change["changes"].get("life_point")
        if life_change is not None and life_change["after"] < life_change["before"]:
            return life_change
    return None


def magic_ball_index(reader: ProcessReader) -> int:
    return int(snapshot_globals(reader)["magic_ball_index"])


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
            first_preheld = False
            if args.prehold_first_throw:
                input_tool.key_down(window.hwnd, VK_OEM_PERIOD)
                first_preheld = True
                write_jsonl(timeline_path, {"phase": "first_throw_key_down_before_load"})
            wait_for_post_splash_transition(
                capture,
                process.pid,
                startup_window_timeout_sec=25.0,
                splash_checksum=splash_checksum,
                post_splash_timeout_sec=args.post_splash_timeout_sec,
            )

            reader = ProcessReader(process.pid)
            try:
                ready_globals = wait_for_loaded_state(
                    reader,
                    timeout_sec=args.loaded_state_timeout_sec,
                    poll_sec=args.poll_sec,
                )
                if args.ready_delay_sec > 0:
                    time.sleep(args.ready_delay_sec)
                start = time.monotonic()
                write_jsonl(timeline_path, {"phase": "loaded_state_ready", "t": 0.0, "globals": ready_globals})
                if args.set_normal_mode:
                    press_key(input_tool, window.hwnd, VK_F5)
                    write_jsonl(timeline_path, {"phase": "set_normal_mode", "t": round(time.monotonic() - start, 3), "globals": snapshot_globals(reader)})
                if args.select_magic_ball:
                    press_key(input_tool, window.hwnd, VK_1)
                    write_jsonl(timeline_path, {"phase": "selected_magic_ball", "t": round(time.monotonic() - start, 3), "globals": snapshot_globals(reader)})

                before_objects = object_snapshots(reader)
                write_jsonl(
                    timeline_path,
                    {
                        "phase": "before_first_throw",
                        "t": round(time.monotonic() - start, 3),
                        "globals": snapshot_globals(reader),
                        "objects": [row for row in before_objects if interesting_object(row)],
                    },
                )
                if first_preheld:
                    input_tool.key_up(VK_OEM_PERIOD)
                else:
                    hold_key(input_tool, window.hwnd, VK_OEM_PERIOD, args.hold_sec)
                write_jsonl(timeline_path, {"phase": "first_throw_released", "t": round(time.monotonic() - start, 3)})

                projectile_cycle: dict[str, float | None] | None = None
                if args.second_after_projectile_clear:
                    projectile_cycle = wait_for_projectile_cycle(
                        reader,
                        timeline_path,
                        start,
                        timeout_sec=args.projectile_cycle_timeout_sec,
                        poll_sec=args.poll_sec,
                    )
                    second_due = time.monotonic() + args.second_recovery_delay_sec
                else:
                    second_due = time.monotonic() + args.second_throw_delay_sec
                end = time.monotonic() + args.observe_sec
                previous_objects = before_objects
                second_thrown = False
                waiting_for_first_hit = args.second_after_tralu_hit
                waiting_for_ball_return = args.second_after_magic_ball_return
                saw_first_ball_index = False
                while time.monotonic() < end:
                    now = time.monotonic()
                    if not waiting_for_first_hit and not waiting_for_ball_return and not second_thrown and now >= second_due:
                        hold_key(input_tool, window.hwnd, VK_OEM_PERIOD, args.hold_sec)
                        second_thrown = True
                        write_jsonl(timeline_path, {"phase": "second_throw_released", "t": round(time.monotonic() - start, 3)})

                    globals_row = snapshot_globals(reader)
                    current_magic_ball = int(globals_row["magic_ball_index"])
                    if waiting_for_ball_return and not saw_first_ball_index and current_magic_ball != -1:
                        saw_first_ball_index = True
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "first_magic_ball_index_seen",
                                "t": round(time.monotonic() - start, 3),
                                "magic_ball_index": current_magic_ball,
                                "magic_ball_flags": globals_row["magic_ball_flags"],
                            },
                        )
                    if waiting_for_ball_return and saw_first_ball_index and current_magic_ball == -1:
                        waiting_for_ball_return = False
                        second_due = time.monotonic() + args.second_after_magic_ball_return_delay_sec
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "first_magic_ball_return_seen",
                                "t": round(time.monotonic() - start, 3),
                                "second_due_delay_sec": args.second_after_magic_ball_return_delay_sec,
                                "magic_ball_flags": globals_row["magic_ball_flags"],
                            },
                        )

                    current_objects = object_snapshots(reader)
                    changes = object_changes(previous_objects, current_objects)
                    if changes:
                        write_jsonl(
                            timeline_path,
                            {"phase": "object_change", "t": round(time.monotonic() - start, 3), "changes": changes},
                        )
                        if waiting_for_first_hit and find_life_drop(changes, args.tralu_object_index) is not None:
                            waiting_for_first_hit = False
                            second_due = time.monotonic() + args.second_after_tralu_hit_delay_sec
                            write_jsonl(
                                timeline_path,
                                {
                                    "phase": "first_tralu_life_drop_seen",
                                    "t": round(time.monotonic() - start, 3),
                                    "second_due_delay_sec": args.second_after_tralu_hit_delay_sec,
                                },
                            )
                    previous_objects = current_objects
                    write_jsonl(
                        timeline_path,
                        {
                            "phase": "sample",
                            "t": round(time.monotonic() - start, 3),
                            "globals": globals_row,
                            "extras": active_extras(reader),
                        },
                    )
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
        "schema": "phase5-magic-ball-tralu-sequence-v1",
        "save": str(save),
        "hold_sec": args.hold_sec,
        "ready_delay_sec": args.ready_delay_sec,
        "set_normal_mode": args.set_normal_mode,
        "select_magic_ball": args.select_magic_ball,
        "second_throw_delay_sec": args.second_throw_delay_sec,
        "second_after_projectile_clear": args.second_after_projectile_clear,
        "second_recovery_delay_sec": args.second_recovery_delay_sec,
        "second_after_tralu_hit": args.second_after_tralu_hit,
        "second_after_tralu_hit_delay_sec": args.second_after_tralu_hit_delay_sec,
        "second_after_magic_ball_return": args.second_after_magic_ball_return,
        "second_after_magic_ball_return_delay_sec": args.second_after_magic_ball_return_delay_sec,
        "observe_sec": args.observe_sec,
        "timeline": str(timeline_path),
        **summarize_life(timeline_path),
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the narrow Tralu Magic Ball sequence experiment.")
    parser.add_argument("--exe", default=str(DEFAULT_GAME_EXE))
    parser.add_argument("--save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--hold-sec", type=float, default=0.75)
    parser.add_argument("--second-throw-delay-sec", type=float, default=0.5)
    parser.add_argument("--second-after-projectile-clear", action="store_true")
    parser.add_argument("--second-recovery-delay-sec", type=float, default=0.2)
    parser.add_argument("--projectile-cycle-timeout-sec", type=float, default=4.0)
    parser.add_argument("--second-after-tralu-hit", action="store_true")
    parser.add_argument("--second-after-tralu-hit-delay-sec", type=float, default=0.5)
    parser.add_argument("--tralu-object-index", type=int, default=3)
    parser.add_argument("--second-after-magic-ball-return", action="store_true")
    parser.add_argument("--second-after-magic-ball-return-delay-sec", type=float, default=0.2)
    parser.add_argument("--observe-sec", type=float, default=5.0)
    parser.add_argument("--poll-sec", type=float, default=0.02)
    parser.add_argument("--loaded-state-timeout-sec", type=float, default=2.0)
    parser.add_argument("--ready-delay-sec", type=float, default=0.0)
    parser.add_argument("--splash-timeout-sec", type=float, default=8.0)
    parser.add_argument("--post-splash-timeout-sec", type=float, default=8.0)
    parser.add_argument("--leave-running", action="store_true")
    parser.add_argument("--prehold-first-throw", action="store_true")
    parser.add_argument("--set-normal-mode", action="store_true")
    parser.add_argument("--select-magic-ball", action="store_true")
    return parser.parse_args()


def main() -> int:
    print(json.dumps(run(parse_args()), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
