#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
PORT_ROOT = REPO_ROOT / "port"
DEV_SHELL = REPO_ROOT / "scripts" / "dev-shell.py"
TOOL_PATH = PORT_ROOT / "zig-out" / "bin" / "lba2-tool.exe"
VIEWER_PATH = PORT_ROOT / "zig-out" / "bin" / "lba2.exe"
VIEWER_IMAGE_NAME = "lba2.exe"
SUCCESS_LAUNCH_TIMEOUT_SEC = 120.0
FAILURE_LAUNCH_TIMEOUT_SEC = 30.0
LAUNCH_POLL_INTERVAL_SEC = 0.5
POST_KILL_SETTLE_SEC = 0.25


class VerificationError(RuntimeError):
    pass


@dataclass(frozen=True)
class CommandResult:
    output: str
    exit_code: int


def print_section(label: str) -> None:
    print()
    print(f"=== {label} ===")


def read_optional_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""
    except PermissionError:
        # The child process may still be flushing or holding the file; treat that
        # as "no new text yet" for the current poll.
        return ""


def ensure(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def ensure_contains(text: str, needle: str, message: str) -> None:
    ensure(needle in text, message)


def combined_run(command: list[str], cwd: Path | None = None) -> CommandResult:
    completed = subprocess.run(
        command,
        cwd=str(cwd) if cwd is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return CommandResult(output=completed.stdout or "", exit_code=int(completed.returncode))


def run_zig_step(arguments: list[str], label: str) -> None:
    print_section(label)
    result = subprocess.run(
        [sys.executable, str(DEV_SHELL), "exec", "--cwd", str(PORT_ROOT), "--", "zig", *arguments],
        check=False,
    )
    if result.returncode != 0:
        raise VerificationError(f"zig {' '.join(arguments)} failed with exit code {result.returncode}.")


def ensure_staged_binaries() -> None:
    ensure(DEV_SHELL.exists(), f"Missing dev shell helper: {DEV_SHELL}")
    ensure(TOOL_PATH.exists(), f"Missing staged tool binary: {TOOL_PATH}")
    ensure(VIEWER_PATH.exists(), f"Missing staged viewer binary: {VIEWER_PATH}")


def list_running_image_pids(image_name: str) -> list[int]:
    result = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    )
    pids: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("INFO:"):
            continue
        row = next(csv.reader([line]))
        if len(row) < 2:
            continue
        try:
            pids.append(int(row[1]))
        except ValueError:
            continue
    return pids


def stop_stale_viewer_processes() -> None:
    pids = list_running_image_pids(VIEWER_IMAGE_NAME)
    if not pids:
        return
    print("Stopping stale lba2.exe process(es).")
    subprocess.run(
        ["taskkill", "/F", "/IM", VIEWER_IMAGE_NAME],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    time.sleep(POST_KILL_SETTLE_SEC)


def run_tool_probe(arguments: list[str], label: str) -> CommandResult:
    print_section(label)
    result = combined_run([str(TOOL_PATH), *arguments], cwd=PORT_ROOT)
    trimmed = result.output.rstrip()
    if trimmed:
        print(trimmed)
    return result


def assert_equal(label: str, actual: Any, expected: Any) -> None:
    if actual != expected:
        raise VerificationError(f"{label}: expected {expected}, got {actual}.")


def test_inspect_room_success(scene: int, background: int, expected_fragments: int, expected_grm_entry: int) -> dict[str, Any]:
    result = run_tool_probe(
        ["inspect-room", str(scene), str(background), "--json"],
        f"lba2-tool inspect-room {scene} {background} --json",
    )
    if result.exit_code != 0:
        raise VerificationError(f"inspect-room {scene}/{background} failed with exit code {result.exit_code}.")
    payload = json.loads(result.output)

    assert_equal("inspect-room command", payload["command"], "inspect-room")
    assert_equal("scene entry index", payload["scene"]["entry_index"], scene)
    assert_equal("background entry index", payload["background"]["entry_index"], background)
    assert_equal("scene kind", payload["scene"]["scene_kind"], "interior")
    assert_equal(
        f"fragment count for {scene}/{background}",
        payload["background"]["fragments"]["fragment_count"],
        expected_fragments,
    )
    assert_equal(
        f"GRM entry for {scene}/{background}",
        payload["background"]["linkage"]["grm_entry_index"],
        expected_grm_entry,
    )

    return {
        "Pair": f"{scene}/{background}",
        "Fragments": int(payload["background"]["fragments"]["fragment_count"]),
        "BrickPreviews": int(payload["background"]["bricks"]["preview_count"]),
        "GrmEntry": int(payload["background"]["linkage"]["grm_entry_index"]),
    }


def test_inspect_room_failure(
    scene: int,
    background: int,
    expected_error: str,
    expected_unsupported_opcode_name: str,
    expected_unsupported_opcode_id: int,
    expected_unsupported_offset: int,
) -> dict[str, Any]:
    result = run_tool_probe(
        ["inspect-room", str(scene), str(background), "--json"],
        f"lba2-tool inspect-room {scene} {background} --json (expected failure)",
    )
    ensure(
        result.exit_code != 0,
        f"inspect-room {scene}/{background} unexpectedly succeeded.",
    )
    ensure_contains(
        result.output,
        expected_error,
        (
            f"inspect-room {scene}/{background} failed, but did not mention {expected_error}. "
            f"Output:\n{result.output.rstrip()}"
        ),
    )
    ensure_contains(
        result.output,
        f"unsupported_life_opcode_name={expected_unsupported_opcode_name}",
        (
            f"inspect-room {scene}/{background} failed, but did not mention "
            f"unsupported_life_opcode_name={expected_unsupported_opcode_name}. Output:\n{result.output.rstrip()}"
        ),
    )
    ensure_contains(
        result.output,
        f"unsupported_life_opcode_id={expected_unsupported_opcode_id}",
        (
            f"inspect-room {scene}/{background} failed, but did not mention "
            f"unsupported_life_opcode_id={expected_unsupported_opcode_id}. Output:\n{result.output.rstrip()}"
        ),
    )
    ensure_contains(
        result.output,
        f"unsupported_life_offset={expected_unsupported_offset}",
        (
            f"inspect-room {scene}/{background} failed, but did not mention "
            f"unsupported_life_offset={expected_unsupported_offset}. Output:\n{result.output.rstrip()}"
        ),
    )

    return {
        "Pair": f"{scene}/{background}",
        "Status": "rejected",
        "Error": expected_error,
    }


def launch_viewer(scene: int, background: int) -> tuple[subprocess.Popen[Any], Path, Path]:
    stdout_fd, stdout_name = tempfile.mkstemp()
    stderr_fd, stderr_name = tempfile.mkstemp()
    os.close(stdout_fd)
    os.close(stderr_fd)
    stdout_path = Path(stdout_name)
    stderr_path = Path(stderr_name)
    stdout_handle = open(stdout_path, "wb")
    stderr_handle = open(stderr_path, "wb")
    try:
        process = subprocess.Popen(
            [str(VIEWER_PATH), "--scene-entry", str(scene), "--background-entry", str(background)],
            cwd=str(PORT_ROOT),
            stdout=stdout_handle,
            stderr=stderr_handle,
        )
    finally:
        stdout_handle.close()
        stderr_handle.close()
    return process, stdout_path, stderr_path


def cleanup_viewer_process(process: subprocess.Popen[Any] | None, stdout_path: Path, stderr_path: Path) -> None:
    stop_stale_viewer_processes()

    if process is not None and process.poll() is None:
        try:
            process.wait(timeout=15.0)
        except subprocess.TimeoutExpired:
            pass
    if process is not None and process.poll() is None:
        process.kill()
        try:
            process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            pass

    stdout_path.unlink(missing_ok=True)
    stderr_path.unlink(missing_ok=True)


def test_viewer_launch_success(
    scene: int,
    background: int,
    expected_fragments: int,
    expected_stderr_fragments: list[str],
    expected_brick_previews: int | None = None,
) -> dict[str, Any]:
    print_section(f"lba2 --scene-entry {scene} --background-entry {background}")
    stop_stale_viewer_processes()

    process: subprocess.Popen[Any] | None = None
    stdout_path = Path()
    stderr_path = Path()
    try:
        process, stdout_path, stderr_path = launch_viewer(scene, background)
        confirmed = False
        deadline = time.monotonic() + SUCCESS_LAUNCH_TIMEOUT_SEC

        while time.monotonic() < deadline:
            stderr = read_optional_text(stderr_path)
            startup_seen = "event=startup" in stderr
            room_snapshot_seen = "event=room_snapshot" in stderr
            pair_seen = f"scene_entry_index={scene} background_entry_index={background}" in stderr
            render_snapshot_seen = "render_snapshot=objects:" in stderr
            fragment_summary_seen = f"fragments={expected_fragments} " in stderr
            brick_preview_summary_seen = (
                expected_brick_previews is None
                or f"brick_previews={expected_brick_previews}" in stderr
            )
            expected_stderr_seen = all(fragment in stderr for fragment in expected_stderr_fragments)
            clean_shutdown_seen = f"status=ok event=shutdown scene_entry={scene} background_entry={background}" in stderr
            viewer_process_running = bool(list_running_image_pids(VIEWER_IMAGE_NAME))

            if (
                (viewer_process_running or clean_shutdown_seen)
                and startup_seen
                and room_snapshot_seen
                and pair_seen
                and render_snapshot_seen
                and fragment_summary_seen
                and brick_preview_summary_seen
                and expected_stderr_seen
            ):
                confirmed = True
                break

            if process.poll() is not None:
                break

            time.sleep(LAUNCH_POLL_INTERVAL_SEC)

        stderr = read_optional_text(stderr_path)
        stdout = read_optional_text(stdout_path)
        ensure(
            confirmed,
            (
                f"viewer launch {scene}/{background} did not reach confirmed startup.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )

        trimmed = stderr.rstrip()
        if trimmed:
            print(trimmed)

        return {
            "Pair": f"{scene}/{background}",
            "Startup": "confirmed",
            "Fragments": expected_fragments,
            "BrickPreviews": "n/a" if expected_brick_previews is None else expected_brick_previews,
        }
    finally:
        cleanup_viewer_process(process, stdout_path, stderr_path)


def test_viewer_launch_failure(
    scene: int,
    background: int,
    expected_error: str,
    expected_unsupported_opcode_name: str,
    expected_unsupported_opcode_id: int,
    expected_unsupported_offset: int,
) -> dict[str, Any]:
    print_section(f"lba2 --scene-entry {scene} --background-entry {background} (expected failure)")
    stop_stale_viewer_processes()

    process: subprocess.Popen[Any] | None = None
    stdout_path = Path()
    stderr_path = Path()
    try:
        process, stdout_path, stderr_path = launch_viewer(scene, background)
        try:
            process.wait(timeout=FAILURE_LAUNCH_TIMEOUT_SEC)
        except subprocess.TimeoutExpired as exc:
            raise VerificationError(
                f"viewer launch {scene}/{background} did not fail within the timeout."
            ) from exc

        stderr = read_optional_text(stderr_path)
        stdout = read_optional_text(stdout_path)

        ensure(
            process.returncode not in (None, 0),
            (
                f"viewer launch {scene}/{background} unexpectedly succeeded.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            "event=room_load_rejected",
            (
                f"viewer launch {scene}/{background} failed, but did not emit room_load_rejected.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            f"scene_entry_index={scene} background_entry_index={background}",
            (
                f"viewer launch {scene}/{background} failed, but did not echo the scene/background pair.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            expected_error,
            (
                f"viewer launch {scene}/{background} failed, but did not mention {expected_error}.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            f"unsupported_life_opcode_name={expected_unsupported_opcode_name}",
            (
                f"viewer launch {scene}/{background} failed, but did not mention "
                f"unsupported_life_opcode_name={expected_unsupported_opcode_name}.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            f"unsupported_life_opcode_id={expected_unsupported_opcode_id}",
            (
                f"viewer launch {scene}/{background} failed, but did not mention "
                f"unsupported_life_opcode_id={expected_unsupported_opcode_id}.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )
        ensure_contains(
            stderr,
            f"unsupported_life_offset={expected_unsupported_offset}",
            (
                f"viewer launch {scene}/{background} failed, but did not mention "
                f"unsupported_life_offset={expected_unsupported_offset}.\n"
                f"stderr:\n{stderr.rstrip()}\nstdout:\n{stdout.rstrip()}"
            ),
        )

        trimmed = stderr.rstrip()
        if trimmed:
            print(trimmed)

        return {
            "Pair": f"{scene}/{background}",
            "Status": "rejected",
            "Error": expected_error,
        }
    finally:
        cleanup_viewer_process(process, stdout_path, stderr_path)


def print_table(rows: list[dict[str, Any]], columns: list[str]) -> None:
    if not rows:
        return
    string_rows = [{column: str(row.get(column, "")) for column in columns} for row in rows]
    widths = {
        column: max(len(column), max(len(row[column]) for row in string_rows))
        for column in columns
    }
    print(" ".join(column.ljust(widths[column]) for column in columns))
    print(" ".join("-" * widths[column] for column in columns))
    for row in string_rows:
        print(" ".join(row[column].ljust(widths[column]) for column in columns))
    print()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Canonical Windows acceptance gate for the staged LBA2 viewer/runtime path."
    )
    parser.add_argument("--fast", action="store_true", help="Use zig build test-fast instead of zig build test.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    test_step = "test-fast" if args.fast else "test"

    run_zig_step(["build", test_step], f"zig build {test_step}")
    run_zig_step(["build", "stage-viewer"], "zig build stage-viewer")
    ensure_staged_binaries()

    inspect_success_results = [
        test_inspect_room_success(19, 19, expected_fragments=0, expected_grm_entry=151)
    ]
    inspect_failure_results = [
        test_inspect_room_failure(2, 2, "ViewerUnsupportedSceneLife", "LM_DEFAULT", 116, 170),
        test_inspect_room_failure(44, 2, "ViewerUnsupportedSceneLife", "LM_END_SWITCH", 118, 713),
        test_inspect_room_failure(11, 10, "ViewerUnsupportedSceneLife", "LM_DEFAULT", 116, 38),
    ]
    launch_results = [
        test_viewer_launch_success(
            19,
            19,
            expected_fragments=0,
            expected_stderr_fragments=[
                "event=neighbor_pattern_summary",
                "origin_cell_count=1246",
                "occupied_surface_count=4828",
                "empty_count=107",
                "out_of_bounds_count=49",
                "missing_top_surface_count=0",
                "standable_neighbor_count=4828",
                "blocked_neighbor_count=0",
                "top_y_delta_buckets=0:4828",
            ],
        )
    ]
    launch_failure_results = [
        test_viewer_launch_failure(2, 2, "ViewerUnsupportedSceneLife", "LM_DEFAULT", 116, 170),
        test_viewer_launch_failure(44, 2, "ViewerUnsupportedSceneLife", "LM_END_SWITCH", 118, 713),
        test_viewer_launch_failure(11, 10, "ViewerUnsupportedSceneLife", "LM_DEFAULT", 116, 38),
    ]

    print()
    print("Viewer verification summary")
    print_table(inspect_success_results, ["Pair", "Fragments", "BrickPreviews", "GrmEntry"])
    print_table(inspect_failure_results, ["Pair", "Status", "Error"])
    print_table(launch_results, ["Pair", "Startup", "Fragments", "BrickPreviews"])
    print_table(launch_failure_results, ["Pair", "Status", "Error"])
    print("status=ok")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerificationError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
