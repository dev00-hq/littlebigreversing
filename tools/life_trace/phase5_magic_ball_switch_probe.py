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

from heading_inject import HeadingInjector, describe_beta
from life_trace_shared import DEFAULT_GAME_EXE
from life_trace_windows import WindowCapture, WindowInput
from phase5_magic_ball_throw_probe import active_extras, snapshot_globals
from phase5_magic_ball_tralu_sequence import (
    object_changes,
    object_snapshots,
    interesting_object,
    kill_existing_lba2,
)
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition
from secret_room_door_watch import ProcessReader


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAVE = DEFAULT_GAME_EXE.parent / "SAVE" / "moon-switches-room.LBA"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_magic_ball_switch_probe"

VK_OEM_PERIOD = 0xBE
VK_1 = 0x31
VK_F5 = 0x74


def write_jsonl(path: Path, row: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, separators=(",", ":")) + "\n")


@contextlib.contextmanager
def hidden_autosave(save_dir: Path) -> Iterator[dict[str, Any]]:
    autosave_path = save_dir / "autosave.lba"
    state: dict[str, Any] = {"hidden": False}
    if not autosave_path.exists():
        try:
            yield state
        finally:
            if autosave_path.exists():
                preserved = save_dir / f"autosave.lba.generated-phase5-switch-probe-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
                autosave_path.replace(preserved)
                state["preserved_generated"] = str(preserved)
        return

    hidden_path = save_dir / f"autosave.lba.phase5-switch-probe-hidden-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    autosave_path.replace(hidden_path)
    state = {"hidden": True, "hidden_path": str(hidden_path)}
    try:
        yield state
    finally:
        if autosave_path.exists():
            preserved = save_dir / f"autosave.lba.generated-phase5-switch-probe-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
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
    time.sleep(0.12)


def wait_for_loaded_state(reader: ProcessReader, *, timeout_sec: float, poll_sec: float) -> dict[str, int]:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        globals_row = snapshot_globals(reader)
        hero = object_snapshots(reader)[0]
        if hero["life_point"] > 0 and globals_row["magic_ball_flag"] == 1:
            return globals_row
        time.sleep(max(0.005, poll_sec))
    raise RuntimeError(f"loaded save state did not become readable within {timeout_sec:g} seconds")


def projectile_active(reader: ProcessReader) -> bool:
    return any(extra["sprite"] >= 0 for extra in active_extras(reader))


def wait_for_projectile_clear(reader: ProcessReader, timeline_path: Path, start: float, *, timeout_sec: float, poll_sec: float) -> None:
    deadline = time.monotonic() + timeout_sec
    saw_active = False
    while time.monotonic() < deadline:
        active = projectile_active(reader)
        t = round(time.monotonic() - start, 3)
        if active and not saw_active:
            saw_active = True
            write_jsonl(timeline_path, {"phase": "projectile_active", "t": t, "extras": active_extras(reader)})
        if saw_active and not active:
            write_jsonl(timeline_path, {"phase": "projectile_cleared", "t": t})
            return
        time.sleep(max(0.005, poll_sec))
    write_jsonl(timeline_path, {"phase": "projectile_clear_timeout", "t": round(time.monotonic() - start, 3), "saw_active": saw_active})


def parse_beta_csv(value: str) -> list[int | None]:
    result: list[int | None] = []
    for raw in value.split(","):
        item = raw.strip()
        if not item or item.lower() == "current":
            result.append(None)
        else:
            result.append(int(item, 0) % 4096)
    return result


def run(args: argparse.Namespace) -> dict[str, Any]:
    exe = Path(args.exe).resolve()
    save = Path(args.save).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    timeline_path = out_dir / "timeline.jsonl"
    timeline_path.write_text("", encoding="utf-8")

    betas = parse_beta_csv(args.betas)
    kill_existing_lba2()
    capture = WindowCapture()
    input_tool = WindowInput()
    process: subprocess.Popen[bytes] | None = None
    screenshots: list[str] = []

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
            injector = HeadingInjector(pid=process.pid)
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

                initial_objects = object_snapshots(reader)
                write_jsonl(
                    timeline_path,
                    {
                        "phase": "initial_objects",
                        "t": round(time.monotonic() - start, 3),
                        "objects": [row for row in initial_objects if interesting_object(row)],
                    },
                )
                if not args.no_screenshots:
                    path = out_dir / "01_initial.png"
                    capture.capture(process.pid, path, timeout_sec=10.0)
                    screenshots.append(str(path))

                previous_objects = initial_objects
                for throw_index, beta in enumerate(betas, start=1):
                    if beta is not None:
                        heading = injector.force_heading_beta(beta, sustain_ms=args.heading_sustain_ms)
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "heading_for_throw",
                                "throw_index": throw_index,
                                "t": round(time.monotonic() - start, 3),
                                "target_beta": beta,
                                "target_beta_debug": describe_beta(beta),
                                "heading": heading,
                            },
                        )
                    else:
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "heading_for_throw",
                                "throw_index": throw_index,
                                "t": round(time.monotonic() - start, 3),
                                "target_beta": None,
                                "heading": injector.snapshot(),
                            },
                        )

                    before_throw = object_snapshots(reader)
                    write_jsonl(
                        timeline_path,
                        {
                            "phase": "before_throw",
                            "throw_index": throw_index,
                            "t": round(time.monotonic() - start, 3),
                            "globals": snapshot_globals(reader),
                            "objects": [row for row in before_throw if interesting_object(row)],
                        },
                    )
                    hold_key(input_tool, window.hwnd, VK_OEM_PERIOD, args.hold_sec)
                    write_jsonl(timeline_path, {"phase": "throw_released", "throw_index": throw_index, "t": round(time.monotonic() - start, 3)})

                    deadline = time.monotonic() + args.per_throw_observe_sec
                    while time.monotonic() < deadline:
                        current_objects = object_snapshots(reader)
                        changes = object_changes(previous_objects, current_objects)
                        if changes:
                            write_jsonl(
                                timeline_path,
                                {
                                    "phase": "object_change",
                                    "throw_index": throw_index,
                                    "t": round(time.monotonic() - start, 3),
                                    "changes": changes,
                                },
                            )
                        previous_objects = current_objects
                        write_jsonl(
                            timeline_path,
                            {
                                "phase": "sample",
                                "throw_index": throw_index,
                                "t": round(time.monotonic() - start, 3),
                                "globals": snapshot_globals(reader),
                                "extras": active_extras(reader),
                            },
                        )
                        time.sleep(max(0.005, args.poll_sec))

                    wait_for_projectile_clear(
                        reader,
                        timeline_path,
                        start,
                        timeout_sec=args.projectile_clear_timeout_sec,
                        poll_sec=args.poll_sec,
                    )
                    time.sleep(args.between_throw_sec)

                if not args.no_screenshots:
                    path = out_dir / "02_final.png"
                    capture.capture(process.pid, path, timeout_sec=10.0)
                    screenshots.append(str(path))
            finally:
                injector.close()
                reader.close()
        finally:
            if process is not None and not args.leave_running:
                process.terminate()
                try:
                    process.wait(timeout=3.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5.0)

    object_event_count = 0
    changed_indices: set[int] = set()
    for line in timeline_path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        if row.get("phase") == "object_change":
            object_event_count += 1
            for change in row.get("changes", []):
                changed_indices.add(int(change["index"]))

    summary = {
        "schema": "phase5-magic-ball-switch-probe-v1",
        "save": str(save),
        "betas": betas,
        "hold_sec": args.hold_sec,
        "object_event_count": object_event_count,
        "changed_object_indices": sorted(changed_indices),
        "timeline": str(timeline_path),
        "screenshots": screenshots,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe Magic Ball switch activation in the Emerald Moon switches room.")
    parser.add_argument("--exe", default=str(DEFAULT_GAME_EXE))
    parser.add_argument("--save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--betas", default="current", help="Comma-separated beta list; use 'current' for the save heading.")
    parser.add_argument("--hold-sec", type=float, default=0.75)
    parser.add_argument("--per-throw-observe-sec", type=float, default=1.5)
    parser.add_argument("--between-throw-sec", type=float, default=0.25)
    parser.add_argument("--projectile-clear-timeout-sec", type=float, default=3.0)
    parser.add_argument("--poll-sec", type=float, default=0.02)
    parser.add_argument("--loaded-state-timeout-sec", type=float, default=2.0)
    parser.add_argument("--ready-delay-sec", type=float, default=0.0)
    parser.add_argument("--splash-timeout-sec", type=float, default=12.0)
    parser.add_argument("--post-splash-timeout-sec", type=float, default=8.0)
    parser.add_argument("--heading-sustain-ms", type=int, default=80)
    parser.add_argument("--leave-running", action="store_true")
    parser.add_argument("--set-normal-mode", action="store_true")
    parser.add_argument("--select-magic-ball", action="store_true")
    parser.add_argument("--no-screenshots", action="store_true")
    return parser.parse_args()


def main() -> int:
    print(json.dumps(run(parse_args()), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
