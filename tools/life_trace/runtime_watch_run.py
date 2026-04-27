from __future__ import annotations

import argparse
import contextlib
import ctypes
import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterator

from life_trace_windows import WindowCapture, WindowInput
from secret_room_door_watch import ProcessReader, snapshot as transition_snapshot


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GAME_DIR = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2"
DEFAULT_EXE = DEFAULT_GAME_DIR / "LBA2.EXE"
DEFAULT_SAVE = REPO_ROOT / "work" / "saves" / "scene2-bg1-key-midpoint-facing-key.LBA"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "runtime_watch_run"

PROCESS_VM_READ = 0x0010
PROCESS_VM_WRITE = 0x0020
PROCESS_VM_OPERATION = 0x0008
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000

NB_LITTLE_KEYS = 0x0049A0A6
HERO_OLD_X = 0x0049A1A4
HERO_OLD_Y = 0x0049A1A8
HERO_OLD_Z = 0x0049A1AC
HERO_X = 0x0049A1DA
HERO_Y = 0x0049A1DE
HERO_Z = 0x0049A1E2
HERO_BETA = 0x0049A1EA
HERO_OLD_BETA = 0x0049A302
HERO_BOUND_ANGLE_SPEED = 0x0049A306
HERO_BOUND_ANGLE_ACC = 0x0049A30A
HERO_BOUND_ANGLE_LAST_TIMER = 0x0049A30E
HERO_BOUND_ANGLE_CUR = 0x0049A312
HERO_BOUND_ANGLE_END = 0x0049A316
CANDIDATE_X = 0x0049A0A8
CANDIDATE_Y = 0x0049A0AC
CANDIDATE_Z = 0x0049A0B0

VK_UP = 0x26

EXPECTED_0013_LOAD = {
    "active_cube": 0,
    "hero_x": 3478,
    "hero_y": 2048,
    "hero_z": 4772,
    "hero_beta": 3584,
    "nb_little_keys": 0,
}

PHASE5_0013_DOOR_POSE = {
    "x": 3050,
    "y": 2048,
    "z": 4034,
    "beta": 2583,
}


@dataclass(frozen=True)
class ScreenshotRecord:
    label: str
    path: str
    window_title: str


class ProcessMemory:
    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self.handle = self.kernel32.OpenProcess(
            PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION | PROCESS_QUERY_LIMITED_INFORMATION,
            False,
            pid,
        )
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())

    def close(self) -> None:
        if self.handle:
            self.kernel32.CloseHandle(self.handle)
            self.handle = 0

    def __enter__(self) -> "ProcessMemory":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def write_i32(self, address: int, value: int) -> None:
        payload = ctypes.c_int32(value)
        self._write(address, ctypes.byref(payload), ctypes.sizeof(payload))

    def write_u16(self, address: int, value: int) -> None:
        payload = ctypes.c_uint16(value % 4096)
        self._write(address, ctypes.byref(payload), ctypes.sizeof(payload))

    def write_u8(self, address: int, value: int) -> None:
        payload = ctypes.c_uint8(value)
        self._write(address, ctypes.byref(payload), ctypes.sizeof(payload))

    def _write(self, address: int, payload, size: int) -> None:
        written = ctypes.c_size_t()
        ok = self.kernel32.WriteProcessMemory(
            self.handle,
            ctypes.c_void_p(address),
            payload,
            size,
            ctypes.byref(written),
        )
        if not ok or written.value != size:
            raise ctypes.WinError(ctypes.get_last_error())


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch LBA2 with the WinMM runtime watcher and capture bounded Phase 5 evidence."
    )
    parser.add_argument("--scenario", choices=("phase5-0013-door",), default="phase5-0013-door")
    parser.add_argument("--exe", default=str(DEFAULT_EXE))
    parser.add_argument("--launch-save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--startup-enter-delay-sec", type=float, default=10.0)
    parser.add_argument("--post-enter-settle-sec", type=float, default=3.0)
    parser.add_argument("--door-walk-sec", type=float, default=4.0)
    parser.add_argument("--poll-sec", type=float, default=0.05)
    parser.add_argument("--keep-process", action="store_true")
    parser.add_argument("--no-hide-autosave", action="store_true")
    return parser.parse_args(argv)


def kill_processes() -> None:
    for image in ("LBA2.EXE", "cdb.exe"):
        subprocess.run(["taskkill", "/IM", image, "/F"], capture_output=True, text=True, check=False)


@contextlib.contextmanager
def autosave_hidden(save_dir: Path, *, enabled: bool) -> Iterator[dict[str, str | bool]]:
    autosave = save_dir / "autosave.lba"
    backup = save_dir / f"autosave.lba.runtime-watch-bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    state: dict[str, str | bool] = {"enabled": enabled, "moved": False}
    if enabled and autosave.exists():
        autosave.replace(backup)
        state.update({"moved": True, "backup": str(backup)})
    try:
        yield state
    finally:
        if state["moved"]:
            if autosave.exists():
                preserved = save_dir / f"autosave.lba.generated-runtime-watch-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
                autosave.replace(preserved)
                state["preserved_generated"] = str(preserved)
            backup.replace(autosave)


def stage_save(exe: Path, source_save: Path) -> Path:
    save_dir = exe.parent / "SAVE"
    save_dir.mkdir(parents=True, exist_ok=True)
    runtime_save = save_dir / source_save.name
    if source_save.resolve() != runtime_save.resolve():
        shutil.copy2(source_save, runtime_save)
    return Path("SAVE") / source_save.name


def read_snapshot(pid: int) -> dict[str, object]:
    with ProcessReader(pid) as reader:
        return transition_snapshot(reader.read_int)


def assert_expected_load(row: dict[str, object]) -> None:
    mismatches = {
        key: {"expected": expected, "actual": row.get(key)}
        for key, expected in EXPECTED_0013_LOAD.items()
        if int(row.get(key, -999999)) != expected
    }
    if mismatches:
        raise RuntimeError(f"direct save launch did not load the expected 0013 save: {json.dumps(mismatches)}")


def capture(capture_tool: WindowCapture, pid: int, out_dir: Path, label: str) -> ScreenshotRecord:
    path = out_dir / f"{label}.png"
    window = capture_tool.capture(pid, path, timeout_sec=10.0)
    return ScreenshotRecord(label=label, path=str(path), window_title=window.title)


def write_jsonl(path: Path, payload: dict[str, object]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, separators=(",", ":")) + "\n")


def set_hero_pose(memory: ProcessMemory, *, x: int, y: int, z: int, beta: int) -> None:
    for address, value in (
        (HERO_X, x),
        (HERO_Y, y),
        (HERO_Z, z),
        (HERO_OLD_X, x),
        (HERO_OLD_Y, y),
        (HERO_OLD_Z, z),
        (CANDIDATE_X, x),
        (CANDIDATE_Y, y),
        (CANDIDATE_Z, z),
    ):
        memory.write_i32(address, value)
    memory.write_u16(HERO_BETA, beta)
    memory.write_i32(HERO_OLD_BETA, beta)
    for address, value in (
        (HERO_BOUND_ANGLE_SPEED, 0),
        (HERO_BOUND_ANGLE_ACC, 0),
        (HERO_BOUND_ANGLE_LAST_TIMER, 0),
        (HERO_BOUND_ANGLE_CUR, beta),
        (HERO_BOUND_ANGLE_END, beta),
    ):
        memory.write_i32(address, value)


def parse_runtime_watch_log(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    events = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip():
            continue
        events.append(json.loads(line))
    return events


def run_phase5_0013_door(args: argparse.Namespace) -> dict[str, object]:
    exe = Path(args.exe).resolve()
    launch_save = Path(args.launch_save).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "events.jsonl"
    summary_path = out_dir / "summary.json"
    runtime_watch_log = out_dir / "lba2_runtime_watch.log"
    for path in (jsonl_path, summary_path, runtime_watch_log):
        path.unlink(missing_ok=True)

    save_arg = stage_save(exe, launch_save)
    kill_processes()

    env = os.environ.copy()
    env["LBA2_RUNTIME_WATCH"] = "1"
    env["LBA2_RUNTIME_WATCH_LOG"] = str(runtime_watch_log)
    env["LBA2_RUNTIME_WATCH_POLL_MS"] = "25"

    screenshots: list[ScreenshotRecord] = []
    observations: list[dict[str, object]] = []
    process = None
    autosave_state: dict[str, str | bool] = {}
    verdict = "runtime_error"
    reason = "run did not complete"

    with autosave_hidden(exe.parent / "SAVE", enabled=not args.no_hide_autosave) as hidden:
        autosave_state = dict(hidden)
        process = subprocess.Popen([str(exe), str(save_arg)], cwd=str(exe.parent), env=env)
        write_jsonl(jsonl_path, {"phase": "launched", "pid": process.pid, "argv1": str(save_arg), "autosave": autosave_state})
        try:
            capture_tool = WindowCapture()
            input_tool = WindowInput()
            window = capture_tool.wait_for_window(process.pid, timeout_sec=30.0)
            time.sleep(max(0.0, args.startup_enter_delay_sec))
            input_tool.send_enter(window.hwnd)
            time.sleep(max(0.0, args.post_enter_settle_sec))

            screenshots.append(capture(capture_tool, process.pid, out_dir, "01_loaded"))
            loaded = read_snapshot(process.pid)
            observations.append({"phase": "loaded", "snapshot": loaded})
            write_jsonl(jsonl_path, observations[-1])
            assert_expected_load(loaded)

            with ProcessMemory(process.pid) as memory:
                memory.write_u8(NB_LITTLE_KEYS, 1)
                set_hero_pose(memory, **PHASE5_0013_DOOR_POSE)

            time.sleep(0.2)
            screenshots.append(capture(capture_tool, process.pid, out_dir, "02_pre_door_with_key"))
            pre_door = read_snapshot(process.pid)
            observations.append({"phase": "pre_door_with_key", "snapshot": pre_door})
            write_jsonl(jsonl_path, observations[-1])

            deadline = time.monotonic() + max(0.1, args.door_walk_sec)
            input_tool.key_down(window.hwnd, VK_UP)
            try:
                while time.monotonic() < deadline:
                    row = read_snapshot(process.pid)
                    observations.append({"phase": "walking_to_door", "snapshot": row})
                    write_jsonl(jsonl_path, observations[-1])
                    if int(row["active_cube"]) == 1:
                        break
                    time.sleep(max(0.01, args.poll_sec))
            finally:
                input_tool.key_up(VK_UP)

            time.sleep(0.5)
            screenshots.append(capture(capture_tool, process.pid, out_dir, "03_after_door_walk"))
            final_snapshot = read_snapshot(process.pid)
            observations.append({"phase": "final", "snapshot": final_snapshot})
            write_jsonl(jsonl_path, observations[-1])

            if int(final_snapshot["active_cube"]) == 1:
                verdict = "phase5_0013_cellar_transition_observed"
                reason = "keyed door path reached active cube 1 with runtime watcher enabled"
            else:
                verdict = "phase5_0013_cellar_transition_not_observed"
                reason = f"final active_cube={final_snapshot['active_cube']}"
        finally:
            if process is not None and process.poll() is None and not args.keep_process:
                process.terminate()
                try:
                    process.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5.0)

    watch_events = parse_runtime_watch_log(runtime_watch_log)
    life_loss_events = [event for event in watch_events if event.get("event") == "life_loss_detected"]
    if not watch_events:
        verdict = "runtime_watch_log_missing"
        reason = "the game scenario ran, but the WinMM runtime watcher did not write any log events"
    summary: dict[str, object] = {
        "scenario": args.scenario,
        "verdict": verdict,
        "reason": reason,
        "pid": None if process is None else process.pid,
        "process_returncode": None if process is None else process.returncode,
        "exe": str(exe),
        "argv1": str(save_arg),
        "launch_save": str(launch_save),
        "autosave": autosave_state,
        "runtime_watch_log": str(runtime_watch_log),
        "runtime_watch_events": watch_events,
        "life_loss_detected": bool(life_loss_events),
        "life_loss_events": life_loss_events,
        "screenshots": [record.__dict__ for record in screenshots],
        "observations": observations,
    }
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    summary = run_phase5_0013_door(args)
    print(json.dumps(summary, indent=2))
    return 0 if str(summary["verdict"]).endswith("_observed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
