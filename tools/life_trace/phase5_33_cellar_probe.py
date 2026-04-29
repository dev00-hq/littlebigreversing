from __future__ import annotations

import argparse
import json
import subprocess
import time
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Iterable

from life_trace_windows import WindowCapture, WindowInput
from runtime_watch_run import (
    DEFAULT_GAME_DIR,
    ProcessMemory,
    autosave_hidden,
    capture,
    kill_processes,
    read_snapshot,
    set_hero_pose,
    stage_save,
    write_jsonl,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_EXE = DEFAULT_GAME_DIR / "LBA2.EXE"
DEFAULT_SAVE = REPO_ROOT / "work" / "saves" / "0013-weapon.LBA"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_33_cellar_zone1"

EXPECTED_SAVE = {
    "version_byte": 0xA4,
    "num_cube": 1,
    "raw_scene_entry_index": 3,
}

ZONE1 = {
    "source_scene_entry_index": 3,
    "source_background_entry_index": 3,
    "source_zone_index": 1,
    "source_zone_num": 19,
    "bounds": (3584, 3328, 8704, 4608, 4608, 9216),
    "destination_cube": 19,
    "decoded_destination": {"x": 28672, "y": 3328, "z": 28160},
    "port_destination_scene_entry_index": 21,
    "port_destination_background_entry_index": 19,
}

ACCEPTED_VERDICTS = {
    "phase5_33_zone1_new_cube_observed",
    "phase5_33_zone1_active_cube_observed",
}

ATTEMPT_DIRECT_CENTER = "direct_center"
ATTEMPT_EDGE_CROSSING = "edge_crossing"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Probe original LBA2 runtime evidence for the guarded 3/3 zone 1 "
            "cellar-source destination-cube handoff."
        )
    )
    parser.add_argument("--exe", default=str(DEFAULT_EXE))
    parser.add_argument("--launch-save", default=str(DEFAULT_SAVE))
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--startup-enter-delay-sec", type=float, default=10.0)
    parser.add_argument("--post-enter-settle-sec", type=float, default=3.0)
    parser.add_argument("--load-timeout-sec", type=float, default=20.0)
    parser.add_argument("--source-sustain-sec", type=float, default=1.0)
    parser.add_argument("--poll-sec", type=float, default=0.05)
    parser.add_argument("--duration-sec", type=float, default=3.0)
    parser.add_argument("--keep-process", action="store_true")
    parser.add_argument("--no-hide-autosave", action="store_true")
    return parser.parse_args(argv)


def read_save_header(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if len(data) < 6:
        raise ValueError(f"save file too short: {path}")
    name_end = data.find(b"\x00", 5)
    if name_end < 0:
        name_end = len(data)
    num_cube = int.from_bytes(data[1:5], "little", signed=True)
    return {
        "version_byte": data[0],
        "version_hex": f"0x{data[0]:02X}",
        "num_cube": num_cube,
        "raw_scene_entry_index": num_cube + 2,
        "save_name": data[5:name_end].decode("ascii", errors="replace"),
    }


def validate_source_save(path: Path) -> dict[str, object]:
    header = read_save_header(path)
    mismatches = {
        key: {"expected": expected, "actual": header.get(key)}
        for key, expected in EXPECTED_SAVE.items()
        if header.get(key) != expected
    }
    if mismatches:
        raise RuntimeError(f"not a guarded 3/3 source save: {json.dumps(mismatches, sort_keys=True)}")
    return header


def zone_center(zone: dict[str, object]) -> dict[str, int]:
    x0, y0, z0, x1, y1, z1 = zone["bounds"]
    return {
        "x": (int(x0) + int(x1)) // 2,
        "y": (int(y0) + int(y1)) // 2,
        "z": (int(z0) + int(z1)) // 2,
        "beta": 0,
    }


def zone_edge_start(zone: dict[str, object]) -> dict[str, int]:
    x0, y0, z0, _x1, y1, z1 = zone["bounds"]
    return {
        "x": int(x0) - 64,
        "y": (int(y0) + int(y1)) // 2,
        "z": (int(z0) + int(z1)) // 2,
        "beta": 1024,
    }


def zone_edge_path(zone: dict[str, object]) -> list[dict[str, int]]:
    start = zone_edge_start(zone)
    center = zone_center(zone)
    return [
        start,
        {**start, "x": int(zone["bounds"][0]) - 16},
        {**center, "x": int(zone["bounds"][0]) + 16, "beta": start["beta"]},
        {**center, "beta": start["beta"]},
    ]


def runtime_looks_loaded(snapshot: dict[str, object]) -> bool:
    return (
        int(snapshot.get("hero_count", 0)) > 0
        and int(snapshot.get("active_cube", -1)) == EXPECTED_SAVE["num_cube"]
        and any(int(snapshot.get(field, 0)) != 0 for field in ("hero_x", "hero_y", "hero_z"))
    )


def wait_for_loaded_snapshot(pid: int, *, timeout_sec: float, poll_sec: float) -> dict[str, object] | None:
    deadline = time.monotonic() + max(0.1, timeout_sec)
    last_snapshot: dict[str, object] | None = None
    while time.monotonic() < deadline:
        last_snapshot = read_snapshot(pid)
        if runtime_looks_loaded(last_snapshot):
            return last_snapshot
        time.sleep(max(0.01, poll_sec))
    return last_snapshot


def attempt_observations(observations: Iterable[dict[str, object]], attempt: str) -> list[dict[str, object]]:
    return [observation for observation in observations if observation.get("attempt") == attempt]


def classify_verdict(
    observations: list[dict[str, object]],
    source_clovers: int | None,
    *,
    attempt: str | None = None,
) -> tuple[str, str]:
    scoped_observations = attempt_observations(observations, attempt) if attempt is not None else observations
    for observation in observations:
        if attempt is not None and observation.get("attempt") != attempt:
            continue
        snapshot = observation["snapshot"]
        if int(snapshot.get("new_cube", -1)) == ZONE1["destination_cube"]:
            return "phase5_33_zone1_new_cube_observed", "NewCube matched decoded destination cube 19"
        if int(snapshot.get("active_cube", -1)) == ZONE1["destination_cube"]:
            return "phase5_33_zone1_active_cube_observed", "active_cube reached destination cube 19"
    if source_clovers is not None:
        for observation in scoped_observations:
            snapshot = observation["snapshot"]
            if int(snapshot.get("clovers", source_clovers)) < source_clovers:
                return "phase5_33_zone1_life_loss_detected", "clover counter decreased during source-zone probe"
    if attempt == ATTEMPT_DIRECT_CENTER:
        return "phase5_33_zone1_direct_center_no_transition", "direct center hero-object pose did not produce NewCube/active_cube destination signal"
    if attempt == ATTEMPT_EDGE_CROSSING:
        return "phase5_33_zone1_edge_crossing_no_transition", "outside-to-inside injected hero-object crossing did not produce NewCube/active_cube destination signal"
    return "phase5_33_zone1_transition_not_observed", "no NewCube/active_cube destination signal observed"


def observe_attempt(
    *,
    process_pid: int,
    jsonl_path: Path,
    attempt: str,
    poses: list[dict[str, int]],
    source_clovers: int | None,
    poll_sec: float,
    duration_sec: float,
    source_sustain_sec: float,
) -> list[dict[str, object]]:
    observations: list[dict[str, object]] = []
    with ProcessMemory(process_pid) as memory:
        for index, pose in enumerate(poses):
            set_hero_pose(memory, **pose)
            observations.append({
                "phase": "pose_written",
                "attempt": attempt,
                "pose_index": index,
                "pose": pose,
                "snapshot": read_snapshot(process_pid),
            })
            write_jsonl(jsonl_path, observations[-1])
            sustain_deadline = time.monotonic() + max(0.0, source_sustain_sec if index == len(poses) - 1 else poll_sec)
            while time.monotonic() < sustain_deadline:
                set_hero_pose(memory, **pose)
                time.sleep(max(0.01, poll_sec))

    deadline = time.monotonic() + max(0.1, duration_sec)
    while time.monotonic() < deadline:
        row = read_snapshot(process_pid)
        observations.append({"phase": "poll", "attempt": attempt, "snapshot": row})
        write_jsonl(jsonl_path, observations[-1])
        if int(row.get("new_cube", -1)) == ZONE1["destination_cube"] or int(row.get("active_cube", -1)) == ZONE1["destination_cube"]:
            break
        if source_clovers is not None and int(row.get("clovers", source_clovers)) < source_clovers:
            break
        time.sleep(max(0.01, poll_sec))
    return observations


def run_probe(args: argparse.Namespace) -> dict[str, object]:
    exe = Path(args.exe).resolve()
    launch_save = Path(args.launch_save).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "events.jsonl"
    summary_path = out_dir / "summary.json"
    for path in (jsonl_path, summary_path):
        path.unlink(missing_ok=True)

    header = validate_source_save(launch_save)
    save_arg = stage_save(exe, launch_save)
    kill_processes()

    screenshots = []
    observations: list[dict[str, object]] = []
    process = None
    autosave_state: dict[str, str | bool] = {}
    verdict = "runtime_error"
    reason = "run did not complete"
    source_clovers: int | None = None

    with autosave_hidden(exe.parent / "SAVE", enabled=not args.no_hide_autosave) as hidden:
        autosave_state = dict(hidden)
        process = subprocess.Popen([str(exe), str(save_arg)], cwd=str(exe.parent))
        write_jsonl(jsonl_path, {"phase": "launched", "pid": process.pid, "argv1": str(save_arg), "autosave": autosave_state})
        try:
            capture_tool = WindowCapture()
            input_tool = WindowInput()
            window = capture_tool.wait_for_window(process.pid, timeout_sec=30.0)
            time.sleep(max(0.0, args.startup_enter_delay_sec))
            input_tool.send_enter(window.hwnd)
            time.sleep(max(0.0, args.post_enter_settle_sec))

            loaded = wait_for_loaded_snapshot(
                process.pid,
                timeout_sec=args.load_timeout_sec,
                poll_sec=args.poll_sec,
            )
            if loaded is None or not runtime_looks_loaded(loaded):
                try:
                    screenshots.append(capture(capture_tool, process.pid, out_dir, "01_load_not_ready"))
                except Exception as error:
                    write_jsonl(jsonl_path, {"phase": "load_timeout_capture_failed", "error": str(error)})
                observations.append({"phase": "load_timeout", "snapshot": loaded})
                write_jsonl(jsonl_path, observations[-1])
                verdict = "phase5_33_zone1_load_not_ready"
                reason = (
                    "runtime never reached the expected loaded 3/3 source save before teleport; "
                    "teleporting from a menu/CD prompt would not prove gameplay behavior"
                )
                summary = {
                    "scenario": "phase5-3-3-zone1-cellar-source",
                    "verdict": verdict,
                    "reason": reason,
                    "pid": process.pid,
                    "process_returncode": process.returncode,
                    "exe": str(exe),
                    "argv1": str(save_arg),
                    "launch_save": str(launch_save),
                    "save_header": header,
                    "autosave": autosave_state,
                    "source_zone": ZONE1,
                    "source_pose": zone_center(ZONE1),
                    "screenshots": [asdict(record) for record in screenshots],
                    "observations": observations,
                    "created_at": datetime.now().isoformat(timespec="seconds"),
                }
                summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
                return summary

            screenshots.append(capture(capture_tool, process.pid, out_dir, "01_loaded"))
            observations.append({"phase": "loaded", "snapshot": loaded})
            write_jsonl(jsonl_path, observations[-1])
            source_clovers = int(loaded.get("clovers", 0))

            source_pose = zone_center(ZONE1)
            direct_observations = observe_attempt(
                process_pid=process.pid,
                jsonl_path=jsonl_path,
                attempt=ATTEMPT_DIRECT_CENTER,
                poses=[source_pose],
                source_clovers=source_clovers,
                poll_sec=args.poll_sec,
                duration_sec=args.duration_sec,
                source_sustain_sec=args.source_sustain_sec,
            )
            observations.extend(direct_observations)
            time.sleep(0.2)
            screenshots.append(capture(capture_tool, process.pid, out_dir, "02_zone1_direct_center"))
            source_snapshot = read_snapshot(process.pid)
            observations.append({"phase": "zone1_direct_center_final", "attempt": ATTEMPT_DIRECT_CENTER, "snapshot": source_snapshot})
            write_jsonl(jsonl_path, observations[-1])
            verdict, reason = classify_verdict(observations, source_clovers, attempt=ATTEMPT_DIRECT_CENTER)

            if verdict not in ACCEPTED_VERDICTS and verdict != "phase5_33_zone1_life_loss_detected":
                edge_observations = observe_attempt(
                    process_pid=process.pid,
                    jsonl_path=jsonl_path,
                    attempt=ATTEMPT_EDGE_CROSSING,
                    poses=zone_edge_path(ZONE1),
                    source_clovers=source_clovers,
                    poll_sec=args.poll_sec,
                    duration_sec=args.duration_sec,
                    source_sustain_sec=args.source_sustain_sec,
                )
                observations.extend(edge_observations)
                time.sleep(0.2)
                screenshots.append(capture(capture_tool, process.pid, out_dir, "03_zone1_edge_crossing"))
                verdict, reason = classify_verdict(observations, source_clovers, attempt=ATTEMPT_EDGE_CROSSING)

            time.sleep(0.5)
            screenshots.append(capture(capture_tool, process.pid, out_dir, "04_final"))
            final_snapshot = read_snapshot(process.pid)
            observations.append({"phase": "final", "snapshot": final_snapshot})
            write_jsonl(jsonl_path, observations[-1])
        finally:
            if process is not None and process.poll() is None and not args.keep_process:
                process.terminate()
                try:
                    process.wait(timeout=5.0)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5.0)

    summary: dict[str, object] = {
        "scenario": "phase5-3-3-zone1-cellar-source",
        "verdict": verdict,
        "reason": reason,
        "pid": None if process is None else process.pid,
        "process_returncode": None if process is None else process.returncode,
        "exe": str(exe),
        "argv1": str(save_arg),
        "launch_save": str(launch_save),
        "save_header": header,
        "autosave": autosave_state,
        "source_zone": ZONE1,
        "source_pose": zone_center(ZONE1),
        "edge_start_pose": zone_edge_start(ZONE1),
        "edge_path": zone_edge_path(ZONE1),
        "screenshots": [asdict(record) for record in screenshots],
        "observations": observations,
        "created_at": datetime.now().isoformat(timespec="seconds"),
    }
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    summary = run_probe(args)
    print(json.dumps(summary, indent=2))
    return 0 if summary["verdict"] in ACCEPTED_VERDICTS else 1


if __name__ == "__main__":
    raise SystemExit(main())
