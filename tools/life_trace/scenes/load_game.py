from __future__ import annotations

import argparse
import shutil
import time
from pathlib import Path

from life_trace_shared import (
    DEFAULT_SAVE_SOURCE_ROOT,
    JsonlWriter,
    LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC,
    LOAD_GAME_MENU_SETTLE_DELAY_SEC,
    LOAD_GAME_POST_ADELINE_MENU_DELAY_SEC,
    LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC,
    PersistedStatusEvent,
)
from life_trace_windows import CaptureError, InputError, WindowCapture, WindowInput


CANONICAL_RUNTIME_SAVE_NAMES = frozenset({"current.lba"})


def default_source_save_path(filename: str) -> Path:
    return DEFAULT_SAVE_SOURCE_ROOT / filename


def runtime_save_dir(launch_path: Path) -> Path:
    return launch_path.parent / "SAVE"


def resolve_source_save(
    launch_save: str | None,
    *,
    default_source: Path,
    lane_name: str,
) -> Path:
    source_path = default_source if launch_save is None else Path(launch_save)
    if not source_path.exists():
        raise RuntimeError(
            f"{lane_name} source save is missing: {source_path}. "
            "This blocks the launch path; ask the user to generate the savegame or pass --launch-save."
        )
    return source_path


def prune_runtime_saves(
    writer: JsonlWriter,
    save_dir: Path,
    *,
    keep_names: set[str],
    reason: str,
) -> list[str]:
    save_dir.mkdir(parents=True, exist_ok=True)
    keep_lower = {name.lower() for name in keep_names}
    removed: list[str] = []

    for path in sorted(save_dir.iterdir(), key=lambda item: item.name.lower()):
        if not path.is_file() or path.suffix.lower() != ".lba":
            continue
        if path.name.lower() in keep_lower:
            continue
        path.unlink()
        removed.append(path.name)

    if removed:
        writer.write_event(
            PersistedStatusEvent(
                message=f"{reason}; removed {', '.join(removed)}",
            )
        )
    return removed


def stage_single_load_game_save(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
    *,
    lane_name: str,
    default_source: Path,
) -> tuple[Path, Path]:
    save_dir = runtime_save_dir(launch_path)
    source_path = resolve_source_save(
        args.launch_save,
        default_source=default_source,
        lane_name=lane_name,
    )
    destination_path = save_dir / source_path.name

    prune_runtime_saves(
        writer,
        save_dir,
        keep_names=set(CANONICAL_RUNTIME_SAVE_NAMES | {destination_path.name}),
        reason="restored canonical SAVE contents before staging the run fixture",
    )

    if source_path.resolve() != destination_path.resolve():
        shutil.copyfile(source_path, destination_path)

    args.staged_load_game_save_path = str(destination_path)
    writer.write_event(
        PersistedStatusEvent(
            message=f"staged {source_path.name} into SAVE as the sole Load Game slot",
        )
    )
    return source_path, destination_path


def cleanup_staged_load_game_save(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
) -> None:
    del args
    prune_runtime_saves(
        writer,
        runtime_save_dir(launch_path),
        keep_names=set(CANONICAL_RUNTIME_SAVE_NAMES),
        reason="restored canonical SAVE contents after the run",
    )


def drive_single_save_load_game_startup(
    writer: JsonlWriter,
    pid: int,
    *,
    scene_label: str,
    adeline_enter_delay_sec: float,
    startup_window_timeout_sec: float,
    post_load_settle_delay_sec: float = LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC,
    post_load_status_message: str = "waited for the sole staged save to settle before attaching fra probe",
    capture: WindowCapture | None = None,
    window_input: WindowInput | None = None,
) -> None:
    capture = WindowCapture() if capture is None else capture
    window_input = WindowInput() if window_input is None else window_input
    writer.write_event(
        PersistedStatusEvent(
            message=f"driving {scene_label} startup through Adeline and Load Game",
            pid=pid,
        )
    )

    def send_input(
        *,
        delay_sec: float,
        startup_step: str,
        status_message: str,
        action: str,
    ) -> None:
        time.sleep(delay_sec)
        try:
            window = capture.wait_for_window(pid, timeout_sec=startup_window_timeout_sec)
            if action == "enter":
                window_input.send_enter(window.hwnd)
            elif action == "down":
                window_input.send_down(window.hwnd)
            else:
                raise RuntimeError(f"unsupported startup action: {action}")
        except (CaptureError, InputError) as error:
            raise RuntimeError(
                f"{scene_label} startup automation failed during {startup_step}: {error}"
            ) from error
        writer.write_event(
            PersistedStatusEvent(
                message=status_message,
                pid=pid,
            )
        )

    send_input(
        delay_sec=adeline_enter_delay_sec,
        startup_step="Adeline splash",
        status_message="sent Enter to continue past the Adeline splash",
        action="enter",
    )
    send_input(
        delay_sec=LOAD_GAME_POST_ADELINE_MENU_DELAY_SEC,
        startup_step="main menu move to New Game",
        status_message="moved selection from Resume Game to New Game",
        action="down",
    )
    send_input(
        delay_sec=LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC,
        startup_step="main menu move to Load Game",
        status_message="moved selection from New Game to Load Game",
        action="down",
    )
    send_input(
        delay_sec=LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC,
        startup_step="Load Game entry",
        status_message="sent Enter to open Load Game",
        action="enter",
    )

    time.sleep(LOAD_GAME_MENU_SETTLE_DELAY_SEC)
    writer.write_event(
        PersistedStatusEvent(
            message="waited for the Load Game menu to settle",
            pid=pid,
        )
    )

    send_input(
        delay_sec=LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC,
        startup_step="sole staged save load",
        status_message="sent Enter to load the sole staged save",
        action="enter",
    )

    time.sleep(post_load_settle_delay_sec)
    writer.write_event(
        PersistedStatusEvent(
            message=post_load_status_message,
            pid=pid,
        )
    )
