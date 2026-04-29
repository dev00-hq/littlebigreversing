from __future__ import annotations

import argparse
import ctypes
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

from life_trace_shared import (
    AgentBranchTraceEvent,
    AgentDoLifeReturnEvent,
    AgentErrorEvent,
    AgentHelperCallsiteEvent,
    AgentStatusEvent,
    AgentTargetValidationEvent,
    AgentTraceEvent,
    AgentWindowTraceEvent,
    AgentWireEventType,
    DEFAULT_CALLSITES_JSONL,
    DEFAULT_FRA_REPO_ROOT,
    DEFAULT_FRIDA_REPO_ROOT,
    DEFAULT_GAME_EXE,
    DEFAULT_RUN_ROOT,
    DEFAULT_SAVE_SOURCE_ROOT,
    DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC,
    ExeSwitchState,
    FraProbeRuntime,
    JsonlWriter,
    PersistedBranchTraceEvent,
    PersistedDoLifeReturnEvent,
    PersistedErrorEvent,
    PersistedHelperCallsiteEvent,
    PersistedMemorySnapshotEvent,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PersistedTargetValidationEvent,
    PersistedTraceEvent,
    PersistedVerdictEvent,
    PersistedWindowTraceEvent,
    PointerWindow,
    REPO_ROOT,
    SCENE11_ADELINE_ENTER_DELAY_SEC,
    SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
    SPAWNED_PROCESS_TERMINATE_GRACE_SEC,
    TAVERN_ADELINE_ENTER_DELAY_SEC,
    TAVERN_STARTUP_WINDOW_TIMEOUT_SEC,
    TRACE_COMPLETE_STATUS_MESSAGE,
    TraceConfig,
    build_trace_config,
    convert_agent_event,
    convert_persisted_event,
    parse_hex_bytes,
    parse_int,
    parse_persisted_event_line,
    serialize_persisted_event,
    load_callsite_index,
)
from life_trace_windows import WindowFrameSignature, WindowInfo
import life_trace_runtime as runtime
import scenes.tavern as tavern_scene
from scenes.registry import (
    fra_structured_scene_modes,
    get_structured_scene_spec,
    structured_scene_modes,
)
from scenes.scene11 import (
    COMPARISON_SNAPSHOT,
    PRIMARY_SNAPSHOT,
    SCENE11_PAIR_PRESET,
    build_scene11_comparison_report,
    build_scene11_run_summary,
    classify_scene11_run_summary,
    Scene11DebuggerSnapshot,
    Scene11ObjectSnapshot,
    Scene11RuntimeCandidate,
    Scene11RunSummary,
    collect_scene11_debugger_snapshot,
    discover_scene11_runtime_candidates,
    determine_scene11_snapshot_verdict,
    drive_scene11_launch_startup,
    load_scene11_run_summary,
    resolve_direct_launch_save,
    scene11_object_status,
    scene11_runtime_pair_owner,
    summarize_scene11_runtime_mismatch,
    write_scene11_run_summary,
)
from scenes.scene11_live import SCENE11_LIVE_PAIR_PRESET
from scenes.tavern import (
    TAVERN_TRACE_PRESET,
    TavernTraceController,
    cleanup_tavern_launch,
    drive_tavern_launch_startup,
)


DEFAULT_BASIC_TARGET_OBJECT = 0
DEFAULT_BASIC_TARGET_OPCODE = 0x76
DEFAULT_BASIC_TARGET_OFFSET = 46

run_direct_frida_trace = runtime.run_direct_frida_trace
run_structured_trace_via_frida = runtime.run_structured_trace_via_frida
run_structured_debugger_snapshot = runtime.run_structured_debugger_snapshot
run_structured_trace_via_fra = runtime.run_structured_trace_via_fra
run_fra_json = runtime.run_fra_json
fra_status_fields = runtime.fra_status_fields
read_fra_probe_records = runtime.read_fra_probe_records
queue_fra_probe_messages = runtime.queue_fra_probe_messages
refresh_fra_probe_terminal_state = runtime.refresh_fra_probe_terminal_state
process_exists_pid = runtime.process_exists_pid
terminate_spawned_process = runtime.terminate_spawned_process
wait_for_process_exit = runtime.wait_for_process_exit


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    argv_list = list(sys.argv[1:] if argv is None else argv)
    callsites_jsonl_explicit = "--callsites-jsonl" in argv_list
    parser = argparse.ArgumentParser(
        description="Bounded runtime evidence probe for the original Windows LBA2 life interpreter."
    )
    parser.add_argument("--process", default="LBA2.EXE", help="Process name to attach to.")
    parser.add_argument(
        "--launch",
        nargs="?",
        const=str(DEFAULT_GAME_EXE),
        help="Launch the executable and attach before resuming it. Defaults to the checked-in runtime when passed without a path.",
    )
    parser.add_argument(
        "--keep-alive",
        action="store_true",
        help="Leave a spawned process running after the tracer exits.",
    )
    parser.add_argument(
        "--takeover-existing-processes",
        action="store_true",
        help="Kill existing LBA2.EXE/cdb.exe processes before launch. Default is fail-fast to protect manual proof sessions.",
    )
    parser.add_argument("--run-root", default=str(DEFAULT_RUN_ROOT), help="Root directory for life_trace run bundles.")
    parser.add_argument(
        "--callsites-jsonl",
        default=str(DEFAULT_CALLSITES_JSONL),
        help=(
            "LM helper callsite JSONL map. "
            f"Defaults to {DEFAULT_CALLSITES_JSONL}."
        ),
    )
    parser.add_argument("--module", default="LBA2.EXE", help="Main module name.")
    parser.add_argument(
        "--frida-repo-root",
        default=None,
        help="Frida repository root containing build/install-root. Supported by basic mode only.",
    )
    parser.add_argument(
        "--fra-repo-root",
        default=None,
        help="frida-agent-cli repository root containing .venv. Supported by FRA-backed structured scene modes.",
    )
    parser.add_argument(
        "--cdb-path",
        default=None,
        help="Optional explicit path to cdb.exe. Supported by debugger-backed structured scene modes.",
    )
    parser.add_argument("--mode", choices=["basic", *structured_scene_modes()], default="basic")
    parser.add_argument("--target-object", type=parse_int, default=None, help="Object index to match.")
    parser.add_argument("--target-opcode", type=parse_int, default=None, help="Opcode byte to match.")
    parser.add_argument("--target-offset", type=parse_int, default=None, help="PtrPrg - PtrLife offset to match.")
    parser.add_argument("--max-hits", type=parse_int, default=1, help="Stop after this many matched hits.")
    parser.add_argument(
        "--timeout-sec",
        type=float,
        default=None,
        help="Stop with an explicit failure if the bounded run does not complete in time.",
    )
    parser.add_argument("--window-before", type=parse_int, default=8, help="Bytes to include before PtrPrg.")
    parser.add_argument("--window-after", type=parse_int, default=8, help="Bytes to include after PtrPrg.")
    parser.add_argument("--log-all", action="store_true", help="Emit every DoLife loop hit instead of only matches.")
    parser.add_argument(
        "--launch-save",
        help="Optional save file path to pass as ArgV[1] when spawning the original runtime.",
    )
    args = parser.parse_args(argv_list)
    args.callsites_jsonl_explicit = callsites_jsonl_explicit

    if args.max_hits < 1:
        parser.error("--max-hits must be at least 1")
    if args.timeout_sec is not None and args.timeout_sec < 0:
        parser.error("--timeout-sec must be at least 0")
    args.run_root = str(Path(args.run_root))

    if args.mode == "basic":
        if args.fra_repo_root is not None:
            parser.error(f"--fra-repo-root requires --mode {' or --mode '.join(fra_structured_scene_modes())}")

        args.target_object = DEFAULT_BASIC_TARGET_OBJECT if args.target_object is None else args.target_object
        args.target_opcode = DEFAULT_BASIC_TARGET_OPCODE if args.target_opcode is None else args.target_opcode
        args.target_offset = DEFAULT_BASIC_TARGET_OFFSET if args.target_offset is None else args.target_offset
        args.focus_offset_start = None
        args.focus_offset_end = None
        args.fingerprint_offset = None
        args.fingerprint_hex = None
        args.fingerprint_bytes = ()
        args.comparison_object = None
        args.comparison_opcode = None
        args.comparison_offset = None
        args.timeout_sec = 0 if args.timeout_sec is None else args.timeout_sec
        args.frida_repo_root = str(DEFAULT_FRIDA_REPO_ROOT if args.frida_repo_root is None else Path(args.frida_repo_root))
        args.fra_repo_root = None
        args.requires_callsite_map = False
        args.helper_capture_enabled = False
        return args

    scene_spec = get_structured_scene_spec(args.mode)
    preset = scene_spec.preset

    if args.target_object is not None or args.target_opcode is not None or args.target_offset is not None:
        parser.error(f"--mode {args.mode} rejects --target-object, --target-opcode, and --target-offset")

    args.target_object = preset.target_object
    args.target_opcode = preset.target_opcode
    args.target_offset = preset.target_offset
    args.max_hits = preset.max_hits
    args.focus_offset_start = preset.focus_offset_start
    args.focus_offset_end = preset.focus_offset_end
    args.fingerprint_offset = preset.fingerprint_offset
    args.fingerprint_hex = preset.fingerprint_hex
    args.fingerprint_bytes = parse_hex_bytes(preset.fingerprint_hex) if preset.fingerprint_hex else ()
    args.timeout_sec = preset.default_timeout_sec if args.timeout_sec is None else args.timeout_sec
    args.comparison_object = preset.comparison_object
    args.comparison_opcode = preset.comparison_opcode
    args.comparison_offset = preset.comparison_offset
    args.launch_save = preset.launch_save if args.launch_save is None else args.launch_save
    if scene_spec.runtime_backend == "fra_probe":
        if args.frida_repo_root is not None:
            parser.error(f"--mode {args.mode} rejects --frida-repo-root; use --fra-repo-root")
        args.fra_repo_root = str(DEFAULT_FRA_REPO_ROOT if args.fra_repo_root is None else Path(args.fra_repo_root))
        args.frida_repo_root = None
    elif scene_spec.runtime_backend == "frida_probe":
        if args.fra_repo_root is not None:
            parser.error(f"--mode {args.mode} rejects --fra-repo-root; use --frida-repo-root")
        args.frida_repo_root = str(DEFAULT_FRIDA_REPO_ROOT if args.frida_repo_root is None else Path(args.frida_repo_root))
        args.fra_repo_root = None
    else:
        if args.frida_repo_root is not None:
            parser.error(f"--mode {args.mode} rejects --frida-repo-root; its canonical backend is debugger-owned")
        if args.fra_repo_root is not None:
            parser.error(f"--mode {args.mode} rejects --fra-repo-root; its canonical backend is debugger-owned")
        args.fra_repo_root = None
        args.frida_repo_root = None
    args.requires_callsite_map = scene_spec.requires_callsite_map
    args.helper_capture_enabled = scene_spec.helper_capture_enabled
    return args


def main() -> int:
    args = parse_args()
    run_root = Path(args.run_root).resolve()
    callsite_path = Path(args.callsites_jsonl).resolve() if args.callsites_jsonl else None
    callsite_index = None
    if callsite_path is not None:
        should_load_callsite_map = bool(args.requires_callsite_map or args.callsites_jsonl_explicit)
        if should_load_callsite_map:
            callsite_index = load_callsite_index(callsite_path)
    writer = JsonlWriter(
        run_root,
        mode=args.mode,
        process_name=args.process,
        launch_path=args.launch,
        launch_save=args.launch_save,
        callsite_artifact_path=callsite_path,
        callsite_index=callsite_index,
        requires_callsite_map=args.requires_callsite_map,
    )
    interrupted = threading.Event()

    def on_signal(signum, frame) -> None:
        del frame
        interrupted.set()
        signal_name = signal.Signals(signum).name if signum in signal.Signals._value2member_map_ else str(signum)
        sys.stderr.write(f"received {signal_name}; draining current trace state before shutdown\n")
        sys.stderr.flush()

    previous_handlers: dict[int, object] = {}
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            previous_handlers[sig] = signal.signal(sig, on_signal)
        except (AttributeError, ValueError):
            continue

    controller = None
    exit_code = None
    try:
        if args.mode == "basic":
            controller, exit_code = run_direct_frida_trace(args, writer, interrupted)
        else:
            scene_spec = get_structured_scene_spec(args.mode)
            if scene_spec.runtime_backend == "fra_probe":
                controller, exit_code = run_structured_trace_via_fra(args, writer, interrupted)
            elif scene_spec.runtime_backend == "frida_probe":
                controller, exit_code = run_structured_trace_via_frida(args, writer, interrupted)
            else:
                controller, exit_code = run_structured_debugger_snapshot(args, writer, interrupted)
    finally:
        writer.close()
        for sig, previous in previous_handlers.items():
            try:
                signal.signal(sig, previous)
            except (AttributeError, ValueError):
                continue

    if exit_code is not None:
        return exit_code
    if controller is None:
        return 1
    if controller.last_error:
        print(controller.last_error, file=sys.stderr)
    return controller.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
