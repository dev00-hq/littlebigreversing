from __future__ import annotations

import argparse
import contextlib
import json
import shutil
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterator

from life_trace_windows import WindowCapture, WindowInput
from life_trace_shared import DEFAULT_GAME_EXE
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition
from phase5_magic_ball_throw_probe import active_extras, snapshot_globals
from secret_room_door_watch import ProcessReader


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAVE_NAME = "throw-ball.LBA"
DEFAULT_SAVE = DEFAULT_GAME_EXE.parent / "SAVE" / DEFAULT_SAVE_NAME
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_magic_ball_drive_probe"

VK_OEM_PERIOD = 0xBE
VK_1 = 0x31
VK_F5 = 0x74
VK_F6 = 0x75
VK_F7 = 0x76
VK_F8 = 0x77
VK_MENU = 0x12

MODE_KEYS = {
    "normal": VK_F5,
    "sporty": VK_F6,
    "aggressive": VK_F7,
    "discreet": VK_F8,
}

KEYS = {
    "period": VK_OEM_PERIOD,
    "alt": VK_MENU,
}

EXTRA_MAGIC_BALL = 1 << 15
EXTRA_TRAINEE = 1 << 19


@dataclass(frozen=True)
class AttemptResult:
    hold_sec: float
    launched: bool
    first_projectile_t: float | None
    first_projectile: dict[str, int] | None
    initial_globals: dict[str, int]
    final_globals: dict[str, int]
    samples: list[dict[str, Any]]
    recall_pressed_t: float | None


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
        yield state
        return

    hidden_path = save_dir / f"autosave.lba.phase5-magic-ball-drive-hidden-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    autosave_path.replace(hidden_path)
    state = {"hidden": True, "hidden_path": str(hidden_path)}
    try:
        yield state
    finally:
        if autosave_path.exists():
            preserved = save_dir / f"autosave.lba.generated-phase5-magic-ball-drive-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
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


def launch_save(exe: Path, save: Path, capture_tool: WindowCapture, input_tool: WindowInput) -> subprocess.Popen[bytes]:
    save_arg = stage_save(save, exe.parent / "SAVE")
    process = subprocess.Popen(direct_launch_argv(exe, save_arg), cwd=str(exe.parent))
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
    return process


def press_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float = 0.08) -> None:
    input_tool.key_down(hwnd, virtual_key)
    time.sleep(hold_sec)
    input_tool.key_up(virtual_key)
    time.sleep(0.15)


def hold_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float) -> None:
    input_tool.key_down(hwnd, virtual_key)
    time.sleep(hold_sec)
    input_tool.key_up(virtual_key)


def first_projectile(extras: list[dict[str, int]]) -> dict[str, int] | None:
    for extra in extras:
        if extra["sprite"] >= 0:
            return extra
    return None


def tracked_magic_ball(sample: dict[str, Any]) -> dict[str, int] | None:
    magic_ball_index = int(sample["globals"].get("magic_ball_index", -1))
    if 0 <= magic_ball_index < 50:
        for extra in sample["extras"]:
            if extra["index"] == magic_ball_index:
                return extra
    candidates = [
        extra
        for extra in sample["extras"]
        if extra["flags"] & EXTRA_MAGIC_BALL and not extra["flags"] & EXTRA_TRAINEE
    ]
    return candidates[0] if candidates else None


def globals_changed(before: dict[str, int], after: dict[str, int]) -> dict[str, dict[str, int]]:
    changes: dict[str, dict[str, int]] = {}
    for key, value in after.items():
        old = before.get(key)
        if old != value:
            changes[key] = {"before": int(old) if old is not None else None, "after": int(value)}
    return changes


def summarize_lifecycle(result: AttemptResult) -> dict[str, Any]:
    active_samples: list[dict[str, Any]] = []
    first_active: dict[str, Any] | None = None
    last_active: dict[str, Any] | None = None
    first_clear_after_active: dict[str, Any] | None = None
    previous_globals = result.initial_globals
    global_changes: list[dict[str, Any]] = []

    for sample in result.samples:
        changes = globals_changed(previous_globals, sample["globals"])
        if changes:
            global_changes.append({"t": sample["t"], "changes": changes})
            previous_globals = sample["globals"]

        projectile = first_projectile(sample["extras"])
        if projectile is not None:
            if first_active is None:
                first_active = sample
            last_active = sample
            active_samples.append(sample)
        elif first_active is not None and first_clear_after_active is None:
            first_clear_after_active = sample

    return {
        "sample_count": len(result.samples),
        "active_sample_count": len(active_samples),
        "first_active_t": first_active["t"] if first_active else None,
        "last_active_t": last_active["t"] if last_active else None,
        "first_clear_after_active_t": first_clear_after_active["t"] if first_clear_after_active else None,
        "cleared_before_monitor_end": first_active is not None and first_clear_after_active is not None,
        "first_active_extras": first_active["extras"] if first_active else [],
        "last_active_extras": last_active["extras"] if last_active else [],
        "first_clear_after_active_extras": first_clear_after_active["extras"] if first_clear_after_active else None,
        "global_change_count": len(global_changes),
        "global_changes": global_changes[:40],
        "magic_ball_events": infer_magic_ball_events(result),
    }


def changed_extra_fields(previous: dict[str, int], current: dict[str, int], fields: tuple[str, ...]) -> dict[str, dict[str, int]]:
    changes: dict[str, dict[str, int]] = {}
    for field in fields:
        old = previous.get(field)
        new = current.get(field)
        if old != new:
            changes[field] = {"before": int(old) if old is not None else None, "after": int(new) if new is not None else None}
    return changes


def sign_flips(previous: dict[str, int], current: dict[str, int]) -> list[str]:
    flips: list[str] = []
    for field in ("vx", "vy", "vz"):
        old = int(previous.get(field, 0))
        new = int(current.get(field, 0))
        if old != 0 and new != 0 and old * new < 0:
            flips.append(field)
    return flips


def infer_magic_ball_events(result: AttemptResult) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    previous_sample: dict[str, Any] | None = None
    previous_ball: dict[str, int] | None = None
    previous_globals = result.initial_globals

    for sample in result.samples:
        current_ball = tracked_magic_ball(sample)
        globals_row = sample["globals"]
        count_before = previous_globals.get("magic_ball_count")
        count_after = globals_row.get("magic_ball_count")
        if count_before != count_after:
            events.append(
                {
                    "kind": "magic_ball_count_change",
                    "t": sample["t"],
                    "before": count_before,
                    "after": count_after,
                }
            )

        if previous_ball is None and current_ball is not None:
            events.append(
                {
                    "kind": "projectile_active",
                    "t": sample["t"],
                    "index": current_ball["index"],
                    "sprite": current_ball["sprite"],
                    "pos": [current_ball["pos_x"], current_ball["pos_y"], current_ball["pos_z"]],
                    "velocity": [current_ball["vx"], current_ball["vy"], current_ball["vz"]],
                    "flags": current_ball["flags"],
                }
            )
        elif previous_ball is not None and current_ball is None:
            events.append(
                {
                    "kind": "projectile_cleared",
                    "t": sample["t"],
                    "previous_index": previous_ball["index"],
                    "previous_sprite": previous_ball["sprite"],
                }
            )
        elif previous_ball is not None and current_ball is not None:
            flips = sign_flips(previous_ball, current_ball)
            kinematic_changes = changed_extra_fields(
                previous_ball,
                current_ball,
                ("index", "sprite", "pos_x", "pos_y", "pos_z", "org_x", "org_y", "org_z", "vx", "vy", "vz", "timer", "flags"),
            )
            origin_changed = any(field in kinematic_changes for field in ("org_x", "org_y", "org_z"))
            timer_changed = "timer" in kinematic_changes
            row_or_sprite_changed = any(field in kinematic_changes for field in ("index", "sprite"))
            if row_or_sprite_changed:
                events.append(
                    {
                        "kind": "return_or_retarget_inferred",
                        "t": sample["t"],
                        "previous_t": previous_sample["t"] if previous_sample else None,
                        "changes": kinematic_changes,
                    }
                )
            elif flips and origin_changed and timer_changed:
                events.append(
                    {
                        "kind": "bounce_inferred",
                        "t": sample["t"],
                        "previous_t": previous_sample["t"] if previous_sample else None,
                        "index": current_ball["index"],
                        "sign_flips": flips,
                        "changes": kinematic_changes,
                    }
                )

        previous_sample = sample
        previous_ball = current_ball
        previous_globals = globals_row

    return events


def run_attempt(
    *,
    exe: Path,
    save: Path,
    out_dir: Path,
    mode: str,
    key_name: str,
    hold_sec: float,
    monitor_sec: float,
    poll_sec: float,
    recall_after_sec: float | None,
    recall_hold_sec: float,
) -> AttemptResult:
    kill_existing_lba2()
    capture_tool = WindowCapture()
    input_tool = WindowInput()
    process: subprocess.Popen[bytes] | None = None
    jsonl_path = out_dir / f"attempt_{key_name}_{mode}_{hold_sec:.3f}.jsonl"
    jsonl_path.write_text("", encoding="utf-8")
    with hidden_autosave(exe.parent / "SAVE") as autosave_state:
        process = launch_save(exe, save, capture_tool, input_tool)
        try:
            window = capture_tool.wait_for_window(process.pid, timeout_sec=10.0)
            write_jsonl(jsonl_path, {"phase": "launched", "pid": process.pid, "autosave": autosave_state})
            press_key(input_tool, window.hwnd, MODE_KEYS[mode])
            press_key(input_tool, window.hwnd, VK_1)

            reader = ProcessReader(process.pid)
            try:
                initial_globals = snapshot_globals(reader)
                write_jsonl(jsonl_path, {"phase": "before_hold", "globals": initial_globals, "extras": active_extras(reader)})
                hold_key(input_tool, window.hwnd, KEYS[key_name], hold_sec)
                start = time.monotonic()
                samples: list[dict[str, Any]] = []
                first_t: float | None = None
                first: dict[str, int] | None = None
                recall_pressed_t: float | None = None
                while time.monotonic() - start < monitor_sec:
                    time.sleep(max(0.01, poll_sec))
                    t = round(time.monotonic() - start, 3)
                    if recall_after_sec is not None and recall_pressed_t is None and t >= recall_after_sec:
                        hold_key(input_tool, window.hwnd, KEYS[key_name], recall_hold_sec)
                        recall_pressed_t = t
                        write_jsonl(jsonl_path, {"phase": "recall_key", "t": recall_pressed_t, "hold_sec": recall_hold_sec})
                    extras = active_extras(reader)
                    globals_row = snapshot_globals(reader)
                    projectile = first_projectile(extras)
                    if projectile is not None and first is None:
                        first = projectile
                        first_t = t
                    row = {"t": t, "globals": globals_row, "extras": extras}
                    samples.append(row)
                    if projectile is not None or t < 0.2:
                        write_jsonl(jsonl_path, {"phase": "sample", **row})
                final_globals = snapshot_globals(reader)
                write_jsonl(jsonl_path, {"phase": "final", "globals": final_globals, "extras": active_extras(reader)})
            finally:
                reader.close()
        finally:
            if process is not None:
                process.terminate()
                try:
                    process.wait(timeout=3.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5.0)
    return AttemptResult(
        hold_sec=hold_sec,
        launched=first is not None,
        first_projectile_t=first_t,
        first_projectile=first,
        initial_globals=initial_globals,
        final_globals=final_globals,
        samples=samples,
        recall_pressed_t=recall_pressed_t,
    )


def parse_durations(raw: str) -> list[float]:
    return [float(part.strip()) for part in raw.split(",") if part.strip()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Direct-launch throw-ball.LBA and find the minimum weapon-key hold that throws the Magic Ball.")
    parser.add_argument("--exe", default=str(DEFAULT_GAME_EXE))
    parser.add_argument("--save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--mode", choices=tuple(MODE_KEYS), default="normal")
    parser.add_argument("--key", choices=tuple(KEYS), default="period")
    parser.add_argument("--durations", default="0.05,0.10,0.20,0.30,0.50,0.75,1.00")
    parser.add_argument("--monitor-sec", type=float, default=3.0)
    parser.add_argument("--poll-sec", type=float, default=0.02)
    parser.add_argument("--recall-after-sec", type=float, default=None, help="Press the weapon key again this many seconds after release.")
    parser.add_argument("--recall-hold-sec", type=float, default=0.08, help="Hold duration for the forced-return key press.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    exe = Path(args.exe).resolve()
    save = Path(args.save).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    summary_path = out_dir / "summary.json"
    durations = parse_durations(args.durations)
    results: list[dict[str, Any]] = []
    for hold_sec in durations:
        result = run_attempt(
            exe=exe,
            save=save,
            out_dir=out_dir,
            mode=args.mode,
            key_name=args.key,
            hold_sec=hold_sec,
            monitor_sec=args.monitor_sec,
            poll_sec=args.poll_sec,
            recall_after_sec=args.recall_after_sec,
            recall_hold_sec=args.recall_hold_sec,
        )
        results.append(
            {
                "hold_sec": result.hold_sec,
                "launched": result.launched,
                "first_projectile_t": result.first_projectile_t,
                "first_projectile": result.first_projectile,
                "initial_globals": result.initial_globals,
                "final_globals": result.final_globals,
                "recall_pressed_t": result.recall_pressed_t,
                "lifecycle": summarize_lifecycle(result),
            }
        )
        if result.launched:
            break

    first_success = next((row for row in results if row["launched"]), None)
    summary = {
        "schema": "phase5-magic-ball-drive-probe-v1",
        "verdict": "minimum_hold_found" if first_success else "no_throw_observed",
        "mode": args.mode,
        "key": args.key,
        "save": str(save),
        "durations": durations,
        "recall_after_sec": args.recall_after_sec,
        "recall_hold_sec": args.recall_hold_sec,
        "first_success": first_success,
        "results": results,
    }
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if first_success else 1


if __name__ == "__main__":
    raise SystemExit(main())
