from __future__ import annotations

import argparse
import contextlib
import json
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterator

from heading_inject import DEFAULT_FRIDA_REPO, HeadingInjector
from life_trace_shared import JsonlWriter, PersistedStatusEvent
from life_trace_windows import WindowCapture, WindowInput
from scenes.load_game import direct_launch_argv, drive_direct_save_launch_startup, resolve_direct_launch_save
from secret_room_door_watch import ProcessReader, WatchZone, find_pid_by_name, snapshot as transition_snapshot


REPO_ROOT = Path(__file__).resolve().parents[2]
EXE = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "LBA2.EXE"
DEFAULT_OUT_DIR = REPO_ROOT / "work" / "live_proofs" / "phase5_187187_transition_probe"
DEFAULT_SAVE = REPO_ROOT / "work" / "saves" / "inside dark monk1.LBA"

TARGET_ZONE = WatchZone(
    index=1,
    kind="change_cube",
    num=185,
    name="scene187_dark_monk_statue_no_readjust_cube185",
    bounds=(1024, 0, 4096, 2048, 512, 5120),
)

RUNTIME_SOURCE_PROBE = {
    "x": 1536,
    "y": 256,
    "z": 4608,
}

EXPECTED_DESTINATION = {
    "cube": 185,
    "x": 13824,
    "y": 5120,
    "z": 14848,
}

LIVE_ZONE1_DESTINATION = {
    "cube": 185,
    "x": 28416,
    "y": 2304,
    "z": 21760,
}

HEIGHT_CLASSIFICATION = {
    "decoded_y": 5120,
    "raw_cell_surface_top_y": 2048,
    "nearest_standable_surface_top_y": 6400,
}

CLASSIC_CONTEXT_FIELDS = {
    "scene_start_x": (0x0049A0A8, 4),
    "scene_start_y": (0x0049A0AC, 4),
    "scene_start_z": (0x0049A0B0, 4),
    "start_x_cube": (0x0049A0E4, 4),
    "start_y_cube": (0x0049A0E8, 4),
    "start_z_cube": (0x0049A0EC, 4),
}

EXPECTED_SAVE_NUM_CUBE = 185
EXPECTED_SAVE_RAW_SCENE_ENTRY = 187


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare original-runtime evidence for guarded 187/187 zone 1 cube 185. "
            "The probe can direct-launch a save or attach to a running LBA2.EXE, teleport to the decoded source zone, "
            "and record transition globals plus hero coordinates before/after the runtime applies the change-cube."
        )
    )
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already running LBA2.EXE pid.")
    target.add_argument("--process-name", default=None, help="Exact process name to resolve when attaching.")
    target.add_argument("--launch-save", default=str(DEFAULT_SAVE), help="Save to pass as argv[1] to LBA2.EXE.")

    parser.add_argument("--launch-exe", default=str(EXE), help="Path to LBA2.EXE.")
    parser.add_argument("--frida-repo-root", default=str(DEFAULT_FRIDA_REPO), help="Frida repo root containing build/install-root.")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR), help="Directory for JSONL, summary, and screenshots.")
    parser.add_argument("--duration-sec", type=float, default=3.0, help="Post-teleport polling duration.")
    parser.add_argument("--poll-sec", type=float, default=0.02, help="Polling cadence.")
    parser.add_argument("--post-load-settle-sec", type=float, default=1.5)
    parser.add_argument("--startup-window-timeout-sec", type=float, default=40.0)
    parser.add_argument("--adeline-enter-delay-sec", type=float, default=10.0)
    parser.add_argument("--startup-fallback-enter-sec", type=float, default=2.0, help="If splash detection fails, wait this long, send Enter, and settle instead of aborting.")
    parser.add_argument("--no-startup-fallback", action="store_true", help="Disable the Enter-after-delay startup fallback.")
    parser.add_argument("--allow-unloaded-runtime", action="store_true", help="Continue even if the first memory snapshot looks like a menu/CD prompt instead of loaded gameplay.")
    parser.add_argument("--source-x", type=int, default=RUNTIME_SOURCE_PROBE["x"])
    parser.add_argument("--source-y", type=int, default=RUNTIME_SOURCE_PROBE["y"])
    parser.add_argument("--source-z", type=int, default=RUNTIME_SOURCE_PROBE["z"])
    parser.add_argument("--no-teleport-source", action="store_true", help="Only observe; do not write hero coordinates.")
    parser.add_argument("--no-sync-candidate-source", action="store_true", help="Do not sync candidate/scene-start globals to the teleported source probe.")
    parser.add_argument("--source-sustain-sec", type=float, default=0.0, help="Reapply the source probe pose for this many seconds before polling.")
    parser.add_argument("--keep-process", action="store_true", help="Leave a launched LBA2.EXE running after the probe.")
    parser.add_argument("--no-kill-existing", action="store_true", help="Do not kill existing LBA2.EXE before direct launch.")
    parser.add_argument("--hide-autosave", action=argparse.BooleanOptionalAction, default=True, help="Temporarily hide SAVE\\autosave.lba during direct launch so startup cannot fall back to AUTOSAVE.")
    return parser.parse_args()


def kill_lba2() -> None:
    subprocess.run(["taskkill", "/IM", "LBA2.EXE", "/F"], capture_output=True, text=True, check=False)


def write_jsonl(path: Path, payload: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, separators=(",", ":")) + "\n")


def read_save_header(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 6:
        raise ValueError(f"save file too short: {path}")
    name_end = data.find(b"\x00", 5)
    if name_end == -1:
        name_end = len(data)
    num_cube = int.from_bytes(data[1:5], byteorder="little", signed=True)
    return {
        "version_byte": data[0],
        "version_hex": f"0x{data[0]:02X}",
        "num_cube": num_cube,
        "raw_scene_entry_index": num_cube + 2,
        "save_name": data[5:name_end].decode("ascii", errors="replace"),
    }


def validate_runtime_source_save(path: Path) -> dict[str, Any]:
    header = read_save_header(path)
    if int(header["num_cube"]) != EXPECTED_SAVE_NUM_CUBE:
        raise ValueError(
            f"{path.name} is cube {header['num_cube']} / raw scene {header['raw_scene_entry_index']}; "
            f"phase5 187/187 proof requires cube {EXPECTED_SAVE_NUM_CUBE} / raw scene {EXPECTED_SAVE_RAW_SCENE_ENTRY}"
        )
    return header


def capture_screenshot(capture: WindowCapture, pid: int, path: Path) -> dict[str, Any]:
    window = capture.capture(pid, path, timeout_sec=10.0)
    return {
        "path": str(path),
        "window": {
            "hwnd": window.hwnd,
            "title": window.title,
            "left": window.left,
            "top": window.top,
            "right": window.right,
            "bottom": window.bottom,
        },
    }


def combined_snapshot(reader: ProcessReader, injector: HeadingInjector) -> dict[str, Any]:
    transition = transition_snapshot(reader.read_int, zones=(TARGET_ZONE,))
    hero = injector.snapshot()
    return {
        "transition_globals": transition,
        "classic_context": read_classic_context(reader),
        "hero_object": hero,
    }


def read_classic_context(reader: ProcessReader) -> dict[str, int]:
    return {
        name: reader.read_int(address, size)
        for name, (address, size) in CLASSIC_CONTEXT_FIELDS.items()
    }


def classic_zone_relative_destination(source_position: dict[str, int]) -> dict[str, int]:
    return {
        "cube": TARGET_ZONE.num,
        "x": EXPECTED_DESTINATION["x"] + int(source_position["x"]) - TARGET_ZONE.bounds[0],
        "y": EXPECTED_DESTINATION["y"] + int(source_position["y"]) - TARGET_ZONE.bounds[1],
        "z": EXPECTED_DESTINATION["z"] + int(source_position["z"]) - TARGET_ZONE.bounds[2],
    }


def runtime_looks_loaded(row: dict[str, Any]) -> bool:
    transition = row["transition_globals"]
    return int(transition["hero_count"]) > 0

def classify_observation(row: dict[str, Any]) -> str:
    transition = row["transition_globals"]
    hero = row["hero_object"]
    active_cube = int(transition["active_cube"])
    new_cube = int(transition["new_cube"])
    new_pos = {
        "x": int(transition["new_pos_x"]),
        "y": int(transition["new_pos_y"]),
        "z": int(transition["new_pos_z"]),
    }
    hero_pos = {
        "x": int(hero["x"]),
        "y": int(hero["y"]),
        "z": int(hero["z"]),
    }
    live_position = {k: LIVE_ZONE1_DESTINATION[k] for k in ("x", "y", "z")}
    if active_cube == LIVE_ZONE1_DESTINATION["cube"] and hero_pos == live_position:
        return "loaded_cube185_live_zone1_destination"
    if active_cube == EXPECTED_DESTINATION["cube"]:
        if hero_pos["y"] == EXPECTED_DESTINATION["y"]:
            return "loaded_cube185_kept_decoded_y"
        if hero_pos["y"] == HEIGHT_CLASSIFICATION["raw_cell_surface_top_y"]:
            return "loaded_cube185_snapped_to_raw_cell_top"
        if hero_pos["y"] == HEIGHT_CLASSIFICATION["nearest_standable_surface_top_y"]:
            return "loaded_cube185_snapped_to_nearest_standable"
        return "loaded_cube185_other_y"
    if new_cube == EXPECTED_DESTINATION["cube"] and new_pos == {k: EXPECTED_DESTINATION[k] for k in ("x", "y", "z")}:
        return "transition_globals_staged_expected_destination"
    return "no_expected_cube185_transition_observed"



@contextlib.contextmanager
def autosave_hidden(runtime_save_dir: Path, *, enabled: bool, writer: JsonlWriter) -> Iterator[None]:
    autosave_path = runtime_save_dir / "autosave.lba"
    backup_path = runtime_save_dir / f"autosave.lba.phase5-187-bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    moved = False
    if enabled and autosave_path.exists():
        if backup_path.exists():
            raise FileExistsError(f"refusing to overwrite existing autosave backup: {backup_path}")
        autosave_path.replace(backup_path)
        moved = True
        writer.write_event(PersistedStatusEvent(message=f"hid autosave during direct launch: {backup_path.name}"))
    try:
        yield
    finally:
        if moved:
            if autosave_path.exists():
                preserved_path = autosave_path.with_name(
                    f"autosave.lba.generated-during-phase5-187-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
                )
                autosave_path.replace(preserved_path)
                writer.write_event(PersistedStatusEvent(message=f"preserved generated autosave: {preserved_path.name}"))
            backup_path.replace(autosave_path)
            writer.write_event(PersistedStatusEvent(message="restored autosave after direct launch"))
def stage_runtime_save(exe: Path, source_save: Path) -> tuple[Path, Path]:
    runtime_save_dir = exe.parent / "SAVE"
    runtime_save_dir.mkdir(parents=True, exist_ok=True)
    runtime_save = runtime_save_dir / source_save.name
    if source_save.resolve() != runtime_save.resolve():
        shutil.copy2(source_save, runtime_save)
    runtime_arg = Path("SAVE") / source_save.name
    return runtime_save, runtime_arg

def launch_game(args: argparse.Namespace, out_dir: Path) -> subprocess.Popen[bytes] | None:
    if args.attach_pid is not None or args.process_name is not None:
        return None
    if not args.no_kill_existing:
        kill_lba2()
    writer = JsonlWriter(out_dir, run_id="phase5-187187-runtime-proof")
    launch_save = resolve_direct_launch_save(
        SimpleNamespace(launch_save=args.launch_save),
        writer,
        lane_name="phase5-187187-runtime-proof",
        default_source=Path(args.launch_save),
    )
    exe = Path(args.launch_exe)
    save_header = validate_runtime_source_save(launch_save)
    runtime_save, runtime_arg = stage_runtime_save(exe, launch_save)
    writer.write_event(
        PersistedStatusEvent(
            message=(
                f"staged runtime save {runtime_save.name} and will launch with {runtime_arg}; "
                f"header cube={save_header['num_cube']} raw_scene={save_header['raw_scene_entry_index']}"
            ),
            launch_save=str(runtime_save),
        )
    )
    write_jsonl(out_dir / "save-header.jsonl", {"phase": "validated_launch_save", "path": str(launch_save), "runtime_save": str(runtime_save), "runtime_arg": str(runtime_arg), "header": save_header})
    with autosave_hidden(exe.parent / "SAVE", enabled=args.hide_autosave, writer=writer):
        proc = subprocess.Popen(direct_launch_argv(exe, runtime_arg), cwd=str(exe.parent))
        try:
            drive_direct_save_launch_startup(
                writer,
                proc.pid,
                scene_label=f"phase5-187187-runtime-proof:{launch_save.name}",
                adeline_enter_delay_sec=args.adeline_enter_delay_sec,
                startup_window_timeout_sec=args.startup_window_timeout_sec,
                post_load_settle_delay_sec=args.post_load_settle_sec,
                post_load_status_message="direct-launch save loaded; preparing 187/187 runtime transition proof",
            )
        except Exception:
            if args.no_startup_fallback:
                try:
                    proc.terminate()
                    proc.wait(timeout=3)
                except Exception:
                    kill_lba2()
                raise
            writer.write_event(
                PersistedStatusEvent(
                    message=f"splash startup detection failed; using Enter-after-delay fallback after {args.startup_fallback_enter_sec:g}s",
                    pid=proc.pid,
                    phase="startup_fallback",
                )
            )
            capture = WindowCapture()
            window_input = WindowInput()
            window = capture.wait_for_window(proc.pid, timeout_sec=args.startup_window_timeout_sec)
            time.sleep(max(0.0, args.startup_fallback_enter_sec))
            window_input.send_enter(window.hwnd)
            time.sleep(max(0.0, args.post_load_settle_sec))
    return proc


def resolve_pid(args: argparse.Namespace, proc: subprocess.Popen[bytes] | None) -> int:
    if args.attach_pid is not None:
        return args.attach_pid
    if proc is not None:
        return proc.pid
    return find_pid_by_name(args.process_name or "LBA2.EXE")


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    jsonl_path = out_dir / "runtime-proof.jsonl"
    summary_path = out_dir / "summary.json"
    jsonl_path.unlink(missing_ok=True)
    summary_path.unlink(missing_ok=True)

    proc: subprocess.Popen[bytes] | None = None
    screenshots: list[dict[str, Any]] = []
    observations: list[dict[str, Any]] = []
    capture = WindowCapture()
    try:
        proc = launch_game(args, out_dir)
        pid = resolve_pid(args, proc)
        screenshots.append(capture_screenshot(capture, pid, out_dir / "00-loaded.png"))
        with HeadingInjector(pid=pid, frida_repo_root=Path(args.frida_repo_root)) as injector, ProcessReader(pid) as reader:
            initial = combined_snapshot(reader, injector)
            write_jsonl(jsonl_path, {"phase": "initial", "snapshot": initial})
            observations.append(initial)
            if not args.allow_unloaded_runtime and not runtime_looks_loaded(initial):
                summary = {
                    "schema": "phase5-187187-runtime-proof-v1",
                    "final_verdict": "runtime_not_loaded_or_cd_prompt",
                    "reason": "initial hero_count is zero; this usually means the game is still at a menu/CD prompt, so teleporting would not prove gameplay transition behavior",
                    "target_zone": {
                        "index": TARGET_ZONE.index,
                        "kind": TARGET_ZONE.kind,
                        "num": TARGET_ZONE.num,
                        "name": TARGET_ZONE.name,
                        "bounds": {
                            "x0": TARGET_ZONE.bounds[0],
                            "y0": TARGET_ZONE.bounds[1],
                            "z0": TARGET_ZONE.bounds[2],
                            "x1": TARGET_ZONE.bounds[3],
                            "y1": TARGET_ZONE.bounds[4],
                            "z1": TARGET_ZONE.bounds[5],
                        },
                    },
                    "expected_destination": EXPECTED_DESTINATION,
                    "source_relative_destination": classic_zone_relative_destination(
                        {"x": args.source_x, "y": args.source_y, "z": args.source_z}
                    ),
                    "live_zone1_destination": LIVE_ZONE1_DESTINATION,
                    "height_classification": HEIGHT_CLASSIFICATION,
                    "final_snapshot": initial,
                    "jsonl": str(jsonl_path),
                    "screenshots": screenshots,
                    "teleport_source_enabled": False,
                    "sync_candidate_source_enabled": False,
                }
                summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
                print(json.dumps(summary, indent=2))
                return 2

            teleport_result: dict[str, Any] | None = None
            if not args.no_teleport_source:
                teleport_result = injector.teleport_xyz(
                    args.source_x,
                    args.source_y,
                    args.source_z,
                    sync_candidate_position=not args.no_sync_candidate_source,
                )
                sustain_deadline = time.monotonic() + max(0.0, args.source_sustain_sec)
                while time.monotonic() < sustain_deadline:
                    teleport_result = injector.teleport_xyz(
                        args.source_x,
                        args.source_y,
                        args.source_z,
                        sync_candidate_position=not args.no_sync_candidate_source,
                    )
                    row = combined_snapshot(reader, injector)
                    verdict = classify_observation(row)
                    write_jsonl(
                        jsonl_path,
                        {
                            "phase": "source_sustain",
                            "target_source": {"x": args.source_x, "y": args.source_y, "z": args.source_z},
                            "teleport_result": teleport_result,
                            "verdict": verdict,
                            "snapshot": row,
                        },
                    )
                    observations.append(row)
                    if verdict != "no_expected_cube185_transition_observed":
                        break
                    time.sleep(0.016)
                time.sleep(0.08)
                after_teleport = combined_snapshot(reader, injector)
                write_jsonl(
                    jsonl_path,
                    {
                        "phase": "after_source_teleport",
                        "target_source": {"x": args.source_x, "y": args.source_y, "z": args.source_z},
                        "teleport_result": teleport_result,
                        "snapshot": after_teleport,
                    },
                )
                observations.append(after_teleport)
                screenshots.append(capture_screenshot(capture, pid, out_dir / "01-source-zone.png"))

            deadline = time.monotonic() + args.duration_sec
            while time.monotonic() < deadline:
                row = combined_snapshot(reader, injector)
                verdict = classify_observation(row)
                payload = {
                    "phase": "poll",
                    "t_monotonic": round(time.monotonic(), 6),
                    "verdict": verdict,
                    "snapshot": row,
                }
                write_jsonl(jsonl_path, payload)
                observations.append(row)
                if verdict != "no_expected_cube185_transition_observed":
                    break
                time.sleep(args.poll_sec)

            screenshots.append(capture_screenshot(capture, pid, out_dir / "02-final.png"))
            final = observations[-1]
            summary = {
                "schema": "phase5-187187-runtime-proof-v1",
                "target_zone": {
                    "index": TARGET_ZONE.index,
                    "kind": TARGET_ZONE.kind,
                    "num": TARGET_ZONE.num,
                    "name": TARGET_ZONE.name,
                    "bounds": {
                        "x0": TARGET_ZONE.bounds[0],
                        "y0": TARGET_ZONE.bounds[1],
                        "z0": TARGET_ZONE.bounds[2],
                        "x1": TARGET_ZONE.bounds[3],
                        "y1": TARGET_ZONE.bounds[4],
                        "z1": TARGET_ZONE.bounds[5],
                    },
                },
                "source_probe_position": {"x": args.source_x, "y": args.source_y, "z": args.source_z},
                "expected_destination": EXPECTED_DESTINATION,
                "source_relative_destination": classic_zone_relative_destination(
                    {"x": args.source_x, "y": args.source_y, "z": args.source_z}
                ),
                "live_zone1_destination": LIVE_ZONE1_DESTINATION,
                "height_classification": HEIGHT_CLASSIFICATION,
                "final_verdict": classify_observation(final),
                "final_snapshot": final,
                "jsonl": str(jsonl_path),
                "screenshots": screenshots,
                "teleport_source_enabled": not args.no_teleport_source,
                "sync_candidate_source_enabled": not args.no_sync_candidate_source,
            }
            summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
            print(json.dumps(summary, indent=2))
    finally:
        if proc is not None and not args.keep_process:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                kill_lba2()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())



















