from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace

from collision_observer import CollisionObserver
from debug_compass import (
    describe_beta,
    degrees_to_beta,
    heading_to_beta,
    shortest_beta_delta,
)
from heading_inject import HeadingInjector
from life_trace_runtime import preflight_owned_launch_processes
from life_trace_shared import JsonlWriter
from life_trace_windows import WindowCapture, WindowInput
from scenes.load_game import (
    direct_launch_argv,
    drive_direct_save_launch_startup,
    resolve_direct_launch_save,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
EXE = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "LBA2.EXE"
DEFAULT_SAVE = REPO_ROOT / "work" / "saves" / "01-house.LBA"

LOG_PATH = REPO_ROOT / "work" / "tmp_waypoint_step_probe.jsonl"
SUMMARY_PATH = REPO_ROOT / "work" / "tmp_waypoint_step_probe_summary.json"
STATUS_PATH = REPO_ROOT / "work" / "tmp_waypoint_step_probe_status.json"
PRE_SHOT_PATH = REPO_ROOT / "work" / "life_trace" / "waypoint-step-pre.png"
POST_HEADING_SHOT_PATH = REPO_ROOT / "work" / "life_trace" / "waypoint-step-post-heading.png"
POST_BURST_SHOT_PATH = REPO_ROOT / "work" / "life_trace" / "waypoint-step-post-burst.png"

VK_UP = 0x26
VK_DOWN = 0x28


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Single-step debug autopilot probe: optionally force heading, walk one burst, and classify the outcome."
    )
    parser.add_argument(
        "--launch-save",
        default=str(DEFAULT_SAVE),
        help="Save fixture to stage into SAVE before launch.",
    )
    heading = parser.add_mutually_exclusive_group(required=False)
    heading.add_argument("--beta", type=int, help="Target heading in classic beta units.")
    heading.add_argument("--degrees", type=float, help="Target heading in debug-compass degrees.")
    heading.add_argument("--heading", choices=("N", "NE", "E", "SE", "S", "SW", "W", "NW"), help="Target debug-compass heading.")
    heading.add_argument(
        "--keep-current-heading",
        action="store_true",
        help="Skip heading injection and preserve the save's natural facing.",
    )
    parser.add_argument("--burst-sec", type=float, default=0.25, help="Movement burst duration.")
    parser.add_argument("--move-key", choices=("up", "down"), default="up", help="Keyboard movement burst to send.")
    parser.add_argument("--post-load-settle-sec", type=float, default=1.5, help="Extra settle time after the staged save loads.")
    parser.add_argument("--post-input-settle-sec", type=float, default=0.08, help="Extra settle time after releasing movement.")
    parser.add_argument("--sample-interval-sec", type=float, default=0.02, help="Polling cadence while holding the movement key.")
    parser.add_argument("--startup-window-timeout-sec", type=float, default=40.0, help="Load Game startup window timeout.")
    parser.add_argument("--blocked-forward-l1-threshold", type=int, default=96, help="Planar L1 distance at or below this is blocked.")
    parser.add_argument(
        "--off-route-tolerance-beta",
        type=int,
        default=384,
        help="If motion occurs but the movement bearing differs from the requested heading by more than this, mark off_route.",
    )
    parser.add_argument("--sustain-ms", type=int, default=0, help="Optional sustained heading reapply window after injection.")
    parser.add_argument("--collision-observer-restored-streak-threshold", type=int, default=6)
    parser.add_argument("--collision-observer-same-pos-delta", type=int, default=8)
    parser.add_argument("--collision-observer-arm-after-reset-sec", type=float, default=0.12)
    parser.add_argument("--collision-observer-initial-pose-delta", type=int, default=24)
    parser.add_argument("--collision-observer-escape-planar-l1-threshold", type=int, default=96)
    parser.add_argument("--collision-observer-minimum-detection-hero-ticks", type=int, default=96)
    parser.add_argument(
        "--takeover-existing-processes",
        action="store_true",
        help="Kill existing LBA2.EXE before launch. Default is fail-fast to protect manual proof sessions.",
    )
    return parser.parse_args()


def write_status(**payload: object) -> None:
    STATUS_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def force_kill_process_tree(pid: int) -> None:
    subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True, text=True)


def append_record(handle, **payload: object) -> None:
    handle.write(json.dumps(payload) + "\n")
    handle.flush()


def resolve_target_beta(args: argparse.Namespace) -> int | None:
    if args.keep_current_heading:
        return None
    if args.beta is not None:
        return int(args.beta) % 4096
    if args.degrees is not None:
        return degrees_to_beta(args.degrees)
    if args.heading is not None:
        return heading_to_beta(args.heading)
    raise RuntimeError("one of --beta/--degrees/--heading or --keep-current-heading is required")


def planar_l1(before: dict[str, object], after: dict[str, object]) -> int:
    return abs(int(after["x"]) - int(before["x"])) + abs(int(after["z"]) - int(before["z"]))


def planar_distance(before: dict[str, object], after: dict[str, object]) -> float:
    dx = int(after["x"]) - int(before["x"])
    dz = int(after["z"]) - int(before["z"])
    return math.sqrt(dx * dx + dz * dz)


def motion_beta(before: dict[str, object], after: dict[str, object]) -> int | None:
    dx = int(after["x"]) - int(before["x"])
    dz = int(after["z"]) - int(before["z"])
    if dx == 0 and dz == 0:
        return None
    angle = math.atan2(dx, -dz)
    if angle < 0:
        angle += math.tau
    return int(round((angle / math.tau) * 4096)) % 4096


def collision_diagnostic_verdict(state: dict[str, object]) -> str:
    if bool(state.get("diagnostic_pin_detected")):
        return "persistent_collision_pin"
    if bool(state.get("pin_candidate_detected")) and bool(state.get("escape_from_initial_detected")):
        return "transient_pin_then_escape"
    return "no_restore_pin_candidate"


def classify_step(
    *,
    before_move: dict[str, object],
    after_move: dict[str, object],
    target_beta: int | None,
    blocked_forward_l1_threshold: int,
    off_route_tolerance_beta: int,
) -> dict[str, object]:
    distance_l1 = planar_l1(before_move, after_move)
    distance_planar = planar_distance(before_move, after_move)
    if distance_l1 <= blocked_forward_l1_threshold:
        return {
            "verdict": "blocked",
            "planar_l1_distance": distance_l1,
            "planar_distance": distance_planar,
            "motion_beta": None,
            "motion_beta_debug": None,
            "heading_error_beta": None,
        }

    actual_motion_beta = motion_beta(before_move, after_move)
    heading_error_beta = (
        None
        if actual_motion_beta is None or target_beta is None
        else shortest_beta_delta(target_beta, actual_motion_beta)
    )
    verdict = "moved"
    if target_beta is not None and heading_error_beta is not None and abs(heading_error_beta) > off_route_tolerance_beta:
        verdict = "off_route"

    return {
        "verdict": verdict,
        "planar_l1_distance": distance_l1,
        "planar_distance": distance_planar,
        "motion_beta": actual_motion_beta,
        "motion_beta_debug": None if actual_motion_beta is None else describe_beta(actual_motion_beta),
        "heading_error_beta": heading_error_beta,
    }


def hold_move_burst(
    *,
    reader: HeadingInjector,
    collision_observer: CollisionObserver,
    window_input: WindowInput,
    hwnd: int,
    duration_sec: float,
    sample_interval_sec: float,
    log_handle,
    t0: float,
    pid: int,
    move_key: str,
) -> tuple[list[dict[str, object]], dict[str, object]]:
    vk = VK_UP if move_key == "up" else VK_DOWN
    samples: list[dict[str, object]] = []
    detection_logged = False
    collision_observer.reset_window()
    window_input.key_down(hwnd, vk)
    try:
        deadline = time.monotonic() + duration_sec
        while time.monotonic() < deadline:
            snapshot = reader.snapshot()
            collision_state = collision_observer.state()
            append_record(
                log_handle,
                t_sec=round(time.monotonic() - t0, 3),
                phase="move_burst",
                pid=pid,
                move_key=move_key,
                snapshot=snapshot,
                collision_state=collision_state,
            )
            samples.append(snapshot)
            if collision_state["diagnostic_pin_detected"] and not detection_logged:
                append_record(
                    log_handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="diagnostic_collision_pin_detected",
                    pid=pid,
                    move_key=move_key,
                    collision_state=collision_state,
                )
                detection_logged = True
            time.sleep(sample_interval_sec)
    finally:
        window_input.key_up(vk)
    release = samples[-1] if samples else reader.snapshot()
    return samples, release


def main() -> int:
    args = parse_args()
    target_beta = resolve_target_beta(args)

    for path in (LOG_PATH, SUMMARY_PATH, STATUS_PATH, PRE_SHOT_PATH, POST_HEADING_SHOT_PATH, POST_BURST_SHOT_PATH):
        path.unlink(missing_ok=True)

    capture = WindowCapture()
    window_input = WindowInput()
    run_root = REPO_ROOT / "work" / "tmp_probe_run"
    run_id = f"waypoint-step-probe-{int(time.time() * 1000)}"
    bundle_root = run_root / run_id
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    writer = JsonlWriter(run_root, run_id=run_id)
    writer.manifest_path.unlink(missing_ok=True)
    preflight_owned_launch_processes(
        writer,
        "LBA2.EXE",
        extra_process_names=(),
        takeover_existing_processes=args.takeover_existing_processes,
    )

    proc = None
    try:
        launch_args = SimpleNamespace(launch_save=args.launch_save)
        launch_save = resolve_direct_launch_save(
            launch_args,
            writer,
            lane_name=run_id,
            default_source=Path(args.launch_save),
        )
        proc = subprocess.Popen(direct_launch_argv(EXE, launch_save), cwd=str(EXE.parent))
        write_status(
            state="launching",
            pid=proc.pid,
            launch_save=str(launch_save),
            target_beta=target_beta,
            target_beta_debug=None if target_beta is None else describe_beta(target_beta),
        )
        drive_direct_save_launch_startup(
            writer,
            proc.pid,
            scene_label=f"{run_id}:{launch_save.name}",
            adeline_enter_delay_sec=8.0,
            startup_window_timeout_sec=args.startup_window_timeout_sec,
            post_load_settle_delay_sec=args.post_load_settle_sec,
            post_load_status_message="direct-launch save loaded; running single heading+burst step",
            capture=capture,
            window_input=window_input,
        )
        window = capture.wait_for_window(proc.pid, timeout_sec=5.0)
        capture.capture(proc.pid, PRE_SHOT_PATH, timeout_sec=5.0)

        t0 = time.monotonic()
        with LOG_PATH.open("a", encoding="utf-8") as handle:
            with CollisionObserver(
                pid=proc.pid,
                restored_streak_threshold=args.collision_observer_restored_streak_threshold,
                same_pos_delta=args.collision_observer_same_pos_delta,
                arm_after_reset_sec=args.collision_observer_arm_after_reset_sec,
                initial_pose_delta=args.collision_observer_initial_pose_delta,
                escape_planar_l1_threshold=args.collision_observer_escape_planar_l1_threshold,
                minimum_detection_hero_ticks=args.collision_observer_minimum_detection_hero_ticks,
            ) as collision_observer, HeadingInjector(pid=proc.pid) as injector:
                start = injector.snapshot()
                append_record(
                    handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="start",
                    pid=proc.pid,
                    snapshot=start,
                    collision_state=collision_observer.state(),
                )

                if target_beta is None:
                    heading_result = injector.snapshot()
                    heading_result["heading_injection_skipped"] = True
                else:
                    heading_result = injector.force_heading_beta(target_beta, sustain_ms=args.sustain_ms)
                append_record(
                    handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="after_heading_inject",
                    pid=proc.pid,
                    snapshot=heading_result,
                    collision_state=collision_observer.state(),
                )
                capture.capture(proc.pid, POST_HEADING_SHOT_PATH, timeout_sec=5.0)

                before_move = injector.snapshot()
                append_record(
                    handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="before_move",
                    pid=proc.pid,
                    snapshot=before_move,
                    collision_state=collision_observer.state(),
                )

                burst_samples, release = hold_move_burst(
                    reader=injector,
                    collision_observer=collision_observer,
                    window_input=window_input,
                    hwnd=window.hwnd,
                    duration_sec=args.burst_sec,
                    sample_interval_sec=args.sample_interval_sec,
                    log_handle=handle,
                    t0=t0,
                    pid=proc.pid,
                    move_key=args.move_key,
                )
                append_record(
                    handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="release",
                    pid=proc.pid,
                    snapshot=release,
                    collision_state=collision_observer.state(),
                )
                time.sleep(args.post_input_settle_sec)
                after_move = injector.snapshot()
                collision_diagnostic = collision_observer.state()
                append_record(
                    handle,
                    t_sec=round(time.monotonic() - t0, 3),
                    phase="after_move",
                    pid=proc.pid,
                    snapshot=after_move,
                    collision_state=collision_diagnostic,
                )
                capture.capture(proc.pid, POST_BURST_SHOT_PATH, timeout_sec=5.0)

        classification = classify_step(
            before_move=before_move,
            after_move=after_move,
            target_beta=target_beta,
            blocked_forward_l1_threshold=args.blocked_forward_l1_threshold,
            off_route_tolerance_beta=args.off_route_tolerance_beta,
        )

        summary = {
            "pid": proc.pid,
            "launch_save": args.launch_save,
            "target_beta": target_beta,
            "target_beta_debug": None if target_beta is None else describe_beta(target_beta),
            "burst_sec": args.burst_sec,
            "move_key": args.move_key,
            "start": start,
            "heading_result": heading_result,
            "before_move": before_move,
            "release": release,
            "after_move": after_move,
            "classification": classification,
            "collision_diagnostic": collision_diagnostic,
            "collision_diagnostic_verdict": collision_diagnostic_verdict(collision_diagnostic),
            "collision_diagnostic_note": "diagnostic restore-pin candidate only; final live collision is revoked once the burst escapes the initial anchor threshold",
            "burst_sample_count": len(burst_samples),
            "blocked_forward_l1_threshold": args.blocked_forward_l1_threshold,
            "off_route_tolerance_beta": args.off_route_tolerance_beta,
            "collision_observer_restored_streak_threshold": args.collision_observer_restored_streak_threshold,
            "collision_observer_same_pos_delta": args.collision_observer_same_pos_delta,
            "collision_observer_arm_after_reset_sec": args.collision_observer_arm_after_reset_sec,
            "collision_observer_initial_pose_delta": args.collision_observer_initial_pose_delta,
            "collision_observer_escape_planar_l1_threshold": args.collision_observer_escape_planar_l1_threshold,
            "collision_observer_minimum_detection_hero_ticks": args.collision_observer_minimum_detection_hero_ticks,
            "pre_screenshot_path": str(PRE_SHOT_PATH),
            "post_heading_screenshot_path": str(POST_HEADING_SHOT_PATH),
            "post_burst_screenshot_path": str(POST_BURST_SHOT_PATH),
            "log_path": str(LOG_PATH),
        }
        SUMMARY_PATH.write_text(json.dumps(summary, indent=2), encoding="utf-8")
        write_status(state="completed", summary_path=str(SUMMARY_PATH), verdict=classification["verdict"])
    finally:
        writer.close()
        if proc is not None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                force_kill_process_tree(proc.pid)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
