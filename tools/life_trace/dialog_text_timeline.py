from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

from dialog_text_dump import (
    DEFAULT_DIAL_READ_CAP,
    DEFAULT_PROCESS_NAME,
    DEFAULT_TEXT_READ_CAP,
    ProcessReadError,
    ProcessReader,
    find_pid_by_name,
    snapshot_dialog_state,
)
from life_trace_windows import WindowCapture, WindowInput
from life_trace_shared import DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC
from scenes.load_game import direct_launch_argv, wait_for_adeline_splash, wait_for_post_splash_transition


DEFAULT_DURATION_SEC = 15.0
DEFAULT_INTERVAL_MS = 100
DEFAULT_STARTUP_WINDOW_TIMEOUT_SEC = 10.0
DEFAULT_SPLASH_TIMEOUT_SEC = 8.0
DEFAULT_DIALOG_ARM_TIMEOUT_SEC = 20.0
DEFAULT_LAUNCH_EXE = (
    Path(__file__).resolve().parents[2]
    / "work"
    / "_innoextract_full"
    / "Speedrun"
    / "Windows"
    / "LBA2_cdrom"
    / "LBA2"
    / "LBA2.EXE"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Continuously sample the pinned dialog globals so auto-progressing dialogs can be "
            "captured without manual page timing."
        )
    )
    parser.add_argument("--process-name", default=DEFAULT_PROCESS_NAME)
    parser.add_argument("--attach-pid", type=int)
    parser.add_argument("--duration-sec", type=float, default=DEFAULT_DURATION_SEC)
    parser.add_argument("--interval-ms", type=int, default=DEFAULT_INTERVAL_MS)
    parser.add_argument("--text-read-cap", type=int, default=DEFAULT_TEXT_READ_CAP)
    parser.add_argument("--dial-read-cap", type=int, default=DEFAULT_DIAL_READ_CAP)
    parser.add_argument("--out", required=True, help="Output JSONL path.")
    parser.add_argument("--changes-only", action="store_true")
    parser.add_argument("--label")
    parser.add_argument("--arm-on-dialog", action="store_true", default=True)
    parser.add_argument("--dialog-arm-timeout-sec", type=float, default=DEFAULT_DIALOG_ARM_TIMEOUT_SEC)
    parser.add_argument("--launch-save", help="Optional save to direct-launch before sampling.")
    parser.add_argument("--launch-exe", default=str(DEFAULT_LAUNCH_EXE))
    parser.add_argument("--startup-window-timeout-sec", type=float, default=DEFAULT_STARTUP_WINDOW_TIMEOUT_SEC)
    parser.add_argument("--splash-timeout-sec", type=float, default=DEFAULT_SPLASH_TIMEOUT_SEC)
    return parser.parse_args()


def snapshot_fingerprint(payload: dict[str, object]) -> str:
    cursor = payload["cursor"]
    globals_snapshot = payload["globals"]
    next_page_split = payload["next_page_split"]
    fingerprint_payload = {
        "dialog_id": globals_snapshot["CurrentDial"],
        "pt_text": globals_snapshot["PtText"],
        "pt_dial": globals_snapshot["PtDial"],
        "cursor_state": cursor["state"],
        "cursor_offset": cursor["pt_dial_minus_pt_text"],
        "decoded_text": payload["decoded_text"],
        "text_before_cursor": next_page_split["text_before_cursor"],
        "text_from_cursor": next_page_split["text_from_cursor"],
    }
    return json.dumps(fingerprint_payload, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


def looks_like_active_dialog(payload: dict[str, object]) -> bool:
    globals_snapshot = payload["globals"]
    decoded_text = str(payload["decoded_text"]).strip()
    current_dial = int(globals_snapshot["CurrentDial"])
    pt_dial = str(globals_snapshot["PtDial"])
    if current_dial != 0:
        return True
    if pt_dial != "0x00000000":
        return True
    if not decoded_text:
        return False
    lowered = decoded_text.lower()
    if lowered in {"new game", "load game", "continue", "options"}:
        return False
    return True


def append_jsonl(path: Path, payload: dict[str, object]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=True) + "\n")


def resolve_pid(args: argparse.Namespace, out_path: Path) -> tuple[int, subprocess.Popen[str] | None]:
    if args.launch_save is None:
        pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name)
        return pid, None

    launch_exe = Path(args.launch_exe).resolve()
    launch_save = Path(args.launch_save).resolve()
    if not launch_exe.exists():
        raise RuntimeError(f"launch exe does not exist: {launch_exe}")
    if not launch_save.exists():
        raise RuntimeError(f"launch save does not exist: {launch_save}")

    proc = subprocess.Popen(direct_launch_argv(launch_exe, launch_save), cwd=str(launch_exe.parent))
    append_jsonl(
        out_path,
        {
            "kind": "status",
            "message": "spawned direct-launch process for timeline capture",
            "pid": proc.pid,
            "launch_save": str(launch_save),
        },
    )

    capture = WindowCapture()
    window_input = WindowInput()
    splash_checksum = wait_for_adeline_splash(
        capture,
        proc.pid,
        startup_window_timeout_sec=args.startup_window_timeout_sec,
        splash_timeout_sec=args.splash_timeout_sec,
    )
    window = capture.wait_for_window(proc.pid, timeout_sec=args.startup_window_timeout_sec)
    window_input.send_enter(window.hwnd)
    wait_for_post_splash_transition(
        capture,
        proc.pid,
        startup_window_timeout_sec=args.startup_window_timeout_sec,
        splash_checksum=splash_checksum,
        post_splash_timeout_sec=DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC,
    )
    append_jsonl(
        out_path,
        {
            "kind": "status",
            "message": "sent Enter to continue past the Adeline splash",
            "pid": proc.pid,
        },
    )
    return proc.pid, proc


def main() -> int:
    args = parse_args()
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("", encoding="utf-8")

    pid, launched_process = resolve_pid(args, out_path)
    deadline = time.monotonic() + max(0.1, args.duration_sec)
    interval_sec = max(0.01, args.interval_ms / 1000.0)
    last_fingerprint: str | None = None
    sample_index = 0

    with ProcessReader(pid) as reader:
        if args.arm_on_dialog:
            arm_deadline = time.monotonic() + max(0.1, args.dialog_arm_timeout_sec)
            while True:
                payload = snapshot_dialog_state(
                    reader,
                    text_read_cap=max(1, args.text_read_cap),
                    dial_read_cap=max(1, args.dial_read_cap),
                )
                payload["pid"] = pid
                payload["process_name"] = args.process_name
                payload["sample_index"] = sample_index
                payload["elapsed_ms"] = 0
                if args.label:
                    payload["label"] = args.label
                if looks_like_active_dialog(payload):
                    append_jsonl(
                        out_path,
                        {
                            "kind": "status",
                            "message": "armed timeline capture on active dialog state",
                            "pid": pid,
                            "current_dial": payload["globals"]["CurrentDial"],
                            "decoded_text": payload["decoded_text"],
                        },
                    )
                    break
                if time.monotonic() > arm_deadline:
                    append_jsonl(
                        out_path,
                        {
                            "kind": "status",
                            "message": "dialog arm timeout expired before active dialog was observed",
                            "pid": pid,
                            "last_decoded_text": payload["decoded_text"],
                            "last_current_dial": payload["globals"]["CurrentDial"],
                        },
                    )
                    break
                sample_index += 1
                time.sleep(interval_sec)
            deadline = time.monotonic() + max(0.1, args.duration_sec)

        while True:
            now = time.monotonic()
            if now > deadline:
                break
            payload = snapshot_dialog_state(
                reader,
                text_read_cap=max(1, args.text_read_cap),
                dial_read_cap=max(1, args.dial_read_cap),
            )
            payload["pid"] = pid
            payload["process_name"] = args.process_name
            payload["sample_index"] = sample_index
            payload["elapsed_ms"] = int(round((args.duration_sec - (deadline - now)) * 1000.0))
            if args.label:
                payload["label"] = args.label

            fingerprint = snapshot_fingerprint(payload)
            if (not args.changes_only) or fingerprint != last_fingerprint:
                append_jsonl(out_path, payload)
                last_fingerprint = fingerprint
            sample_index += 1
            time.sleep(interval_sec)

    append_jsonl(
        out_path,
        {
            "kind": "status",
            "message": "dialog timeline capture completed",
            "pid": pid,
            "sample_count": sample_index,
        },
    )

    if launched_process is not None:
        launched_process.poll()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
