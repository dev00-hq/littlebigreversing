from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import shutil
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator

from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
LIFE_TRACE_DIR = REPO_ROOT / "tools" / "life_trace"
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(LIFE_TRACE_DIR))

from tools.game_drive_checkpoint import (  # noqa: E402
    VISUAL_RESULT_SCHEMA_PATH,
    validate_checkpoint,
    validate_visual_result,
)
from heading_inject import HeadingInjector  # noqa: E402
from life_trace_shared import DEFAULT_GAME_EXE  # noqa: E402
from life_trace_windows import WindowCapture, WindowInput  # noqa: E402
from phase5_magic_ball_switch_probe import stage_save  # noqa: E402
from phase5_magic_ball_throw_probe import active_extras, read_sized, snapshot_globals  # noqa: E402
from phase5_magic_ball_tralu_sequence import kill_existing_lba2  # noqa: E402
from scenes.load_game import direct_launch_argv  # noqa: E402
from secret_room_door_watch import ProcessReader  # noqa: E402


DEFAULT_OUT_ROOT = REPO_ROOT / "work" / "game_drive_runs"
DEFAULT_ARCHIVE_ROOT = REPO_ROOT / "docs" / "evidence_archive" / "game_drive"
DEFAULT_SAVE_DIR = DEFAULT_GAME_EXE.parent / "SAVE"
RUNNER_SUCCESS_VERDICTS = {"passed", "checkpoint_passed_actions_recorded"}
PT_TEXT_GLOBAL = 0x004CC498
PT_DIAL_GLOBAL = 0x004CCDF0
CURRENT_DIAL_GLOBAL = 0x004CCF10
COMPORTEMENT_GLOBAL = 0x0049A098
HERO_OBJECT_BASE_CANDIDATE = 0x0049A198
HERO_OBJECT_ANIMATION_FIELDS = {
    "hero_obj_gen_body": (0x00, 1),
    "hero_obj_gen_anim": (0x02, 2),
    "hero_obj_next_gen_anim": (0x04, 2),
    "hero_obj_sprite_candidate": (0x36, 2),
    "hero_obj_flag_anim_candidate": (0x81, 1),
    "hero_obj_x_candidate": (0x42, 4),
    "hero_obj_y_candidate": (0x46, 4),
    "hero_obj_z_candidate": (0x4A, 4),
    "hero_obj_beta_candidate": (0x52, 4),
}
KEYS = {
    "period": 0xBE,
    "numpad_decimal": 0x6E,
    "w": 0x57,
    "enter": 0x0D,
    "space": 0x20,
    "ctrl": 0x11,
    "left": 0x25,
    "up": 0x26,
    "right": 0x27,
    "down": 0x28,
    "f5": 0x74,
    "f6": 0x75,
    "f7": 0x76,
    "f8": 0x77,
    "1": 0x31,
}


class GameDriveRunnerError(Exception):
    pass


def repo_relative(path: Path) -> str:
    return path.resolve().relative_to(REPO_ROOT).as_posix()


def utc_stamp() -> str:
    return datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_event_id(value: str) -> str:
    cleaned = "".join(char if char.isalnum() or char in {"-", "_", "."} else "_" for char in value)
    return cleaned.strip("._") or "game-drive-run"


def resolve_repo_path(value: str | None) -> Path | None:
    if not value:
        return None
    path = Path(value)
    if not path.is_absolute():
        path = REPO_ROOT / path
    return path


def archive_image(source: Path, destination: Path) -> dict[str, Any]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGB")
        image.thumbnail((640, 480), Image.Resampling.LANCZOS)
        image.save(destination, "WEBP", quality=35, method=6)
    return {
        "source": repo_relative(source),
        "archive": repo_relative(destination),
        "source_sha256": sha256_file(source),
        "archive_sha256": sha256_file(destination),
        "source_bytes": source.stat().st_size,
        "archive_bytes": destination.stat().st_size,
        "compression": {
            "format": "webp",
            "quality": 35,
            "method": 6,
            "max_size": [640, 480],
        },
    }


def archive_game_drive_run(
    summary: dict[str, Any],
    run_dir: Path,
    archive_root: Path,
    *,
    event_id: str | None = None,
    reason: str,
) -> dict[str, Any]:
    run_name = run_dir.name
    archive_id = safe_event_id(event_id or run_name)
    archive_dir = archive_root / archive_id
    archive_dir.mkdir(parents=True, exist_ok=False)
    summary_path = run_dir / "summary.json"
    manifest: dict[str, Any] = {
        "schema": "game-drive-evidence-archive-v1",
        "archive_id": archive_id,
        "reason": reason,
        "checkpoint_id": summary.get("checkpoint_id"),
        "verdict": summary.get("verdict"),
        "run_dir": repo_relative(run_dir),
        "created_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "source_summary": repo_relative(summary_path),
        "images": [],
        "json": [],
    }
    for name in ("visual_result.json", "codex_exec.json"):
        source = run_dir / name
        if source.is_file():
            destination = archive_dir / name
            shutil.copy2(source, destination)
            manifest["json"].append(
                {
                    "source": repo_relative(source),
                    "archive": repo_relative(destination),
                    "source_sha256": sha256_file(source),
                    "archive_sha256": sha256_file(destination),
                }
            )
    for key in ("checkpoint_screenshot", "after_actions_screenshot"):
        source = resolve_repo_path(summary.get(key) if isinstance(summary.get(key), str) else None)
        if source is not None and source.is_file():
            destination = archive_dir / f"{key}.webp"
            image_record = archive_image(source, destination)
            image_record["summary_field"] = key
            manifest["images"].append(image_record)
    write_json(summary_path, summary)
    shutil.copy2(summary_path, archive_dir / "summary.json")
    manifest["source_summary_sha256"] = sha256_file(summary_path)
    manifest["json"].insert(
        0,
        {
            "source": repo_relative(summary_path),
            "archive": repo_relative(archive_dir / "summary.json"),
            "source_sha256": sha256_file(summary_path),
            "archive_sha256": sha256_file(archive_dir / "summary.json"),
        },
    )
    write_json(archive_dir / "manifest.json", manifest)
    manifest["manifest"] = repo_relative(archive_dir / "manifest.json")
    return manifest


@contextlib.contextmanager
def hidden_autosave(save_dir: Path) -> Iterator[dict[str, Any]]:
    autosave_path = save_dir / "autosave.lba"
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    state: dict[str, Any] = {"hidden": False}
    if autosave_path.exists():
        hidden_path = save_dir / f"autosave.lba.game-drive-hidden-{stamp}"
        autosave_path.replace(hidden_path)
        state = {"hidden": True, "hidden_path": str(hidden_path)}
    try:
        yield state
    finally:
        if autosave_path.exists():
            preserved = save_dir / f"autosave.lba.generated-game-drive-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
            autosave_path.replace(preserved)
            state["preserved_generated"] = str(preserved)
        hidden_path_value = state.get("hidden_path")
        if isinstance(hidden_path_value, str):
            Path(hidden_path_value).replace(autosave_path)


def resolve_save(save_name: str, save_root: Path) -> Path:
    path = save_root / save_name
    if not path.is_file():
        raise GameDriveRunnerError(f"save does not exist: {path}")
    return path


def action_to_key_hold(action: str) -> tuple[int, float]:
    action_specs = {
        "hold_period_0_75_sec_release": ("period", 0.75),
        "hold_numpad_decimal_0_75_sec_release": ("numpad_decimal", 0.75),
        "press_w_0_18_sec": ("w", 0.18),
        "press_enter_0_08_sec": ("enter", 0.08),
        "press_space_0_08_sec": ("space", 0.08),
        "hold_left_0_50_sec_release": ("left", 0.50),
        "hold_right_0_50_sec_release": ("right", 0.50),
        "hold_up_0_50_sec_release": ("up", 0.50),
        "hold_up_1_00_sec_release": ("up", 1.00),
        "hold_up_2_00_sec_release": ("up", 2.00),
        "hold_down_0_50_sec_release": ("down", 0.50),
        "press_f5_0_08_sec": ("f5", 0.08),
        "press_f6_0_08_sec": ("f6", 0.08),
        "press_f7_0_08_sec": ("f7", 0.08),
        "press_f8_0_08_sec": ("f8", 0.08),
        "hold_f6_0_50_sec_release": ("f6", 0.50),
        "press_1_0_08_sec": ("1", 0.08),
    }
    spec = action_specs.get(action)
    if spec is not None:
        key_name, hold_sec = spec
        return KEYS[key_name], hold_sec
    raise GameDriveRunnerError(f"unsupported action: {action}")


def hold_key(input_tool: WindowInput, hwnd: int, virtual_key: int, hold_sec: float) -> None:
    input_tool.key_down(hwnd, virtual_key)
    time.sleep(max(0.01, hold_sec))
    input_tool.key_up(virtual_key)
    time.sleep(0.18)


def changed_fields(samples: list[dict[str, Any]]) -> dict[str, list[Any]]:
    if not samples:
        return {}
    names = sorted({name for sample in samples for name in sample if name != "error"})
    changes: dict[str, list[Any]] = {}
    for name in names:
        values = []
        for sample in samples:
            value = sample.get(name)
            if value not in values:
                values.append(value)
        if len(values) > 1:
            changes[name] = values[:8]
    return changes


def hold_key_with_runtime_poll(
    input_tool: WindowInput,
    hwnd: int,
    virtual_key: int,
    hold_sec: float,
    reader: ProcessReader,
    *,
    post_release_sec: float = 1.2,
    poll_sec: float = 0.05,
) -> dict[str, Any]:
    samples: list[dict[str, Any]] = []
    started = time.monotonic()
    release_at = started + max(0.01, hold_sec)
    end_at = release_at + max(0.0, post_release_sec)
    input_tool.key_down(hwnd, virtual_key)
    released = False
    try:
        while time.monotonic() < end_at:
            now = time.monotonic()
            if not released and now >= release_at:
                input_tool.key_up(virtual_key)
                released = True
            sample = safe_snapshot(reader)
            sample["extras"] = extras_summary(reader)
            sample["dialog"] = dialog_summary(reader)
            sample["_t_ms"] = int((now - started) * 1000)
            samples.append(sample)
            time.sleep(poll_sec)
    finally:
        if not released:
            input_tool.key_up(virtual_key)
    time.sleep(0.18)
    comparable_samples = [{key: value for key, value in sample.items() if key != "_t_ms"} for sample in samples]
    return {
        "sample_count": len(samples),
        "duration_ms": int((time.monotonic() - started) * 1000),
        "changed_fields": changed_fields(comparable_samples),
        "samples": samples[:60],
    }


def ctrl_tap_with_runtime_poll(
    input_tool: WindowInput,
    hwnd: int,
    tap_virtual_key: int,
    reader: ProcessReader,
    *,
    pre_tap_sec: float = 0.35,
    tap_hold_sec: float = 0.12,
    post_tap_ctrl_hold_sec: float = 0.35,
    post_release_sec: float = 1.2,
    poll_sec: float = 0.05,
) -> dict[str, Any]:
    samples: list[dict[str, Any]] = []
    started = time.monotonic()
    tap_down_at = started + max(0.0, pre_tap_sec)
    tap_up_at = tap_down_at + max(0.01, tap_hold_sec)
    ctrl_up_at = tap_up_at + max(0.0, post_tap_ctrl_hold_sec)
    end_at = ctrl_up_at + max(0.0, post_release_sec)
    input_tool.key_down(hwnd, KEYS["ctrl"])
    pressed_tap = False
    released_tap = False
    released_ctrl = False
    try:
        while time.monotonic() < end_at:
            now = time.monotonic()
            if not pressed_tap and now >= tap_down_at:
                input_tool.key_down(hwnd, tap_virtual_key)
                pressed_tap = True
            if pressed_tap and not released_tap and now >= tap_up_at:
                input_tool.key_up(tap_virtual_key)
                released_tap = True
            if not released_ctrl and now >= ctrl_up_at:
                input_tool.key_up(KEYS["ctrl"])
                released_ctrl = True
            sample = safe_snapshot(reader)
            sample["extras"] = extras_summary(reader)
            sample["dialog"] = dialog_summary(reader)
            sample["_t_ms"] = int((now - started) * 1000)
            samples.append(sample)
            time.sleep(poll_sec)
    finally:
        if not released_tap:
            input_tool.key_up(tap_virtual_key)
        if not released_ctrl:
            input_tool.key_up(KEYS["ctrl"])
    time.sleep(0.18)
    comparable_samples = [{key: value for key, value in sample.items() if key != "_t_ms"} for sample in samples]
    return {
        "sample_count": len(samples),
        "duration_ms": int((time.monotonic() - started) * 1000),
        "changed_fields": changed_fields(comparable_samples),
        "samples": samples[:60],
    }


def run_action_with_runtime_poll(
    action: str,
    input_tool: WindowInput,
    hwnd: int,
    reader: ProcessReader,
) -> dict[str, Any]:
    if action == "ctrl_right_behavior_cycle":
        return ctrl_tap_with_runtime_poll(input_tool, hwnd, KEYS["right"], reader)
    key, hold_sec = action_to_key_hold(action)
    return hold_key_with_runtime_poll(input_tool, hwnd, key, hold_sec, reader)


def safe_snapshot(reader: ProcessReader) -> dict[str, Any]:
    try:
        snapshot = snapshot_globals(reader)
        snapshot["comportement"] = reader.read_int(COMPORTEMENT_GLOBAL, 1)
        snapshot["hero_animation_candidate"] = hero_animation_candidate_summary(reader)
        return snapshot
    except Exception as error:
        return {"error": str(error)}


def hero_animation_candidate_summary(reader: ProcessReader) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for name, (offset, size) in HERO_OBJECT_ANIMATION_FIELDS.items():
        summary[name] = read_sized(reader, HERO_OBJECT_BASE_CANDIDATE + offset, size)
    return summary


def dialog_summary(reader: ProcessReader) -> dict[str, Any]:
    try:
        pt_text = reader.read_int(PT_TEXT_GLOBAL, 4)
        pt_dial = reader.read_int(PT_DIAL_GLOBAL, 4)
        current_dial = reader.read_int(CURRENT_DIAL_GLOBAL, 2)
    except Exception as error:
        return {"error": str(error)}
    cursor_offset = pt_dial - pt_text if pt_text and pt_dial and pt_dial >= pt_text else None
    return {
        "current_dial": current_dial,
        "pt_text": f"0x{pt_text & 0xFFFFFFFF:08X}",
        "pt_dial": f"0x{pt_dial & 0xFFFFFFFF:08X}",
        "cursor_offset": cursor_offset,
    }


def extras_summary(reader: ProcessReader) -> dict[str, Any]:
    try:
        rows = active_extras(reader)
    except Exception as error:
        return {"error": str(error)}
    sprite_counts: dict[str, int] = {}
    compact_rows = []
    for row in rows:
        sprite_key = str(row["sprite"])
        sprite_counts[sprite_key] = sprite_counts.get(sprite_key, 0) + 1
        compact_rows.append(
            {
                "index": row["index"],
                "sprite": row["sprite"],
                "body": row["body"],
                "pos_x": row["pos_x"],
                "pos_y": row["pos_y"],
                "pos_z": row["pos_z"],
                "owner": row["owner"],
                "hit_force": row["hit_force"],
            }
        )
    return {
        "active_extra_count": len(rows),
        "sprite_counts": sprite_counts,
        "active_extras": compact_rows[:20],
    }


def known_runtime_expectations_match(snapshot: dict[str, Any], runtime_expect: dict[str, Any]) -> bool:
    for key, expected in runtime_expect.items():
        if key in {"life_not_lost", "scene", "background"}:
            continue
        if key in snapshot and snapshot[key] != expected:
            return False
    return True


def wait_for_loaded_runtime(
    reader: ProcessReader,
    window: Any,
    input_tool: WindowInput,
    runtime_expect: dict[str, Any],
    *,
    timeout_sec: float = 25.0,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_sec
    last_snapshot: dict[str, Any] = {}
    enter_count = 0
    while time.monotonic() < deadline:
        snapshot = safe_snapshot(reader)
        last_snapshot = snapshot
        if (
            "error" not in snapshot
            and snapshot.get("hero_count", 0) > 0
            and known_runtime_expectations_match(snapshot, runtime_expect)
        ):
            return {"snapshot": snapshot, "enter_count": enter_count}
        input_tool.send_enter(window.hwnd)
        enter_count += 1
        time.sleep(1.0)
    raise GameDriveRunnerError(
        "direct-save launch did not reach expected runtime state; "
        f"last_snapshot={json.dumps(last_snapshot, sort_keys=True)}"
    )


def startup_direct_save(process: subprocess.Popen[bytes], capture: WindowCapture, input_tool: WindowInput) -> Any:
    window = capture.wait_for_window(process.pid, timeout_sec=25.0)
    time.sleep(1.0)
    return capture.wait_for_window(process.pid, timeout_sec=10.0)


def apply_pose_if_needed(checkpoint: dict[str, Any], pid: int) -> dict[str, Any] | None:
    pose = checkpoint["pose"]
    method = pose["method"]
    if method == "existing_pose":
        return None
    coordinates = pose["coordinates"]
    with HeadingInjector(pid=pid) as injector:
        before = injector.snapshot()
        teleport = None
        if method in {"direct_pose", "teleport"}:
            teleport = injector.teleport_xyz(
                coordinates["x"],
                coordinates["y"],
                coordinates["z"],
                sync_old_position=True,
                sync_candidate_position=True,
            )
        heading = injector.force_heading_beta(
            coordinates["beta"],
            sustain_ms=200,
            verify_tolerance_beta=pose["tolerance"]["beta"],
        )
        after = injector.snapshot()
    return {
        "method": method,
        "before": before,
        "teleport": teleport,
        "heading": heading,
        "after": after,
    }


def build_visual_prompt(checkpoint: dict[str, Any]) -> str:
    visual = checkpoint["visual_expect"]
    return (
        "Classify this LBA2 game screenshot against the expected checkpoint. "
        "Return strict JSON only. The checkpoint_id field must exactly equal the supplied checkpoint_id. "
        "Include a non-empty summary that justifies every boolean field.\n\n"
        + json.dumps(
            {
                "checkpoint_id": checkpoint["id"],
                "save": checkpoint["save"],
                "visual_source": visual["source"],
                "scene_description": visual.get("scene_description"),
                "target_description": visual.get("target_description"),
                "expected": visual["expected"],
                "summary_must_mention": visual["summary_must_mention"],
                "negative_controls": visual["negative_controls"],
                "response_schema": "game-drive-visual-classification-v1",
            },
            indent=2,
        )
    )


def classify_screenshot(checkpoint_path: Path, checkpoint: dict[str, Any], screenshot: Path, out_dir: Path) -> dict[str, Any]:
    result_path = out_dir / "visual_result.json"
    prompt = build_visual_prompt(checkpoint)
    codex_executable = "codex.cmd" if sys.platform == "win32" else "codex"
    command = [
        codex_executable,
        "exec",
        "--image",
        str(screenshot),
        "--output-schema",
        str(VISUAL_RESULT_SCHEMA_PATH),
        "-o",
        str(result_path),
        "-",
    ]
    completed = subprocess.run(
        command,
        cwd=str(REPO_ROOT),
        input=prompt,
        capture_output=True,
        text=True,
        check=False,
        timeout=180,
    )
    write_json(
        out_dir / "codex_exec.json",
        {
            "command": command,
            "stdin": prompt,
            "exit_code": completed.returncode,
            "stdout_tail": completed.stdout[-4000:],
            "stderr_tail": completed.stderr[-4000:],
            "result_path": repo_relative(result_path) if result_path.exists() else None,
        },
    )
    if completed.returncode != 0:
        raise GameDriveRunnerError(f"codex exec failed with exit code {completed.returncode}")
    if not result_path.is_file():
        raise GameDriveRunnerError("codex exec did not write visual result")
    return validate_visual_result(checkpoint_path, result_path)


def capture_visual_checkpoint(
    checkpoint: dict[str, Any],
    capture: WindowCapture,
    pid: int,
    output_path: Path,
) -> str:
    source = checkpoint["visual_expect"]["source"]
    if source == "live_window_capture":
        capture.capture(pid, output_path, timeout_sec=10.0)
        return source
    raise GameDriveRunnerError(f"unsupported visual source: {source}")


def run_checkpoint(
    checkpoint_path: Path,
    *,
    out_root: Path,
    save_root: Path,
    exe: Path,
    archive: bool = False,
    archive_on_failure: bool = False,
    archive_root: Path = DEFAULT_ARCHIVE_ROOT,
    archive_event_id: str | None = None,
) -> dict[str, Any]:
    checkpoint = validate_checkpoint(checkpoint_path)
    run_dir = out_root / f"{checkpoint['id']}_{utc_stamp()}"
    run_dir.mkdir(parents=True, exist_ok=False)
    summary_path = run_dir / "summary.json"
    process: subprocess.Popen[bytes] | None = None
    capture = WindowCapture()
    input_tool = WindowInput()
    reader: ProcessReader | None = None
    summary: dict[str, Any] = {
        "schema": "game-drive-run-summary-v1",
        "checkpoint_id": checkpoint["id"],
        "checkpoint": repo_relative(checkpoint_path),
        "save": checkpoint["save"],
        "run_dir": repo_relative(run_dir),
        "verdict": "started",
    }
    write_json(summary_path, summary)

    kill_existing_lba2()
    with hidden_autosave(exe.parent / "SAVE") as autosave_state:
        try:
            save = resolve_save(checkpoint["save"], save_root)
            runtime_save_arg = stage_save(save, exe.parent / "SAVE")
            process = subprocess.Popen(direct_launch_argv(exe, runtime_save_arg), cwd=str(exe.parent))
            summary["pid"] = process.pid
            summary["autosave"] = autosave_state
            window = startup_direct_save(process, capture, input_tool)
            reader = ProcessReader(process.pid)
            loaded_runtime = wait_for_loaded_runtime(reader, window, input_tool, checkpoint["runtime_expect"])
            summary["runtime_before_pose"] = loaded_runtime["snapshot"]
            summary["startup"] = {"enter_count": loaded_runtime["enter_count"]}
            pose_result = apply_pose_if_needed(checkpoint, process.pid)
            if pose_result is not None:
                summary["pose_result"] = pose_result
                time.sleep(0.5)
            summary["runtime_before_visual"] = safe_snapshot(reader)

            screenshot = run_dir / f"{checkpoint['visual_expect']['checkpoint']}.png"
            input_tool._activate_window(window.hwnd)
            visual_source = capture_visual_checkpoint(checkpoint, capture, process.pid, screenshot)
            summary["checkpoint_screenshot"] = repo_relative(screenshot)
            summary["visual_source"] = visual_source
            visual_result = classify_screenshot(checkpoint_path, checkpoint, screenshot, run_dir)
            summary["visual_result"] = visual_result
            if not visual_result["matches"]:
                summary["verdict"] = "blocked_visual_checkpoint_mismatch"
                return summary

            action_records = []
            for action in checkpoint["actions_after_checkpoint"]:
                before = safe_snapshot(reader)
                poll = run_action_with_runtime_poll(action, input_tool, window.hwnd, reader)
                after = safe_snapshot(reader)
                action_records.append({"action": action, "before": before, "poll": poll, "after": after})
            summary["actions"] = action_records
            if action_records:
                after_action = run_dir / "after_actions.png"
                capture.capture(process.pid, after_action, timeout_sec=10.0)
                summary["after_actions_screenshot"] = repo_relative(after_action)
            summary["runtime_final"] = safe_snapshot(reader)
            summary["verdict"] = "checkpoint_passed_actions_recorded" if action_records else "passed"
            return summary
        except Exception as error:
            summary["verdict"] = "error"
            summary["error"] = str(error)
            raise
        finally:
            if reader is not None:
                reader.close()
            if process is not None and process.poll() is None:
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True, text=True, check=False)
            write_json(summary_path, summary)
            should_archive = archive or (archive_on_failure and summary.get("verdict") not in RUNNER_SUCCESS_VERDICTS)
            if should_archive:
                archive_reason = "explicit" if archive else f"failure:{summary.get('verdict')}"
                archive_id = safe_event_id(archive_event_id or run_dir.name)
                summary["evidence_archive"] = {
                    "archive_id": archive_id,
                    "manifest": repo_relative(archive_root / archive_id / "manifest.json"),
                    "reason": archive_reason,
                }
                archive_game_drive_run(
                    summary,
                    run_dir,
                    archive_root,
                    event_id=archive_id,
                    reason=archive_reason,
                )
                write_json(summary_path, summary)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run declared game-drive checkpoints against the original LBA2 runtime.")
    parser.add_argument("checkpoints", nargs="+", type=Path)
    parser.add_argument("--out-root", type=Path, default=DEFAULT_OUT_ROOT)
    parser.add_argument("--save-root", type=Path, default=DEFAULT_SAVE_DIR)
    parser.add_argument("--exe", type=Path, default=DEFAULT_GAME_EXE)
    parser.add_argument("--archive", action="store_true", help="archive compressed evidence for this run")
    parser.add_argument("--archive-on-failure", action="store_true", help="archive compressed evidence only when a run fails")
    parser.add_argument("--archive-root", type=Path, default=DEFAULT_ARCHIVE_ROOT)
    parser.add_argument("--archive-event-id", help="stable event/task/promotion id for the evidence archive")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    results = []
    exit_code = 0
    for checkpoint_path in args.checkpoints:
        try:
            result = run_checkpoint(
                checkpoint_path,
                out_root=args.out_root,
                save_root=args.save_root,
                exe=args.exe,
                archive=args.archive,
                archive_on_failure=args.archive_on_failure,
                archive_root=args.archive_root,
                archive_event_id=args.archive_event_id,
            )
        except Exception as error:
            result = {
                "schema": "game-drive-run-summary-v1",
                "checkpoint": str(checkpoint_path),
                "verdict": "error",
                "error": str(error),
            }
            exit_code = 1
        results.append(result)
    payload = {"schema": "game-drive-run-batch-v1", "results": results}
    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        for result in results:
            print(f"{result.get('checkpoint_id', result.get('checkpoint'))}: {result['verdict']}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
