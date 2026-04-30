from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from life_trace_shared import DEFAULT_GAME_EXE
from life_trace_windows import WindowCapture, WindowInput
from phase5_magic_ball_switch_probe import (
    VK_1,
    VK_F5,
    VK_OEM_PERIOD,
    hidden_autosave,
    hold_key,
    press_key,
    stage_save,
    wait_for_loaded_state,
    write_jsonl,
)
from phase5_magic_ball_tralu_sequence import kill_existing_lba2
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition
from secret_room_door_watch import ProcessReader


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_magic_ball_cdb_agent_watch"


def parse_address(text: str) -> int:
    return int(text, 0)


def read_int(reader: ProcessReader, address: int, size: int) -> int:
    return reader.read_int(address, size) & ((1 << (size * 8)) - 1)


def run_watch(
    *,
    pid: int,
    address: int,
    size: int,
    out_path: Path,
    capture_root: Path,
    timeout_sec: float,
    disasm_count: int,
    stack_count: int,
) -> subprocess.Popen[bytes]:
    cdb_agent = shutil.which("cdb-agent")
    if cdb_agent is None:
        raise RuntimeError("cdb-agent was not found on PATH")
    capture_root.mkdir(parents=True, exist_ok=True)
    return subprocess.Popen(
        [
            cdb_agent,
            "--json",
            "--out",
            str(out_path),
            "watch",
            "write",
            "--pid",
            str(pid),
            "--address",
            f"0x{address:08X}",
            "--size",
            str(size),
            "--wow64",
            "--timeout-sec",
            str(timeout_sec),
            "--disasm-count",
            str(disasm_count),
            "--stack-count",
            str(stack_count),
            "--capture-root",
            str(capture_root),
        ],
        cwd=str(REPO_ROOT),
        stdout=out_path.with_suffix(".stdout.txt").open("wb"),
        stderr=out_path.with_suffix(".stderr.txt").open("wb"),
    )


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


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
            try:
                ready_globals = wait_for_loaded_state(reader, timeout_sec=args.loaded_state_timeout_sec, poll_sec=args.poll_sec)
                press_key(input_tool, window.hwnd, VK_F5)
                press_key(input_tool, window.hwnd, VK_1)
                if args.ready_delay_sec > 0:
                    time.sleep(args.ready_delay_sec)

                before = read_int(reader, args.address, args.size)
                write_jsonl(
                    timeline_path,
                    {
                        "phase": "ready_before_watch",
                        "globals": ready_globals,
                        "watch_name": args.watch_name,
                        "address": f"0x{args.address:08X}",
                        "size": args.size,
                        "value": before,
                    },
                )
                initial_path = out_dir / "01_initial.png"
                capture.capture(process.pid, initial_path, timeout_sec=10.0)
                screenshots.append(str(initial_path))

                watch_out = out_dir / "cdb_agent_watch.json"
                watch_proc = run_watch(
                    pid=process.pid,
                    address=args.address,
                    size=args.size,
                    out_path=watch_out,
                    capture_root=out_dir / "cdb-agent-captures",
                    timeout_sec=args.watch_timeout_sec,
                    disasm_count=args.disasm_count,
                    stack_count=args.stack_count,
                )
                time.sleep(args.watch_arm_delay_sec)
                write_jsonl(timeline_path, {"phase": "watch_started", "cdb_agent_pid": watch_proc.pid})
                hold_key(input_tool, window.hwnd, VK_OEM_PERIOD, args.hold_sec)
                write_jsonl(timeline_path, {"phase": "throw_released"})
                try:
                    watch_proc.wait(timeout=args.watch_timeout_sec + 10.0)
                except subprocess.TimeoutExpired:
                    watch_proc.kill()
                    watch_proc.wait(timeout=5.0)
                try:
                    after: dict[str, Any] = {"value": read_int(reader, args.address, args.size)}
                    final_path = out_dir / "02_final.png"
                    capture.capture(process.pid, final_path, timeout_sec=10.0)
                    screenshots.append(str(final_path))
                except OSError as error:
                    after = {"read_error": str(error)}
                write_jsonl(timeline_path, {"phase": "after_watch", "watch_returncode": watch_proc.returncode, **after})
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

    watch_payload = load_json(out_dir / "cdb_agent_watch.json") if (out_dir / "cdb_agent_watch.json").exists() else None
    summary = {
        "schema": "phase5-magic-ball-cdb-agent-watch-v1",
        "save": str(save),
        "watch_name": args.watch_name,
        "watched_address": f"0x{args.address:08X}",
        "watched_size": args.size,
        "timeline": str(timeline_path),
        "watch_payload": watch_payload,
        "screenshots": screenshots,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Arm cdb-agent watch write, throw Magic Ball, and capture the writer.")
    parser.add_argument("--exe", default=str(DEFAULT_GAME_EXE))
    parser.add_argument("--save", required=True)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--watch-name", required=True)
    parser.add_argument("--address", type=parse_address, required=True)
    parser.add_argument("--size", type=int, choices=(1, 2, 4, 8), required=True)
    parser.add_argument("--hold-sec", type=float, default=0.75)
    parser.add_argument("--poll-sec", type=float, default=0.02)
    parser.add_argument("--loaded-state-timeout-sec", type=float, default=8.0)
    parser.add_argument("--ready-delay-sec", type=float, default=0.0)
    parser.add_argument("--splash-timeout-sec", type=float, default=60.0)
    parser.add_argument("--post-splash-timeout-sec", type=float, default=12.0)
    parser.add_argument("--watch-arm-delay-sec", type=float, default=2.0)
    parser.add_argument("--watch-timeout-sec", type=float, default=10.0)
    parser.add_argument("--disasm-count", type=int, default=8)
    parser.add_argument("--stack-count", type=int, default=12)
    parser.add_argument("--leave-running", action="store_true")
    return parser.parse_args()


def main() -> int:
    print(json.dumps(run(parse_args()), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
