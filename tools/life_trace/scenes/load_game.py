from __future__ import annotations

import argparse
import time
from pathlib import Path

from life_trace_shared import (
    DEFAULT_SAVE_SOURCE_ROOT,
    DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC,
    JsonlWriter,
    PersistedStatusEvent,
)
from life_trace_windows import CaptureError, InputError, WindowCapture, WindowInput


ADELINE_SPLASH_STABLE_FRAME_COUNT = 2
ADELINE_SPLASH_MIN_LIT_SAMPLES = 64
ADELINE_SPLASH_MIN_MEAN_LUMA = 8
ADELINE_SPLASH_POLL_SEC = 0.1
ADELINE_SPLASH_MIN_AGE_SEC = 1.0
ADELINE_EXIT_STABLE_FRAME_COUNT = 2


def default_source_save_path(filename: str) -> Path:
    return DEFAULT_SAVE_SOURCE_ROOT / filename


def resolve_direct_launch_save(
    args: argparse.Namespace,
    writer: JsonlWriter,
    *,
    lane_name: str,
    default_source: Path,
) -> Path:
    source_path = default_source if getattr(args, "launch_save", None) is None else Path(args.launch_save)
    if not source_path.exists():
        raise RuntimeError(
            f"{lane_name} direct launch save is missing: {source_path}. "
            "This blocks the canonical launch path; ask the user to generate the savegame or pass --launch-save."
        )
    resolved = source_path.resolve()
    args.launch_save = str(resolved)
    writer.write_event(
        PersistedStatusEvent(
            message=f"resolved direct launch save {resolved.name}",
            launch_save=str(resolved),
        )
    )
    return resolved


def direct_launch_argv(launch_path: Path, launch_save: Path) -> list[str]:
    return [str(launch_path), str(launch_save)]


def wait_for_adeline_splash(
    capture: WindowCapture,
    pid: int,
    *,
    startup_window_timeout_sec: float,
    splash_timeout_sec: float,
) -> int:
    capture.wait_for_window(pid, timeout_sec=startup_window_timeout_sec)
    splash_start = time.monotonic()
    deadline = time.monotonic() + splash_timeout_sec
    first_checksum: int | None = None
    last_checksum: int | None = None
    saw_frame_transition = False
    stable_frames = 0

    while True:
        now = time.monotonic()
        if now >= deadline:
            raise RuntimeError(
                f"Adeline splash did not reach a stable rendered frame within {splash_timeout_sec:g} seconds"
            )

        _, signature = capture.capture_frame_signature(pid, timeout_sec=startup_window_timeout_sec)
        if first_checksum is None:
            first_checksum = signature.checksum
        elif signature.checksum != first_checksum:
            saw_frame_transition = True
        splash_like = (
            signature.lit_samples >= ADELINE_SPLASH_MIN_LIT_SAMPLES
            and signature.mean_luma >= ADELINE_SPLASH_MIN_MEAN_LUMA
        )
        if splash_like and signature.checksum == last_checksum:
            stable_frames += 1
        elif splash_like:
            stable_frames = 1
            last_checksum = signature.checksum
        else:
            stable_frames = 0
            last_checksum = None

        if (
            saw_frame_transition
            and stable_frames >= ADELINE_SPLASH_STABLE_FRAME_COUNT
            and now - splash_start >= ADELINE_SPLASH_MIN_AGE_SEC
        ):
            assert last_checksum is not None
            return last_checksum

        time.sleep(ADELINE_SPLASH_POLL_SEC)


def wait_for_post_splash_transition(
    capture: WindowCapture,
    pid: int,
    *,
    startup_window_timeout_sec: float,
    splash_checksum: int,
    post_splash_timeout_sec: float,
) -> None:
    deadline = time.monotonic() + post_splash_timeout_sec
    stable_non_splash_frames = 0

    while True:
        now = time.monotonic()
        if now >= deadline:
            raise RuntimeError(
                f"direct-save launch never left the Adeline splash within {post_splash_timeout_sec:g} seconds"
            )

        _, signature = capture.capture_frame_signature(pid, timeout_sec=startup_window_timeout_sec)
        if signature.checksum != splash_checksum:
            stable_non_splash_frames += 1
        else:
            stable_non_splash_frames = 0

        if stable_non_splash_frames >= ADELINE_EXIT_STABLE_FRAME_COUNT:
            return

        time.sleep(ADELINE_SPLASH_POLL_SEC)


def drive_direct_save_launch_startup(
    writer: JsonlWriter,
    pid: int,
    *,
    scene_label: str,
    adeline_enter_delay_sec: float,
    startup_window_timeout_sec: float,
    post_load_settle_delay_sec: float = DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC,
    post_load_status_message: str = "waited for the direct-launch save to settle before attaching fra probe",
    capture: WindowCapture | None = None,
    window_input: WindowInput | None = None,
) -> None:
    capture = WindowCapture() if capture is None else capture
    window_input = WindowInput() if window_input is None else window_input
    writer.write_event(
        PersistedStatusEvent(
            message=f"driving {scene_label} startup through direct save launch",
            pid=pid,
        )
    )

    try:
        splash_checksum = wait_for_adeline_splash(
            capture,
            pid,
            startup_window_timeout_sec=startup_window_timeout_sec,
            splash_timeout_sec=adeline_enter_delay_sec,
        )
        window = capture.wait_for_window(pid, timeout_sec=startup_window_timeout_sec)
        window_input.send_enter(window.hwnd)
        wait_for_post_splash_transition(
            capture,
            pid,
            startup_window_timeout_sec=startup_window_timeout_sec,
            splash_checksum=splash_checksum,
            post_splash_timeout_sec=post_load_settle_delay_sec,
        )
    except (CaptureError, InputError) as error:
        raise RuntimeError(
            f"{scene_label} startup automation failed during Adeline splash enter: {error}"
        ) from error

    writer.write_event(
        PersistedStatusEvent(
            message="sent Enter to continue past the Adeline splash",
            pid=pid,
        )
    )

    time.sleep(post_load_settle_delay_sec)
    writer.write_event(
        PersistedStatusEvent(
            message=post_load_status_message,
            pid=pid,
        )
    )
