from __future__ import annotations

import argparse
import ctypes
import json
import os
import queue
import signal
import struct
import subprocess
import sys
import threading
import time
import zlib
from ctypes import wintypes
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

try:
    import msgspec
    from msgspec import UNSET, UnsetType
except ModuleNotFoundError as exc:
    raise SystemExit(
        "msgspec is required for tools/life_trace/trace_life.py; "
        "install repo requirements with `python3 -m pip install -r requirements.txt`."
    ) from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "work" / "life_trace"
DEFAULT_GAME_EXE = (
    REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "LBA2.EXE"
)
DEFAULT_FRIDA_REPO_ROOT = Path(r"D:\repos\reverse\frida")
DEFAULT_FRA_REPO_ROOT = Path(r"D:\repos\frida-agent-cli")
TAVERN_POST_076_TIMEOUT_SEC = 2.0


def parse_int(value: str) -> int:
    return int(value, 0)


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_hex_bytes(value: str) -> tuple[int, ...]:
    return tuple(int(part, 16) for part in value.split())


def default_output_path() -> str:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return str(DEFAULT_OUTPUT_DIR / f"life-trace-{timestamp}.jsonl")


@dataclass
class FraProbeRuntime:
    target_id: str
    probe_id: str
    artifact_path: Path
    consumed_records: int = 0
    terminal_event: str | None = None
    terminal_reason: str | None = None


@dataclass(frozen=True)
class TracePreset:
    name: str
    target_object: int
    target_opcode: int
    target_offset: int
    focus_offset_start: int
    focus_offset_end: int
    fingerprint_offset: int | None
    fingerprint_hex: str | None
    max_hits: int
    default_timeout_sec: float | None
    comparison_object: int | None = None
    comparison_opcode: int | None = None
    comparison_offset: int | None = None
    launch_save: str | None = None


DEFAULT_BASIC_TARGET_OBJECT = 0
DEFAULT_BASIC_TARGET_OPCODE = 0x76
DEFAULT_BASIC_TARGET_OFFSET = 46


TAVERN_TRACE_PRESET = TracePreset(
    name="tavern-trace",
    target_object=0,
    target_opcode=0x76,
    target_offset=4883,
    focus_offset_start=4780,
    focus_offset_end=4890,
    fingerprint_offset=40,
    fingerprint_hex="28 14 00 21 2F 00 23 0D 0E 00",
    max_hits=1,
    default_timeout_sec=60.0,
)

SCENE11_PAIR_PRESET = TracePreset(
    name="scene11-pair",
    target_object=12,
    target_opcode=0x74,
    target_offset=38,
    focus_offset_start=30,
    focus_offset_end=48,
    fingerprint_offset=30,
    fingerprint_hex="00 01 17 42 00 75 2D 00 74 17",
    max_hits=1,
    default_timeout_sec=60.0,
    comparison_object=18,
    comparison_opcode=0x76,
    comparison_offset=84,
    launch_save=str(
        REPO_ROOT
        / "work"
        / "_innoextract_full"
        / "Speedrun"
        / "Windows"
        / "LBA2_cdrom"
        / "LBA2"
        / "SAVE"
        / "scene11-pair.LBA"
    ),
)


NullableStrField = str | None | UnsetType
NullableIntField = int | None | UnsetType
NullableBoolField = bool | None | UnsetType
StrField = str | UnsetType
IntField = int | UnsetType
BoolField = bool | UnsetType


class TraceConfig(msgspec.Struct, kw_only=True, forbid_unknown_fields=True):
    module_name: StrField = msgspec.field(name="moduleName", default=UNSET)
    mode: StrField = UNSET
    log_all: BoolField = msgspec.field(name="logAll", default=UNSET)
    max_hits: IntField = msgspec.field(name="maxHits", default=UNSET)
    target_object: IntField = msgspec.field(name="targetObject", default=UNSET)
    target_opcode: IntField = msgspec.field(name="targetOpcode", default=UNSET)
    target_offset: IntField = msgspec.field(name="targetOffset", default=UNSET)
    window_before: IntField = msgspec.field(name="windowBefore", default=UNSET)
    window_after: IntField = msgspec.field(name="windowAfter", default=UNSET)
    focus_offset_start: NullableIntField = msgspec.field(name="focusOffsetStart", default=UNSET)
    focus_offset_end: NullableIntField = msgspec.field(name="focusOffsetEnd", default=UNSET)
    fingerprint_offset: NullableIntField = msgspec.field(name="fingerprintOffset", default=UNSET)
    fingerprint_hex: NullableStrField = msgspec.field(name="fingerprintHex", default=UNSET)
    fingerprint_bytes: list[int] | UnsetType = msgspec.field(name="fingerprintBytes", default=UNSET)
    comparison_object: NullableIntField = msgspec.field(name="comparisonObject", default=UNSET)
    comparison_opcode: NullableIntField = msgspec.field(name="comparisonOpcode", default=UNSET)
    comparison_offset: NullableIntField = msgspec.field(name="comparisonOffset", default=UNSET)


class PointerWindow(msgspec.Struct, kw_only=True, forbid_unknown_fields=True):
    start: str
    cursor_index: int
    bytes_hex: str | None
    error: StrField = UNSET


class ExeSwitchState(msgspec.Struct, kw_only=True, forbid_unknown_fields=True):
    func: int | None
    type_answer: int | None
    value: int | None


class AgentEvent(msgspec.Struct, tag_field="kind", kw_only=True, forbid_unknown_fields=True):
    pass


class AgentStatusEvent(AgentEvent, tag="status"):
    message: str
    config: TraceConfig | UnsetType = UNSET
    frida_lib: NullableStrField = UNSET
    frida_module: NullableStrField = UNSET
    frida_repo_root: NullableStrField = UNSET
    frida_root: NullableStrField = UNSET
    frida_site_packages: NullableStrField = UNSET
    launch_path: NullableStrField = UNSET
    launch_save: NullableStrField = UNSET
    matched_hits: IntField = UNSET
    mode: StrField = UNSET
    module_base: StrField = UNSET
    module_name: StrField = UNSET
    output_path: StrField = UNSET
    phase: NullableStrField = UNSET
    pid: IntField = UNSET
    process_name: StrField = UNSET
    timed_out: BoolField = UNSET


class AgentTraceEvent(AgentEvent, tag="trace"):
    thread_id: int
    object_index: int
    owner_kind: str
    current_object: str
    ptr_life: str
    offset_life: int | None
    ptr_prg: str
    ptr_prg_offset: int | None
    opcode: int | None
    opcode_hex: str | None
    byte_at_ptr_prg: int | None
    byte_at_ptr_prg_hex: str | None
    ptr_window: PointerWindow
    working_type_answer: int | None
    working_value: int | None
    exe_switch: ExeSwitchState
    matches_target: bool
    trace_role: StrField = UNSET


class AgentTargetValidationEvent(AgentEvent, tag="target_validation"):
    thread_id: int
    object_index: int
    owner_kind: str
    ptr_life: str
    fingerprint_start_offset: int
    fingerprint_hex_actual: str
    fingerprint_hex_expected: str
    matches_fingerprint: bool


class AgentBranchTraceEvent(AgentEvent, tag="branch_trace"):
    thread_id: int
    branch_kind: str
    object_index: int
    ptr_prg_offset_before: int | None
    operand_offset: int | None
    computed_target_offset: int | None
    exe_switch_before: ExeSwitchState
    exe_switch_after: ExeSwitchState
    comparison_result: BoolField = UNSET


class AgentWindowTraceEvent(AgentEvent, tag="window_trace"):
    thread_id: int
    object_index: int
    owner_kind: str
    current_object: str
    ptr_life: str
    offset_life: int | None
    matches_target: BoolField = UNSET
    ptr_prg: StrField = UNSET
    ptr_prg_offset: NullableIntField = UNSET
    opcode: NullableIntField = UNSET
    opcode_hex: NullableStrField = UNSET
    ptr_window: PointerWindow | UnsetType = UNSET
    working_type_answer: NullableIntField = UNSET
    working_value: NullableIntField = UNSET
    exe_switch: ExeSwitchState | UnsetType = UNSET
    post_076_outcome: StrField = UNSET
    trace_role: StrField = UNSET
    fetched_in_do_life_loop: BoolField = UNSET
    ptr_prg_before: StrField = UNSET
    ptr_prg_before_offset: NullableIntField = UNSET
    byte_at_ptr_prg: NullableIntField = UNSET
    byte_at_ptr_prg_hex: NullableStrField = UNSET
    ptr_window_before: PointerWindow | UnsetType = UNSET
    working_type_answer_before: NullableIntField = UNSET
    working_value_before: NullableIntField = UNSET
    exe_switch_before: ExeSwitchState | UnsetType = UNSET
    ptr_prg_after: StrField = UNSET
    ptr_prg_after_offset: NullableIntField = UNSET
    next_opcode: NullableIntField = UNSET
    next_opcode_hex: NullableStrField = UNSET
    ptr_window_after: PointerWindow | UnsetType = UNSET
    working_type_answer_after: NullableIntField = UNSET
    working_value_after: NullableIntField = UNSET
    exe_switch_after: ExeSwitchState | UnsetType = UNSET
    entered_do_func_life: BoolField = UNSET
    entered_do_test: BoolField = UNSET
    post_hit_outcome: StrField = UNSET


class AgentDoLifeReturnEvent(AgentEvent, tag="do_life_return"):
    trace_role: str
    thread_id: int
    object_index: int
    owner_kind: str
    current_object: str
    ptr_life: str
    offset_life: int | None
    fetched_in_do_life_loop: bool
    ptr_prg_before: str
    ptr_prg_before_offset: int | None
    byte_at_ptr_prg: int | None
    byte_at_ptr_prg_hex: str | None
    ptr_window_before: PointerWindow
    working_type_answer_before: int | None
    working_value_before: int | None
    exe_switch_before: ExeSwitchState
    ptr_prg_after: str
    ptr_prg_after_offset: int | None
    next_opcode: int | None
    next_opcode_hex: str | None
    ptr_window_after: PointerWindow
    working_type_answer_after: int | None
    working_value_after: int | None
    exe_switch_after: ExeSwitchState
    entered_do_func_life: bool
    entered_do_test: bool
    post_hit_outcome: str


class AgentErrorEvent(AgentEvent, tag="error"):
    description: str
    stack: str | None = None


class PersistedStatusEvent(AgentStatusEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedTraceEvent(AgentTraceEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedTargetValidationEvent(AgentTargetValidationEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedBranchTraceEvent(AgentBranchTraceEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedWindowTraceEvent(AgentWindowTraceEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedDoLifeReturnEvent(AgentDoLifeReturnEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedErrorEvent(AgentErrorEvent):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedScreenshotEvent(msgspec.Struct, tag_field="kind", tag="screenshot", kw_only=True, forbid_unknown_fields=True):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET
    poi: str
    screenshot_path: str
    source_window_title: str
    capture_status: str


class PersistedScreenshotErrorEvent(
    msgspec.Struct,
    tag_field="kind",
    tag="screenshot_error",
    kw_only=True,
    forbid_unknown_fields=True,
):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET
    poi: str
    reason: str
    capture_status: str


class PersistedVerdictEvent(msgspec.Struct, tag_field="kind", tag="verdict", kw_only=True, forbid_unknown_fields=True):
    event_id: StrField = UNSET
    timestamp_utc: StrField = UNSET
    phase: str
    matched_fingerprint: bool
    required_screenshots_complete: bool
    result: str
    reason: str
    break_target_offset: NullableIntField = UNSET
    break_target_proof_event_id: NullableStrField = UNSET
    comparison_entered_do_func_life: NullableBoolField = UNSET
    comparison_entered_do_test: NullableBoolField = UNSET
    comparison_event_id: NullableStrField = UNSET
    comparison_post_hit_outcome: NullableStrField = UNSET
    expected_break_offset: NullableIntField = UNSET
    expected_break_target_offset: NullableIntField = UNSET
    fingerprint_event_id: NullableStrField = UNSET
    hidden_076_case_seen: BoolField = UNSET
    opcode_076_fetch_event_id: NullableStrField = UNSET
    post_076_outcome: NullableStrField = UNSET
    post_076_outcome_event_id: NullableStrField = UNSET
    primary_entered_do_func_life: NullableBoolField = UNSET
    primary_entered_do_test: NullableBoolField = UNSET
    primary_event_id: NullableStrField = UNSET
    primary_post_hit_outcome: NullableStrField = UNSET
    returned_after_076: BoolField = UNSET
    saw_076_fetch: BoolField = UNSET
    saw_break_at_43: BoolField = UNSET
    saw_expected_break: BoolField = UNSET
    saw_post_076_loop: BoolField = UNSET


AgentWireEventType = (
    AgentStatusEvent
    | AgentTraceEvent
    | AgentTargetValidationEvent
    | AgentBranchTraceEvent
    | AgentWindowTraceEvent
    | AgentDoLifeReturnEvent
    | AgentErrorEvent
)

PersistedWireEventType = (
    PersistedStatusEvent
    | PersistedTraceEvent
    | PersistedTargetValidationEvent
    | PersistedBranchTraceEvent
    | PersistedWindowTraceEvent
    | PersistedDoLifeReturnEvent
    | PersistedErrorEvent
    | PersistedScreenshotEvent
    | PersistedScreenshotErrorEvent
    | PersistedVerdictEvent
)

AGENT_EVENT_TYPES = (
    AgentStatusEvent,
    AgentTraceEvent,
    AgentTargetValidationEvent,
    AgentBranchTraceEvent,
    AgentWindowTraceEvent,
    AgentDoLifeReturnEvent,
    AgentErrorEvent,
)

PERSISTED_EVENT_TYPES = (
    PersistedStatusEvent,
    PersistedTraceEvent,
    PersistedTargetValidationEvent,
    PersistedBranchTraceEvent,
    PersistedWindowTraceEvent,
    PersistedDoLifeReturnEvent,
    PersistedErrorEvent,
    PersistedScreenshotEvent,
    PersistedScreenshotErrorEvent,
    PersistedVerdictEvent,
)


def build_trace_config(args: argparse.Namespace) -> TraceConfig:
    return TraceConfig(
        module_name=args.module,
        mode=args.mode,
        log_all=args.log_all,
        max_hits=args.max_hits,
        target_object=args.target_object,
        target_opcode=args.target_opcode,
        target_offset=args.target_offset,
        window_before=args.window_before,
        window_after=args.window_after,
        focus_offset_start=args.focus_offset_start,
        focus_offset_end=args.focus_offset_end,
        fingerprint_offset=args.fingerprint_offset,
        fingerprint_hex=args.fingerprint_hex,
        fingerprint_bytes=list(args.fingerprint_bytes),
        comparison_object=args.comparison_object,
        comparison_opcode=args.comparison_opcode,
        comparison_offset=args.comparison_offset,
    )


def convert_agent_event(payload: object) -> AgentWireEventType:
    return msgspec.convert(payload, AgentWireEventType)


def convert_persisted_event(payload: object) -> PersistedWireEventType:
    return msgspec.convert(payload, PersistedWireEventType)


def parse_persisted_event_line(line: str) -> PersistedWireEventType:
    return convert_persisted_event(json.loads(line))


def persist_agent_event(event: AgentWireEventType) -> PersistedWireEventType:
    return convert_persisted_event(msgspec.to_builtins(event))


def finalize_persisted_event(
    event: PersistedWireEventType,
    *,
    event_id: str | None = None,
    timestamp_utc: str | None = None,
) -> PersistedWireEventType:
    assigned_event_id = event_id
    if assigned_event_id is None and event.event_id is not UNSET:
        assigned_event_id = event.event_id
    if assigned_event_id is None:
        raise ValueError("event_id must be provided before serializing a persisted event")

    assigned_timestamp = timestamp_utc
    if assigned_timestamp is None and event.timestamp_utc is not UNSET:
        assigned_timestamp = event.timestamp_utc
    if assigned_timestamp is None:
        assigned_timestamp = utc_now_iso()

    return msgspec.structs.replace(
        event,
        event_id=assigned_event_id,
        timestamp_utc=assigned_timestamp,
    )


def serialize_persisted_event(event: PersistedWireEventType) -> str:
    return json.dumps(msgspec.to_builtins(event), ensure_ascii=True, sort_keys=True)


def optional_value(value):
    return None if value is UNSET else value


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    argv_list = list(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(
        description="Bounded Frida probe for the original Windows LBA2 life interpreter."
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
        "--output",
        default=None,
        help="JSONL output path. Defaults under work/life_trace/ when omitted.",
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
        help="frida-agent-cli repository root containing .venv. Supported by tavern-trace and scene11-pair modes.",
    )
    parser.add_argument("--mode", choices=["basic", "tavern-trace", "scene11-pair"], default="basic")
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
        "--screenshot-dir",
        help="Root screenshot directory. Only supported with --mode tavern-trace or --mode scene11-pair.",
    )
    parser.add_argument(
        "--launch-save",
        help="Optional save file path to pass as ArgV[1] when spawning the original runtime.",
    )
    args = parser.parse_args(argv_list)

    if args.max_hits < 1:
        parser.error("--max-hits must be at least 1")
    if args.timeout_sec is not None and args.timeout_sec < 0:
        parser.error("--timeout-sec must be at least 0")
    if args.output is None:
        args.output = default_output_path()

    if args.mode not in ("tavern-trace", "scene11-pair") and args.screenshot_dir is not None:
        parser.error("--screenshot-dir requires --mode tavern-trace or --mode scene11-pair")

    if args.mode == "tavern-trace":
        preset = TAVERN_TRACE_PRESET
        if args.target_object is not None or args.target_opcode is not None or args.target_offset is not None:
            parser.error("--mode tavern-trace rejects --target-object, --target-opcode, and --target-offset")
        if args.frida_repo_root is not None:
            parser.error("--mode tavern-trace rejects --frida-repo-root; use --fra-repo-root")

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
        if args.screenshot_dir is None:
            args.screenshot_dir = str(REPO_ROOT / "work" / "life_trace" / "shots")
        args.fra_repo_root = str(DEFAULT_FRA_REPO_ROOT if args.fra_repo_root is None else Path(args.fra_repo_root))
    elif args.mode == "scene11-pair":
        preset = SCENE11_PAIR_PRESET
        if args.target_object is not None or args.target_opcode is not None or args.target_offset is not None:
            parser.error("--mode scene11-pair rejects --target-object, --target-opcode, and --target-offset")
        if args.frida_repo_root is not None:
            parser.error("--mode scene11-pair rejects --frida-repo-root; use --fra-repo-root")

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
        if args.screenshot_dir is None:
            args.screenshot_dir = str(REPO_ROOT / "work" / "life_trace" / "shots")
        args.fra_repo_root = str(DEFAULT_FRA_REPO_ROOT if args.fra_repo_root is None else Path(args.fra_repo_root))
    else:
        if args.fra_repo_root is not None:
            parser.error("--fra-repo-root requires --mode tavern-trace or --mode scene11-pair")
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

    if args.mode == "basic":
        args.fra_repo_root = None
    else:
        args.frida_repo_root = None

    return args


def ensure_staged_frida(repo_root: Path) -> tuple[Path, Path, Path]:
    frida_root = repo_root / "build" / "install-root" / "Program Files" / "Frida"
    site_packages = frida_root / "lib" / "site-packages"
    frida_bin = frida_root / "bin"
    frida_lib = frida_root / "lib" / "frida" / "x86_64"

    missing = [path for path in (frida_root, site_packages, frida_bin, frida_lib) if not path.exists()]
    if missing:
        missing_text = "\n".join(str(path) for path in missing)
        raise RuntimeError(
            "missing staged Frida paths:\n"
            f"{missing_text}\n"
            "build the local Frida repo and install it into build/install-root first"
        )

    sys.path.insert(0, str(site_packages))
    os.environ["PYTHONPATH"] = str(site_packages)
    os.environ["PATH"] = os.pathsep.join([str(frida_bin), str(frida_lib), os.environ.get("PATH", "")])

    return frida_root, site_packages, frida_lib


def load_agent_source(args: argparse.Namespace) -> str:
    config = build_trace_config(args)
    template = (Path(__file__).with_name("agent.js")).read_text(encoding="utf-8")
    return template.replace(
        "__TRACE_CONFIG__",
        json.dumps(msgspec.to_builtins(config), separators=(",", ":")),
    )


def find_process(device, process_name: str):
    target = process_name.lower()
    for process in device.enumerate_processes():
        if process.name.lower() == target:
            return process
    raise RuntimeError(f"process not found: {process_name}")


def process_exists(device, pid: int) -> bool:
    try:
        return any(process.pid == pid for process in device.enumerate_processes())
    except Exception:  # noqa: BLE001
        return False


def process_exists_pid(pid: int) -> bool:
    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if handle == 0:
        return False
    kernel32.CloseHandle(handle)
    return True


def resolve_fra_launcher(repo_root: Path) -> list[str]:
    python_exe = repo_root / ".venv" / "Scripts" / "python.exe"
    if not python_exe.exists():
        raise RuntimeError(
            "missing fra launcher: "
            f"{python_exe}\n"
            "build or restore the frida-agent-cli virtual environment first"
        )
    return [str(python_exe), "-m", "fra"]


def run_fra_json(
    fra_launcher: list[str],
    *fra_args: str,
    input_text: str | None = None,
) -> dict | list:
    completed = subprocess.run(
        [*fra_launcher, *fra_args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        input=input_text,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or "<no output>"
        raise RuntimeError(
            f"fra command failed ({completed.returncode}): {' '.join(fra_args)}\n{detail}"
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"fra command returned invalid JSON: {' '.join(fra_args)}"
        ) from exc


def fra_status_fields(doctor_report: dict) -> dict[str, str | None]:
    if not doctor_report.get("ok"):
        failing_checks = [
            f"{check.get('name')}: {check.get('detail')}"
            for check in doctor_report.get("checks", [])
            if isinstance(check, dict) and not check.get("ok")
        ]
        details = "\n".join(failing_checks) if failing_checks else json.dumps(doctor_report, indent=2)
        raise RuntimeError(f"fra doctor failed:\n{details}")

    bootstrap = doctor_report.get("bootstrap") if isinstance(doctor_report.get("bootstrap"), dict) else {}
    paths = bootstrap.get("paths") if isinstance(bootstrap.get("paths"), dict) else {}
    frida = doctor_report.get("frida") if isinstance(doctor_report.get("frida"), dict) else {}
    return {
        "frida_module": frida.get("module_path"),
        "frida_repo_root": paths.get("repo_root"),
        "frida_root": paths.get("staged_root"),
        "frida_site_packages": paths.get("site_packages"),
        "frida_lib": paths.get("dll_dir"),
    }

def read_fra_probe_records(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
) -> list[dict]:
    payload = run_fra_json(
        fra_launcher,
        "probe",
        "tail",
        "--artifact",
        str(runtime.artifact_path),
        "--format",
        "json",
    )
    if not isinstance(payload, list):
        raise RuntimeError("fra probe tail returned an unexpected payload")
    if runtime.consumed_records > len(payload):
        raise RuntimeError("fra probe tail returned fewer records than the tracer already consumed")

    new_records = payload[runtime.consumed_records :]
    runtime.consumed_records = len(payload)

    normalized: list[dict] = []
    for record in new_records:
        if not isinstance(record, dict):
            raise RuntimeError("fra probe tail returned a non-dict record")
        normalized.append(record)
    return normalized


def queue_fra_probe_messages(
    runtime: FraProbeRuntime,
    records: list[dict],
    message_queue: queue.Queue[AgentWireEventType],
) -> None:
    for record in records:
        if record.get("kind") != "probe_message":
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            raise RuntimeError("fra probe tail returned a non-dict message")
        event = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)


def try_wait_for_fra_probe_lifecycle(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
    event: str,
) -> dict | None:
    completed = subprocess.run(
        [
            *fra_launcher,
            "probe",
            "wait",
            "--artifact",
            str(runtime.artifact_path),
            "--lifecycle-event",
            event,
            "--timeout",
            "0",
            "--format",
            "json",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode == 0:
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"fra probe wait returned invalid JSON for lifecycle {event}"
            ) from exc
        if not isinstance(payload, dict):
            raise RuntimeError("fra probe wait returned an unexpected payload")
        return payload

    detail = (completed.stderr or completed.stdout).strip()
    if "timed out waiting for a matching probe artifact record" in detail:
        return None
    raise RuntimeError(
        f"fra probe wait failed ({completed.returncode}) for lifecycle {event}: {detail or '<no output>'}"
    )


def refresh_fra_probe_terminal_state(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
) -> None:
    if runtime.terminal_event is not None:
        return

    for event in ("terminated", "detached", "removed"):
        record = try_wait_for_fra_probe_lifecycle(fra_launcher, runtime, event)
        if record is None:
            continue
        runtime.terminal_event = event
        reason = record.get("reason")
        runtime.terminal_reason = None if reason is None else str(reason)
        return


class JsonlWriter:
    def __init__(self, output_path: Path) -> None:
        self.output_path = output_path
        self.output_path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.output_path.open("w", encoding="utf-8", newline="\n")
        self._event_counter = 0
        self.run_id = self.output_path.stem

    def next_event_id(self) -> str:
        self._event_counter += 1
        return f"evt-{self._event_counter:04d}"

    def write_event(
        self,
        event: AgentWireEventType | PersistedWireEventType,
        *,
        event_id: str | None = None,
    ) -> str:
        if isinstance(event, PERSISTED_EVENT_TYPES):
            record = event
        elif isinstance(event, AGENT_EVENT_TYPES):
            record = persist_agent_event(event)
        else:
            raise TypeError(f"unsupported event type: {type(event)!r}")

        assigned_event_id = event_id
        if assigned_event_id is None and record.event_id is not UNSET:
            assigned_event_id = record.event_id
        if assigned_event_id is None:
            assigned_event_id = self.next_event_id()

        record = finalize_persisted_event(record, event_id=assigned_event_id)
        line = serialize_persisted_event(record)
        self.handle.write(f"{line}\n")
        self.handle.flush()
        sys.stdout.write(f"{line}\n")
        sys.stdout.flush()
        return assigned_event_id

    def close(self) -> None:
        self.handle.close()


def normalize_script_message(message: dict) -> AgentWireEventType | None:
    if message.get("type") == "send":
        payload = message.get("payload")
        if not isinstance(payload, dict):
            raise RuntimeError(f"unexpected Frida payload type: {type(payload)!r}")

        event = dict(payload)
        nested_payload = event.pop("payload", None)
        if nested_payload is not None:
            if not isinstance(nested_payload, dict):
                raise RuntimeError(f"unexpected Frida nested payload type: {type(nested_payload)!r}")
            event.update(nested_payload)
        return convert_agent_event(event)

    if message.get("type") == "error":
        return AgentErrorEvent(
            description=message.get("description") or "unknown script error",
            stack=message.get("stack"),
        )

    return None


@dataclass(frozen=True)
class WindowInfo:
    hwnd: int
    title: str
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top


class CaptureError(RuntimeError):
    pass


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", ctypes.c_long),
        ("biHeight", ctypes.c_long),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", ctypes.c_long),
        ("biYPelsPerMeter", ctypes.c_long),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [
        ("bmiHeader", BITMAPINFOHEADER),
        ("bmiColors", wintypes.DWORD * 3),
    ]


class WindowCapture:
    SRCCOPY = 0x00CC0020
    CAPTUREBLT = 0x40000000
    DIB_RGB_COLORS = 0
    BI_RGB = 0
    GW_OWNER = 4

    def __init__(self) -> None:
        if os.name != "nt":
            raise RuntimeError("window capture is only supported on Windows")

        self.user32 = ctypes.windll.user32
        self.gdi32 = ctypes.windll.gdi32

        self.user32.EnumWindows.argtypes = [ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM), wintypes.LPARAM]
        self.user32.EnumWindows.restype = wintypes.BOOL
        self.user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
        self.user32.GetWindowThreadProcessId.restype = wintypes.DWORD
        self.user32.IsWindowVisible.argtypes = [wintypes.HWND]
        self.user32.IsWindowVisible.restype = wintypes.BOOL
        self.user32.IsIconic.argtypes = [wintypes.HWND]
        self.user32.IsIconic.restype = wintypes.BOOL
        self.user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(RECT)]
        self.user32.GetWindowRect.restype = wintypes.BOOL
        self.user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
        self.user32.GetWindowTextLengthW.restype = ctypes.c_int
        self.user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
        self.user32.GetWindowTextW.restype = ctypes.c_int
        self.user32.GetWindow.argtypes = [wintypes.HWND, wintypes.UINT]
        self.user32.GetWindow.restype = wintypes.HWND
        self.user32.GetDC.argtypes = [wintypes.HWND]
        self.user32.GetDC.restype = wintypes.HDC
        self.user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
        self.user32.ReleaseDC.restype = ctypes.c_int

        self.gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
        self.gdi32.CreateCompatibleDC.restype = wintypes.HDC
        self.gdi32.DeleteDC.argtypes = [wintypes.HDC]
        self.gdi32.DeleteDC.restype = wintypes.BOOL
        self.gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
        self.gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
        self.gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
        self.gdi32.SelectObject.restype = wintypes.HGDIOBJ
        self.gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
        self.gdi32.DeleteObject.restype = wintypes.BOOL
        self.gdi32.BitBlt.argtypes = [
            wintypes.HDC,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_int,
            wintypes.HDC,
            ctypes.c_int,
            ctypes.c_int,
            wintypes.DWORD,
        ]
        self.gdi32.BitBlt.restype = wintypes.BOOL
        self.gdi32.GetDIBits.argtypes = [
            wintypes.HDC,
            wintypes.HBITMAP,
            wintypes.UINT,
            wintypes.UINT,
            ctypes.c_void_p,
            ctypes.POINTER(BITMAPINFO),
            wintypes.UINT,
        ]
        self.gdi32.GetDIBits.restype = ctypes.c_int

        try:
            self.user32.SetProcessDPIAware()
        except AttributeError:
            pass

    def wait_for_window(self, pid: int, timeout_sec: float = 10.0) -> WindowInfo:
        deadline = time.monotonic() + timeout_sec
        while True:
            window = self.find_window(pid)
            if window is not None:
                return window
            if time.monotonic() >= deadline:
                raise CaptureError(f"window for pid {pid} did not become capturable within {timeout_sec:g} seconds")
            time.sleep(0.1)

    def find_window(self, pid: int) -> WindowInfo | None:
        candidates: list[WindowInfo] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def enum_proc(hwnd, _lparam):
            process_id = wintypes.DWORD()
            self.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
            if process_id.value != pid:
                return True
            if not self.user32.IsWindowVisible(hwnd):
                return True
            if self.user32.IsIconic(hwnd):
                return True

            rect = RECT()
            if not self.user32.GetWindowRect(hwnd, ctypes.byref(rect)):
                return True
            if rect.right <= rect.left or rect.bottom <= rect.top:
                return True

            title_length = self.user32.GetWindowTextLengthW(hwnd)
            title_buffer = ctypes.create_unicode_buffer(title_length + 1)
            self.user32.GetWindowTextW(hwnd, title_buffer, len(title_buffer))
            candidates.append(
                WindowInfo(
                    hwnd=int(hwnd),
                    title=title_buffer.value,
                    left=rect.left,
                    top=rect.top,
                    right=rect.right,
                    bottom=rect.bottom,
                )
            )
            return True

        self.user32.EnumWindows(enum_proc, 0)
        if not candidates:
            return None

        def sort_key(window: WindowInfo) -> tuple[int, int, int]:
            owner = self.user32.GetWindow(window.hwnd, self.GW_OWNER)
            area = window.width * window.height
            return (1 if not owner else 0, area, len(window.title))

        candidates.sort(key=sort_key, reverse=True)
        return candidates[0]

    def capture(self, pid: int, output_path: Path, timeout_sec: float = 10.0) -> WindowInfo:
        window = self.wait_for_window(pid, timeout_sec=timeout_sec)
        width = window.width
        height = window.height
        if width <= 0 or height <= 0:
            raise CaptureError(f"window {window.hwnd:#x} has invalid bounds {width}x{height}")

        screen_dc = self.user32.GetDC(0)
        if not screen_dc:
            raise CaptureError("GetDC(NULL) failed")

        mem_dc = self.gdi32.CreateCompatibleDC(screen_dc)
        if not mem_dc:
            self.user32.ReleaseDC(0, screen_dc)
            raise CaptureError("CreateCompatibleDC failed")

        bitmap = self.gdi32.CreateCompatibleBitmap(screen_dc, width, height)
        if not bitmap:
            self.gdi32.DeleteDC(mem_dc)
            self.user32.ReleaseDC(0, screen_dc)
            raise CaptureError("CreateCompatibleBitmap failed")

        old_object = self.gdi32.SelectObject(mem_dc, bitmap)
        if not old_object:
            self.gdi32.DeleteObject(bitmap)
            self.gdi32.DeleteDC(mem_dc)
            self.user32.ReleaseDC(0, screen_dc)
            raise CaptureError("SelectObject failed")

        try:
            rop = self.SRCCOPY | self.CAPTUREBLT
            if not self.gdi32.BitBlt(mem_dc, 0, 0, width, height, screen_dc, window.left, window.top, rop):
                raise CaptureError("BitBlt failed")

            bitmap_info = BITMAPINFO()
            bitmap_info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
            bitmap_info.bmiHeader.biWidth = width
            bitmap_info.bmiHeader.biHeight = -height
            bitmap_info.bmiHeader.biPlanes = 1
            bitmap_info.bmiHeader.biBitCount = 32
            bitmap_info.bmiHeader.biCompression = self.BI_RGB

            raw = ctypes.create_string_buffer(width * height * 4)
            rows = self.gdi32.GetDIBits(
                mem_dc,
                bitmap,
                0,
                height,
                raw,
                ctypes.byref(bitmap_info),
                self.DIB_RGB_COLORS,
            )
            if rows != height:
                raise CaptureError(f"GetDIBits returned {rows}, expected {height}")

            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(self.encode_png_rgba(width, height, raw.raw))
            if not output_path.exists():
                raise CaptureError(f"capture file was not written: {output_path}")
            return window
        finally:
            self.gdi32.SelectObject(mem_dc, old_object)
            self.gdi32.DeleteObject(bitmap)
            self.gdi32.DeleteDC(mem_dc)
            self.user32.ReleaseDC(0, screen_dc)

    @staticmethod
    def encode_png_rgba(width: int, height: int, bgra_bytes: bytes) -> bytes:
        stride = width * 4
        source = memoryview(bgra_bytes)
        rows = bytearray()
        for y in range(height):
            row = source[y * stride : (y + 1) * stride]
            rows.append(0)
            for index in range(0, stride, 4):
                blue = row[index]
                green = row[index + 1]
                red = row[index + 2]
                alpha = row[index + 3]
                rows.extend((red, green, blue, alpha))

        def chunk(tag: bytes, payload: bytes) -> bytes:
            crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
            return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

        header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
        image_data = zlib.compress(bytes(rows), level=9)
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", image_data) + chunk(b"IEND", b"")


class BasicTraceController:
    def __init__(self, args: argparse.Namespace, writer: JsonlWriter) -> None:
        self.args = args
        self.writer = writer
        self.matched_hits = 0
        self.exit_code = 0
        self.terminal = False
        self.last_error: str | None = None

    def begin(self) -> None:
        return

    def handle_event(self, event: AgentWireEventType) -> None:
        self.writer.write_event(event)
        if isinstance(event, AgentTraceEvent) and event.matches_target:
            self.matched_hits += 1
            if self.matched_hits >= self.args.max_hits:
                self.terminal = True
        elif isinstance(event, AgentErrorEvent):
            self.last_error = event.description or "unknown error"
            self.exit_code = 1
            self.terminal = True

    def handle_timeout(self) -> None:
        description = f"timed out without a matched hit after {self.args.timeout_sec:g} seconds"
        self.writer.write_event(
            PersistedStatusEvent(
                message=description,
                matched_hits=self.matched_hits,
                timed_out=True,
            )
        )
        self.last_error = description
        self.exit_code = 1
        self.terminal = True

    def handle_interrupt(self) -> None:
        self.writer.write_event(
            PersistedStatusEvent(
                message="interrupted",
                matched_hits=self.matched_hits,
            )
        )
        self.last_error = "interrupted"
        self.exit_code = 1
        self.terminal = True

    def next_deadline(self) -> float | None:
        return None

    def poll(self, now: float) -> None:
        return


class TavernTraceController:
    def __init__(self, args: argparse.Namespace, writer: JsonlWriter, pid: int) -> None:
        self.args = args
        self.writer = writer
        self.pid = pid
        self.phase = "attached"
        self.exit_code = 1
        self.terminal = False
        self.last_error: str | None = None

        self.capture = WindowCapture()
        self.screenshot_root = Path(args.screenshot_dir).resolve()
        self.run_screenshot_dir = self.screenshot_root / writer.run_id
        self.run_screenshot_dir.mkdir(parents=True, exist_ok=True)

        self.matched_fingerprint = False
        self.active_thread_id: int | None = None
        self.break_target_offset: int | None = None
        self.saw_076_fetch = False
        self.post_076_thread_id: int | None = None
        self.post_076_deadline: float | None = None
        self.post_076_outcome: str | None = None
        self.post_076_outcome_event_id: str | None = None
        self.saw_post_076_loop = False
        self.returned_after_076 = False
        self.hidden_076_case_seen = False
        self.opcode_076_event_id: str | None = None
        self.fingerprint_event_id: str | None = None
        self.required_screenshots: dict[str, str] = {}

    def begin(self) -> None:
        self._advance_phase("waiting_for_fingerprint", "waiting for the Tavern fingerprint")

    def handle_event(self, event: AgentWireEventType) -> None:
        event_id = self.writer.write_event(event)
        if isinstance(event, AgentErrorEvent):
            self._finalize("unexpected_control_flow", event.description or "agent error", take_final_screenshot=True)
            return

        if isinstance(event, AgentTargetValidationEvent) and event.matches_fingerprint:
            if not self.matched_fingerprint:
                self.matched_fingerprint = True
                self.active_thread_id = event.thread_id
                self.fingerprint_event_id = event_id
                self._advance_phase("armed_for_window", "fingerprint matched; waiting for the switch window")
                self._capture_required_poi(
                    poi="fingerprint_match",
                    event_id=event_id,
                    object_index=event.object_index,
                    offset_value=event.fingerprint_start_offset,
                )
            return

        if not self._is_tracked_event(event):
            return

        if isinstance(event, AgentBranchTraceEvent):
            if self.phase == "armed_for_window":
                self._advance_phase("capturing_tavern_trace", "capturing the Tavern switch window")

            if event.branch_kind == "break_jump":
                self.break_target_offset = event.computed_target_offset

            if self.saw_076_fetch and self.post_076_outcome is None:
                self.post_076_outcome = f"branch_trace:{event.branch_kind}"
                self.post_076_outcome_event_id = event_id
                self._finalize_tavern_verdict()
            return

        if isinstance(event, AgentWindowTraceEvent):
            offset_value = optional_value(event.ptr_prg_offset)
            opcode_value = optional_value(event.opcode)
            if offset_value == self.args.target_offset and opcode_value == self.args.target_opcode:
                if not self.saw_076_fetch:
                    self.saw_076_fetch = True
                    self.post_076_thread_id = event.thread_id
                    self.post_076_deadline = time.monotonic() + TAVERN_POST_076_TIMEOUT_SEC
                    self.opcode_076_event_id = event_id
                    self._advance_phase("capturing_verdict", "captured the 0x76 fetch; waiting for the next outcome")
                    self._capture_required_poi(
                        poi="opcode_076_fetch",
                        event_id=event_id,
                        object_index=event.object_index,
                        offset_value=offset_value,
                    )
                return

            if (
                self.saw_076_fetch
                and self.post_076_outcome is None
                and event.thread_id == self.post_076_thread_id
                and optional_value(event.post_076_outcome) == "loop_reentry"
            ):
                self.saw_post_076_loop = True
                self.post_076_outcome = "loop_reentry"
                self.post_076_outcome_event_id = event_id
                self._finalize_tavern_verdict()
            return

        if isinstance(event, AgentDoLifeReturnEvent) and self.saw_076_fetch and self.post_076_outcome is None:
            self.returned_after_076 = True
            self.post_076_outcome = "do_life_return"
            self.post_076_outcome_event_id = event_id
            self._finalize_tavern_verdict()

    def handle_timeout(self) -> None:
        if not self.matched_fingerprint:
            self._finalize(
                "timed_out_before_fingerprint",
                f"timed out after {self.args.timeout_sec:g} seconds before the Tavern fingerprint matched",
                take_final_screenshot=True,
            )
            return

        self._finalize(
            "timed_out_before_076",
            f"timed out after {self.args.timeout_sec:g} seconds before capturing the Tavern 0x76 fetch",
            take_final_screenshot=True,
        )

    def handle_interrupt(self) -> None:
        self._finalize("unexpected_control_flow", "interrupted before the Tavern trace completed", take_final_screenshot=True)

    def next_deadline(self) -> float | None:
        return self.post_076_deadline

    def poll(self, now: float) -> None:
        if self.post_076_deadline is not None and now >= self.post_076_deadline and not self.terminal:
            self._finalize(
                "unexpected_control_flow",
                "captured opcode 0x76 but did not capture a bounded post-0x76 outcome before the follow-up timeout expired",
                take_final_screenshot=True,
            )

    def _is_tracked_event(self, event: AgentBranchTraceEvent | AgentWindowTraceEvent | AgentDoLifeReturnEvent) -> bool:
        return (
            self.active_thread_id is not None
            and event.thread_id == self.active_thread_id
            and event.object_index == self.args.target_object
        )

    def _advance_phase(self, phase: str, message: str) -> None:
        if self.phase == phase or self.terminal:
            return
        self.phase = phase
        self.writer.write_event(PersistedStatusEvent(phase=phase, message=message))

    def _capture_required_poi(self, poi: str, event_id: str, object_index: int, offset_value: int | None) -> None:
        if poi in self.required_screenshots or self.terminal:
            return

        try:
            screenshot_path, window = self._capture_window_file(poi, event_id, object_index, offset_value)
        except CaptureError as error:
            self.writer.write_event(
                PersistedScreenshotErrorEvent(
                    poi=poi,
                    reason=str(error),
                    capture_status="failed",
                ),
                event_id=event_id,
            )
            self._finalize(
                "screenshot_capture_failed",
                f"required screenshot failed for {poi}: {error}",
                take_final_screenshot=False,
            )
            return

        self.required_screenshots[poi] = screenshot_path
        self.writer.write_event(
            PersistedScreenshotEvent(
                poi=poi,
                screenshot_path=screenshot_path,
                source_window_title=window.title,
                capture_status="captured",
            ),
            event_id=event_id,
        )

    def _capture_window_file(
        self,
        poi: str,
        event_id: str,
        object_index: int,
        offset_value: int | None,
    ) -> tuple[str, WindowInfo]:
        filename = f"{event_id}__{poi}__obj{object_index}__off{self._format_offset(offset_value)}.png"
        absolute_path = self.run_screenshot_dir / filename
        window = self.capture.capture(self.pid, absolute_path)
        return self._display_path(absolute_path), window

    def _display_path(self, path: Path) -> str:
        try:
            return str(path.relative_to(REPO_ROOT)).replace("\\", "/")
        except ValueError:
            return str(path)

    @staticmethod
    def _format_offset(offset_value: int | None) -> str:
        if offset_value is None:
            return "na"
        return f"{int(offset_value):03d}"

    def _finalize_tavern_verdict(self) -> None:
        if (
            self.matched_fingerprint
            and self.saw_076_fetch
            and self.post_076_outcome is not None
            and not self.hidden_076_case_seen
        ):
            self._finalize("tavern_trace_complete", f"captured Tavern proof through {self.post_076_outcome}", take_final_screenshot=True)
            return

        self._finalize(
            "unexpected_control_flow",
            f"captured a post-0x76 outcome ({self.post_076_outcome}) without the full canonical Tavern proof sequence",
            take_final_screenshot=True,
        )

    def _finalize(self, result: str, reason: str, *, take_final_screenshot: bool) -> None:
        if self.terminal:
            return

        verdict_event_id = self.writer.next_event_id()
        if take_final_screenshot:
            try:
                screenshot_path, window = self._capture_window_file(
                    poi="final_verdict",
                    event_id=verdict_event_id,
                    object_index=self.args.target_object,
                    offset_value=self.args.target_offset,
                )
            except CaptureError as error:
                self.writer.write_event(
                    PersistedScreenshotErrorEvent(
                        poi="final_verdict",
                        reason=str(error),
                        capture_status="failed",
                    ),
                    event_id=verdict_event_id,
                )
                result = "screenshot_capture_failed"
                reason = f"required screenshot failed for final_verdict: {error}"
            else:
                self.required_screenshots["final_verdict"] = screenshot_path
                self.writer.write_event(
                    PersistedScreenshotEvent(
                        poi="final_verdict",
                        screenshot_path=screenshot_path,
                        source_window_title=window.title,
                        capture_status="captured",
                    ),
                    event_id=verdict_event_id,
                )

        required_screenshots_complete = (
            result != "screenshot_capture_failed"
            and self._required_pois() <= set(self.required_screenshots)
        )

        self.writer.write_event(
            PersistedVerdictEvent(
                phase="completed",
                matched_fingerprint=self.matched_fingerprint,
                break_target_offset=self.break_target_offset,
                saw_076_fetch=self.saw_076_fetch,
                saw_post_076_loop=self.saw_post_076_loop,
                returned_after_076=self.returned_after_076,
                hidden_076_case_seen=self.hidden_076_case_seen,
                required_screenshots_complete=required_screenshots_complete,
                result=result,
                reason=reason,
                fingerprint_event_id=self.fingerprint_event_id,
                opcode_076_fetch_event_id=self.opcode_076_event_id,
                post_076_outcome=self.post_076_outcome,
                post_076_outcome_event_id=self.post_076_outcome_event_id,
            ),
            event_id=verdict_event_id,
        )

        if self.phase != "completed":
            self.phase = "completed"

        self.last_error = None if result == "tavern_trace_complete" else reason
        self.exit_code = 0 if result == "tavern_trace_complete" else 1
        self.terminal = True

    def _required_pois(self) -> set[str]:
        required: set[str] = set()
        if self.matched_fingerprint:
            required.add("fingerprint_match")
        if self.saw_076_fetch:
            required.add("opcode_076_fetch")
        required.add("final_verdict")
        return required


class Scene11PairController:
    def __init__(self, args: argparse.Namespace, writer: JsonlWriter, pid: int) -> None:
        self.args = args
        self.writer = writer
        self.pid = pid
        self.phase = "attached"
        self.exit_code = 1
        self.terminal = False
        self.last_error: str | None = None

        self.capture = WindowCapture()
        self.screenshot_root = Path(args.screenshot_dir).resolve()
        self.run_screenshot_dir = self.screenshot_root / writer.run_id
        self.run_screenshot_dir.mkdir(parents=True, exist_ok=True)

        self.matched_fingerprint = False
        self.fingerprint_event_id: str | None = None
        self.primary_event_id: str | None = None
        self.primary_event: AgentWindowTraceEvent | AgentDoLifeReturnEvent | None = None
        self.comparison_event_id: str | None = None
        self.comparison_event: AgentWindowTraceEvent | AgentDoLifeReturnEvent | None = None
        self.required_screenshots: dict[str, str] = {}

    def begin(self) -> None:
        self._advance_phase("waiting_for_fingerprint", "waiting for the canonical scene-11 fingerprint")

    def handle_event(self, event: AgentWireEventType) -> None:
        event_id = self.writer.write_event(event)
        if isinstance(event, AgentErrorEvent):
            self._finalize("unexpected_control_flow", event.description or "agent error", take_final_screenshot=True)
            return

        if isinstance(event, AgentTargetValidationEvent) and event.matches_fingerprint:
            if not self.matched_fingerprint:
                self.matched_fingerprint = True
                self.fingerprint_event_id = event_id
                self._advance_phase("capturing_primary", "scene-11 fingerprint matched; waiting for object 12 LM_DEFAULT")
                self._capture_required_poi(
                    poi="fingerprint_match",
                    event_id=event_id,
                    object_index=event.object_index,
                    offset_value=event.fingerprint_start_offset,
                )
            return

        if not isinstance(event, (AgentWindowTraceEvent, AgentDoLifeReturnEvent)):
            return

        trace_role = optional_value(event.trace_role)
        if trace_role == "primary" and self.primary_event_id is None:
            self.primary_event_id = event_id
            self.primary_event = event
            self._capture_required_poi(
                poi="primary_opcode_hit",
                event_id=event_id,
                object_index=event.object_index,
                offset_value=optional_value(event.ptr_prg_before_offset) if isinstance(event, AgentWindowTraceEvent) else event.ptr_prg_before_offset,
            )
            self._advance_phase("capturing_comparison", "captured object 12 LM_DEFAULT; waiting for object 18 LM_END_SWITCH")
            if self.comparison_event_id is not None:
                self._finalize_scene11_verdict()
            return

        if trace_role == "comparison" and self.comparison_event_id is None:
            self.comparison_event_id = event_id
            self.comparison_event = event
            self._capture_required_poi(
                poi="comparison_opcode_hit",
                event_id=event_id,
                object_index=event.object_index,
                offset_value=optional_value(event.ptr_prg_before_offset) if isinstance(event, AgentWindowTraceEvent) else event.ptr_prg_before_offset,
            )
            if self.primary_event_id is None:
                self._advance_phase("capturing_primary", "captured object 18 comparison early; still waiting for object 12 LM_DEFAULT")
            else:
                self._finalize_scene11_verdict()

    def handle_timeout(self) -> None:
        if not self.matched_fingerprint:
            self._finalize(
                "timed_out_before_fingerprint",
                f"timed out after {self.args.timeout_sec:g} seconds before the canonical scene-11 fingerprint matched",
                take_final_screenshot=True,
            )
            return

        if self.primary_event_id is None:
            self._finalize(
                "timed_out_before_primary",
                f"timed out after {self.args.timeout_sec:g} seconds before capturing object {self.args.target_object} opcode 0x{self.args.target_opcode:02X} at offset {self.args.target_offset}",
                take_final_screenshot=True,
            )
            return

        self._finalize(
            "timed_out_before_comparison",
            f"timed out after {self.args.timeout_sec:g} seconds before capturing object {self.args.comparison_object} opcode 0x{self.args.comparison_opcode:02X} at offset {self.args.comparison_offset}",
            take_final_screenshot=True,
        )

    def handle_interrupt(self) -> None:
        self._finalize("unexpected_control_flow", "interrupted before the scene-11 pair trace completed", take_final_screenshot=True)

    def next_deadline(self) -> float | None:
        return None

    def poll(self, now: float) -> None:
        return

    def _advance_phase(self, phase: str, message: str) -> None:
        if self.phase == phase or self.terminal:
            return
        self.phase = phase
        self.writer.write_event(PersistedStatusEvent(phase=phase, message=message))

    def _capture_required_poi(self, poi: str, event_id: str, object_index: int, offset_value: int | None) -> None:
        if poi in self.required_screenshots or self.terminal:
            return

        try:
            screenshot_path, window = self._capture_window_file(poi, event_id, object_index, offset_value)
        except CaptureError as error:
            self.writer.write_event(
                PersistedScreenshotErrorEvent(
                    poi=poi,
                    reason=str(error),
                    capture_status="failed",
                ),
                event_id=event_id,
            )
            self._finalize(
                "screenshot_capture_failed",
                f"required screenshot failed for {poi}: {error}",
                take_final_screenshot=False,
            )
            return

        self.required_screenshots[poi] = screenshot_path
        self.writer.write_event(
            PersistedScreenshotEvent(
                poi=poi,
                screenshot_path=screenshot_path,
                source_window_title=window.title,
                capture_status="captured",
            ),
            event_id=event_id,
        )

    def _capture_window_file(
        self,
        poi: str,
        event_id: str,
        object_index: int,
        offset_value: int | None,
    ) -> tuple[str, WindowInfo]:
        filename = f"{event_id}__{poi}__obj{object_index}__off{self._format_offset(offset_value)}.png"
        absolute_path = self.run_screenshot_dir / filename
        window = self.capture.capture(self.pid, absolute_path)
        return self._display_path(absolute_path), window

    def _display_path(self, path: Path) -> str:
        try:
            return str(path.relative_to(REPO_ROOT)).replace("\\", "/")
        except ValueError:
            return str(path)

    @staticmethod
    def _format_offset(offset_value: int | None) -> str:
        if offset_value is None:
            return "na"
        return f"{int(offset_value):03d}"

    def _finalize_scene11_verdict(self) -> None:
        if self.matched_fingerprint and self.primary_event_id is not None and self.comparison_event_id is not None:
            self._finalize(
                "scene11_pair_complete",
                "captured scene-11 LM_DEFAULT and LM_END_SWITCH evidence on live paths",
                take_final_screenshot=True,
            )
            return

        self._finalize(
            "unexpected_control_flow",
            "captured an incomplete scene-11 pair evidence set",
            take_final_screenshot=True,
        )

    def _finalize(self, result: str, reason: str, *, take_final_screenshot: bool) -> None:
        if self.terminal:
            return

        verdict_event_id = self.writer.next_event_id()
        if take_final_screenshot:
            try:
                screenshot_path, window = self._capture_window_file(
                    poi="final_verdict",
                    event_id=verdict_event_id,
                    object_index=self.args.target_object,
                    offset_value=self.args.target_offset,
                )
            except CaptureError as error:
                self.writer.write_event(
                    PersistedScreenshotErrorEvent(
                        poi="final_verdict",
                        reason=str(error),
                        capture_status="failed",
                    ),
                    event_id=verdict_event_id,
                )
                result = "screenshot_capture_failed"
                reason = f"required screenshot failed for final_verdict: {error}"
            else:
                self.required_screenshots["final_verdict"] = screenshot_path
                self.writer.write_event(
                    PersistedScreenshotEvent(
                        poi="final_verdict",
                        screenshot_path=screenshot_path,
                        source_window_title=window.title,
                        capture_status="captured",
                    ),
                    event_id=verdict_event_id,
                )

        required_screenshots_complete = (
            result != "screenshot_capture_failed"
            and self._required_pois() <= set(self.required_screenshots)
        )

        self.writer.write_event(
            PersistedVerdictEvent(
                phase="completed",
                matched_fingerprint=self.matched_fingerprint,
                required_screenshots_complete=required_screenshots_complete,
                result=result,
                reason=reason,
                fingerprint_event_id=self.fingerprint_event_id,
                primary_event_id=self.primary_event_id,
                primary_post_hit_outcome=None if self.primary_event is None else optional_value(self.primary_event.post_hit_outcome),
                primary_entered_do_func_life=None if self.primary_event is None else optional_value(self.primary_event.entered_do_func_life),
                primary_entered_do_test=None if self.primary_event is None else optional_value(self.primary_event.entered_do_test),
                comparison_event_id=self.comparison_event_id,
                comparison_post_hit_outcome=None if self.comparison_event is None else optional_value(self.comparison_event.post_hit_outcome),
                comparison_entered_do_func_life=None if self.comparison_event is None else optional_value(self.comparison_event.entered_do_func_life),
                comparison_entered_do_test=None if self.comparison_event is None else optional_value(self.comparison_event.entered_do_test),
            ),
            event_id=verdict_event_id,
        )

        if self.phase != "completed":
            self.phase = "completed"

        self.last_error = None if result == "scene11_pair_complete" else reason
        self.exit_code = 0 if result == "scene11_pair_complete" else 1
        self.terminal = True

    def _required_pois(self) -> set[str]:
        required: set[str] = set()
        if self.matched_fingerprint:
            required.add("fingerprint_match")
        if self.primary_event_id is not None:
            required.add("primary_opcode_hit")
        if self.comparison_event_id is not None:
            required.add("comparison_opcode_hit")
        required.add("final_verdict")
        return required


def run_direct_frida_trace(
    args: argparse.Namespace,
    writer: JsonlWriter,
    output_path: Path,
    interrupted: threading.Event,
) -> tuple[BasicTraceController | TavernTraceController | Scene11PairController | None, int | None]:
    message_queue: queue.Queue[AgentWireEventType] = queue.Queue()

    repo_root = Path(args.frida_repo_root).resolve()
    frida_root, site_packages, frida_lib = ensure_staged_frida(repo_root)

    import frida

    device = frida.get_local_device()
    session = None
    script = None
    spawned_pid: int | None = None
    controller: BasicTraceController | TavernTraceController | Scene11PairController | None = None

    def on_message(message: dict, data) -> None:
        event = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)

    try:
        if args.launch:
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawn_argv = [str(launch_path)]
            if args.launch_save is not None:
                launch_save_path = Path(args.launch_save)
                if not launch_save_path.exists():
                    raise RuntimeError(f"launch save path does not exist: {launch_save_path}")
                spawn_argv.append(str(launch_save_path))
            spawned_pid = device.spawn(spawn_argv, cwd=str(launch_path.parent))
            pid = spawned_pid
        else:
            process = find_process(device, args.process)
            pid = process.pid

        if args.mode == "scene11-pair":
            controller = Scene11PairController(args, writer, pid)
        else:
            controller = BasicTraceController(args, writer)

        session = device.attach(pid)
        script = session.create_script(load_agent_source(args))
        script.on("message", on_message)
        script.load()

        writer.write_event(
            PersistedStatusEvent(
                frida_module=getattr(frida, "__file__", None),
                frida_repo_root=str(repo_root),
                frida_root=str(frida_root),
                frida_site_packages=str(site_packages),
                frida_lib=str(frida_lib),
                message="attached",
                mode=args.mode,
                output_path=str(output_path),
                pid=pid,
                process_name=args.process,
                launch_path=args.launch,
                launch_save=args.launch_save,
            )
        )

        if spawned_pid is not None:
            device.resume(spawned_pid)
            writer.write_event(
                PersistedStatusEvent(
                    message="resumed spawned process",
                    pid=spawned_pid,
                )
            )

        controller.begin()

        deadline = None
        if args.timeout_sec is not None and args.timeout_sec > 0:
            deadline = time.monotonic() + args.timeout_sec

        while controller is not None and not controller.terminal:
            if interrupted.is_set():
                controller.handle_interrupt()
                break

            if not process_exists(device, pid):
                writer.write_event(
                    PersistedStatusEvent(
                        message="target process exited",
                        pid=pid,
                    )
                )
                if isinstance(controller, Scene11PairController):
                    controller._finalize(
                        "process_exited",
                        f"process {pid} exited before the structured trace completed",
                        take_final_screenshot=False,
                    )
                else:
                    controller.last_error = f"process {pid} exited"
                    controller.exit_code = 1
                    controller.terminal = True
                break

            now = time.monotonic()
            controller.poll(now)
            if controller.terminal:
                break

            if deadline is not None and now >= deadline:
                controller.handle_timeout()
                break

            wakeups = [0.25]
            next_deadline = controller.next_deadline()
            if deadline is not None:
                wakeups.append(max(0.0, deadline - now))
            if next_deadline is not None:
                wakeups.append(max(0.0, next_deadline - now))
            timeout = max(0.01, min(wakeups))

            try:
                event = message_queue.get(timeout=timeout)
            except queue.Empty:
                continue
            controller.handle_event(event)
    except Exception as error:  # noqa: BLE001
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        if controller is not None and isinstance(controller, Scene11PairController) and not controller.terminal:
            controller._finalize("unexpected_control_flow", str(error), take_final_screenshot=True)
        elif controller is not None:
            controller.last_error = str(error)
            controller.exit_code = 1
            controller.terminal = True
        elif controller is None:
            print(str(error), file=sys.stderr)
            return None, 1
    finally:
        if script is not None:
            try:
                script.unload()
            except Exception:  # noqa: BLE001
                pass

        if session is not None:
            try:
                session.detach()
            except Exception:  # noqa: BLE001
                pass

        if spawned_pid is not None:
            if args.keep_alive:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving spawned process alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    device.kill(spawned_pid)
                    writer.write_event(
                        PersistedStatusEvent(
                            message="killed spawned process",
                            pid=spawned_pid,
                        )
                    )
                except Exception:  # noqa: BLE001
                    pass

    return controller, None


def run_structured_trace_via_fra(
    args: argparse.Namespace,
    writer: JsonlWriter,
    output_path: Path,
    interrupted: threading.Event,
) -> tuple[TavernTraceController | Scene11PairController | None, int | None]:
    message_queue: queue.Queue[AgentWireEventType] = queue.Queue()

    fra_repo_root = Path(args.fra_repo_root).resolve()
    fra_launcher = resolve_fra_launcher(fra_repo_root)
    doctor_report = run_fra_json(fra_launcher, "doctor", "--format", "json")
    status_fields = fra_status_fields(doctor_report if isinstance(doctor_report, dict) else {})

    target_id: str | None = None
    probe_runtime: FraProbeRuntime | None = None
    controller: TavernTraceController | Scene11PairController | None = None
    spawned_pid: int | None = None
    pid: int | None = None

    try:
        if args.launch:
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawn_args = [
                "target",
                "spawn",
                "--format",
                "json",
                "--cwd",
                str(launch_path.parent),
                str(launch_path),
            ]
            if args.launch_save is not None:
                launch_save_path = Path(args.launch_save)
                if not launch_save_path.exists():
                    raise RuntimeError(f"launch save path does not exist: {launch_save_path}")
                spawn_args.append(str(launch_save_path))
            target_record = run_fra_json(fra_launcher, *spawn_args)
        else:
            target_record = run_fra_json(
                fra_launcher,
                "target",
                "attach",
                "--format",
                "json",
                args.process,
            )
        if not isinstance(target_record, dict):
            raise RuntimeError("fra target command returned an unexpected payload")

        target_id = str(target_record["target_id"])
        pid = int(target_record["pid"])
        if args.launch:
            spawned_pid = pid

        if args.mode == "scene11-pair":
            controller = Scene11PairController(args, writer, pid)
        else:
            controller = TavernTraceController(args, writer, pid)
        probe_record = run_fra_json(
            fra_launcher,
            "probe",
            "add",
            "--target",
            target_id,
            "--format",
            "json",
            "--stdin",
            input_text=load_agent_source(args),
        )
        if not isinstance(probe_record, dict):
            raise RuntimeError("fra probe add returned an unexpected payload")
        probe_runtime = FraProbeRuntime(
            target_id=target_id,
            probe_id=str(probe_record["probe_id"]),
            artifact_path=Path(str(probe_record["event_artifact"])),
        )

        writer.write_event(
            PersistedStatusEvent(
                phase="attached",
                frida_module=status_fields["frida_module"],
                frida_repo_root=status_fields["frida_repo_root"],
                frida_root=status_fields["frida_root"],
                frida_site_packages=status_fields["frida_site_packages"],
                frida_lib=status_fields["frida_lib"],
                message="attached",
                mode=args.mode,
                output_path=str(output_path),
                pid=pid,
                process_name=args.process,
                launch_path=args.launch,
                launch_save=args.launch_save,
            )
        )

        if spawned_pid is not None:
            run_fra_json(
                fra_launcher,
                "target",
                "resume",
                "--target",
                target_id,
                "--format",
                "json",
            )
            writer.write_event(
                PersistedStatusEvent(
                    message="resumed spawned process",
                    pid=spawned_pid,
                )
            )

        controller.begin()

        deadline = None
        if args.timeout_sec is not None and args.timeout_sec > 0:
            deadline = time.monotonic() + args.timeout_sec

        while controller is not None and not controller.terminal:
            if interrupted.is_set():
                controller.handle_interrupt()
                break

            if probe_runtime is not None:
                queue_fra_probe_messages(
                    probe_runtime,
                    read_fra_probe_records(fra_launcher, probe_runtime),
                    message_queue,
                )
                refresh_fra_probe_terminal_state(fra_launcher, probe_runtime)
                if probe_runtime.terminal_event in {"detached", "terminated", "removed"}:
                    reason_suffix = (
                        ""
                        if not probe_runtime.terminal_reason
                        else f" ({probe_runtime.terminal_reason})"
                    )
                    writer.write_event(
                        PersistedStatusEvent(
                            message=f"fra probe {probe_runtime.terminal_event}{reason_suffix}",
                            pid=pid,
                        )
                    )
                    controller._finalize(
                        "process_exited" if probe_runtime.terminal_event == "terminated" else "unexpected_control_flow",
                        f"fra probe {probe_runtime.terminal_event} ended before the structured trace completed{reason_suffix}",
                        take_final_screenshot=False,
                    )
                    break

            if pid is not None and not process_exists_pid(pid):
                writer.write_event(
                    PersistedStatusEvent(
                        message="target process exited",
                        pid=pid,
                    )
                )
                controller._finalize(
                    "process_exited",
                    f"process {pid} exited before the structured trace completed",
                    take_final_screenshot=False,
                )
                break

            now = time.monotonic()
            controller.poll(now)
            if controller.terminal:
                break

            if deadline is not None and now >= deadline:
                controller.handle_timeout()
                break

            wakeups = [0.25]
            next_deadline = controller.next_deadline()
            if deadline is not None:
                wakeups.append(max(0.0, deadline - now))
            if next_deadline is not None:
                wakeups.append(max(0.0, next_deadline - now))
            timeout = max(0.01, min(wakeups))

            try:
                event = message_queue.get(timeout=timeout)
            except queue.Empty:
                continue
            controller.handle_event(event)
    except Exception as error:  # noqa: BLE001
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        if controller is not None and not controller.terminal:
            controller._finalize("unexpected_control_flow", str(error), take_final_screenshot=True)
        elif controller is None:
            print(str(error), file=sys.stderr)
            return None, 1
    finally:
        if probe_runtime is not None:
            try:
                run_fra_json(
                    fra_launcher,
                    "probe",
                    "remove",
                    "--format",
                    "json",
                    probe_runtime.probe_id,
                )
            except Exception:  # noqa: BLE001
                pass

        if target_id is not None:
            if spawned_pid is not None:
                if args.keep_alive:
                    try:
                        run_fra_json(
                            fra_launcher,
                            "target",
                            "detach",
                            "--target",
                            target_id,
                            "--format",
                            "json",
                        )
                        writer.write_event(
                            PersistedStatusEvent(
                                message="leaving spawned process alive",
                                pid=spawned_pid,
                            )
                        )
                    except Exception:  # noqa: BLE001
                        pass
                else:
                    try:
                        run_fra_json(
                            fra_launcher,
                            "target",
                            "terminate",
                            "--target",
                            target_id,
                            "--format",
                            "json",
                        )
                        writer.write_event(
                            PersistedStatusEvent(
                                message="killed spawned process",
                                pid=spawned_pid,
                            )
                        )
                    except Exception:  # noqa: BLE001
                        pass
            else:
                try:
                    run_fra_json(
                        fra_launcher,
                        "target",
                        "detach",
                        "--target",
                        target_id,
                        "--format",
                        "json",
                    )
                except Exception:  # noqa: BLE001
                    pass

    return controller, None


def main() -> int:
    args = parse_args()
    output_path = Path(args.output).resolve()
    writer = JsonlWriter(output_path)
    interrupted = threading.Event()
    controller: BasicTraceController | TavernTraceController | Scene11PairController | None = None
    exit_override: int | None = None

    def handle_interrupt(signum, frame) -> None:
        _ = signum
        _ = frame
        interrupted.set()

    previous_sigint = signal.signal(signal.SIGINT, handle_interrupt)

    try:
        if args.mode == "basic":
            controller, exit_override = run_direct_frida_trace(args, writer, output_path, interrupted)
        else:
            controller, exit_override = run_structured_trace_via_fra(args, writer, output_path, interrupted)
    finally:
        signal.signal(signal.SIGINT, previous_sigint)
        writer.close()

    if exit_override is not None:
        return exit_override
    if controller is not None and controller.last_error:
        print(controller.last_error, file=sys.stderr)
    return 0 if controller is not None and controller.exit_code == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
