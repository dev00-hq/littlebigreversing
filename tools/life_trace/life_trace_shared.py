from __future__ import annotations

import argparse
import json
import sys
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
DEFAULT_RUN_ROOT = REPO_ROOT / "work" / "life_trace" / "runs"
DEFAULT_SAVE_SOURCE_ROOT = REPO_ROOT / "work" / "saves"
DEFAULT_CALLSITES_JSONL = REPO_ROOT / "work" / "ghidra_projects" / "callsites" / "lm_helper_callsites.jsonl"
DEFAULT_GAME_EXE = (
    REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "LBA2.EXE"
)
DEFAULT_FRIDA_REPO_ROOT = Path(r"D:\repos\reverse\frida")
DEFAULT_FRA_REPO_ROOT = Path(r"D:\repos\frida-agent-cli")
TAVERN_POST_076_TIMEOUT_SEC = 2.0
TAVERN_ADELINE_ENTER_DELAY_SEC = 4.5
TAVERN_RESUME_ENTER_DELAY_SEC = 1.5
TAVERN_RESUME_SETTLE_DELAY_SEC = 2.0
TAVERN_STARTUP_WINDOW_TIMEOUT_SEC = 5.0
SCENE11_ADELINE_ENTER_DELAY_SEC = 5.0
DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC = 5.0
SCENE11_STARTUP_WINDOW_TIMEOUT_SEC = 5.0
TRACE_COMPLETE_STATUS_MESSAGE = "trace complete; no further probe events expected; process teardown may lag briefly"
TRACE_FINISHED_STATUS_MESSAGE = "trace finished; no further probe events expected"
SPAWNED_PROCESS_TERMINATE_GRACE_SEC = 3.0
SPAWNED_PROCESS_TERMINATE_POLL_SEC = 0.1


def parse_int(value: str) -> int:
    return int(value, 0)


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_hex_bytes(value: str) -> tuple[int, ...]:
    return tuple(int(part, 16) for part in value.split())


def default_run_id() -> str:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"life-trace-{timestamp}"


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
    helper_capture_enabled: BoolField = msgspec.field(name="helperCaptureEnabled", default=UNSET)
    requires_callsite_map: BoolField = msgspec.field(name="requiresCallsiteMap", default=UNSET)


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


class AgentHelperCallsiteEvent(AgentEvent, tag="helper_callsite"):
    callee_name: str
    caller_static_live: str
    caller_static_rel: str
    thread_id: int
    object_index: int
    owner_kind: str
    ptr_life: str
    ptr_prg: str
    ptr_prg_offset: int | None
    opcode: int | None
    opcode_hex: str | None
    trace_role: StrField = UNSET
    within_function: NullableStrField = UNSET
    within_entry: NullableStrField = UNSET
    call_instruction: NullableStrField = UNSET
    call_index: NullableIntField = UNSET
    callsite_status: StrField = UNSET


class AgentErrorEvent(AgentEvent, tag="error"):
    description: str
    stack: str | None = None


class PersistedStatusEvent(AgentStatusEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedTraceEvent(AgentTraceEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedTargetValidationEvent(AgentTargetValidationEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedBranchTraceEvent(AgentBranchTraceEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedWindowTraceEvent(AgentWindowTraceEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedDoLifeReturnEvent(AgentDoLifeReturnEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedHelperCallsiteEvent(AgentHelperCallsiteEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedErrorEvent(AgentErrorEvent):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET


class PersistedScreenshotEvent(msgspec.Struct, tag_field="kind", tag="screenshot", kw_only=True, forbid_unknown_fields=True):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
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
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET
    poi: str
    reason: str
    capture_status: str


class PersistedMemorySnapshotEvent(
    msgspec.Struct,
    tag_field="kind",
    tag="memory_snapshot",
    kw_only=True,
    forbid_unknown_fields=True,
):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
    timestamp_utc: StrField = UNSET
    snapshot_name: str
    debugger: str
    address: str
    object_index: NullableIntField = UNSET
    current_object: NullableStrField = UNSET
    relative_to: NullableStrField = UNSET
    relative_offset: NullableIntField = UNSET
    value_hex: NullableStrField = UNSET
    value_u16: NullableIntField = UNSET
    value_u32: NullableIntField = UNSET
    window: PointerWindow | UnsetType = UNSET


class PersistedVerdictEvent(msgspec.Struct, tag_field="kind", tag="verdict", kw_only=True, forbid_unknown_fields=True):
    event_id: StrField = UNSET
    run_id: StrField = UNSET
    source_stream: StrField = UNSET
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
    | AgentHelperCallsiteEvent
    | AgentErrorEvent
)

PersistedWireEventType = (
    PersistedStatusEvent
    | PersistedTraceEvent
    | PersistedTargetValidationEvent
    | PersistedBranchTraceEvent
    | PersistedWindowTraceEvent
    | PersistedDoLifeReturnEvent
    | PersistedHelperCallsiteEvent
    | PersistedErrorEvent
    | PersistedScreenshotEvent
    | PersistedScreenshotErrorEvent
    | PersistedMemorySnapshotEvent
    | PersistedVerdictEvent
)

AGENT_EVENT_TYPES = (
    AgentStatusEvent,
    AgentTraceEvent,
    AgentTargetValidationEvent,
    AgentBranchTraceEvent,
    AgentWindowTraceEvent,
    AgentDoLifeReturnEvent,
    AgentHelperCallsiteEvent,
    AgentErrorEvent,
)

PERSISTED_EVENT_TYPES = (
    PersistedStatusEvent,
    PersistedTraceEvent,
    PersistedTargetValidationEvent,
    PersistedBranchTraceEvent,
    PersistedWindowTraceEvent,
    PersistedDoLifeReturnEvent,
    PersistedHelperCallsiteEvent,
    PersistedErrorEvent,
    PersistedScreenshotEvent,
    PersistedScreenshotErrorEvent,
    PersistedMemorySnapshotEvent,
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
        helper_capture_enabled=args.helper_capture_enabled,
        requires_callsite_map=args.requires_callsite_map,
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
    run_id: str | None = None,
    source_stream: str | None = None,
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

    assigned_run_id = run_id
    if assigned_run_id is None and event.run_id is not UNSET:
        assigned_run_id = event.run_id
    if assigned_run_id is None:
        raise ValueError("run_id must be provided before serializing a persisted event")

    assigned_source_stream = source_stream
    if assigned_source_stream is None and event.source_stream is not UNSET:
        assigned_source_stream = event.source_stream
    if assigned_source_stream is None:
        raise ValueError("source_stream must be provided before serializing a persisted event")

    return msgspec.structs.replace(
        event,
        event_id=assigned_event_id,
        run_id=assigned_run_id,
        source_stream=assigned_source_stream,
        timestamp_utc=assigned_timestamp,
    )


def serialize_persisted_event(event: PersistedWireEventType) -> str:
    return json.dumps(msgspec.to_builtins(event), ensure_ascii=True, sort_keys=True)


def optional_value(value):
    return None if value is UNSET else value


def normalize_caller_static_rel(value: str) -> str:
    text = value.strip()
    if text.lower().startswith("0x"):
        text = text[2:]
    if not text or any(char not in "0123456789abcdefABCDEF" for char in text):
        raise ValueError(f"invalid caller_static_rel: {value!r}")
    return f"0x{text.upper().zfill(8)}"


def load_callsite_index(path: Path) -> dict[tuple[str, str], dict[str, object]]:
    if not path.exists():
        raise RuntimeError(f"callsite map does not exist: {path}")

    index: dict[tuple[str, str], dict[str, object]] = {}
    required_fields = {
        "callee_name",
        "caller_static_rel",
        "within_function",
        "within_entry",
        "call_instruction",
        "call_index",
    }
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"callsite map line {line_number} is not valid JSON: {path}") from exc
        if not isinstance(payload, dict):
            raise RuntimeError(f"callsite map line {line_number} is not an object: {path}")

        missing = sorted(required_fields - set(payload))
        if missing:
            joined = ", ".join(missing)
            raise RuntimeError(f"callsite map line {line_number} is missing required fields: {joined}")

        callee_name = payload["callee_name"]
        caller_static_rel = payload["caller_static_rel"]
        if not isinstance(callee_name, str):
            raise RuntimeError(f"callsite map line {line_number} has non-string callee_name")
        if not isinstance(caller_static_rel, str):
            raise RuntimeError(f"callsite map line {line_number} has non-string caller_static_rel")

        key = (callee_name, normalize_caller_static_rel(caller_static_rel))
        if key in index:
            raise RuntimeError(
                "duplicate callsite map key "
                f"{callee_name} {key[1]} at line {line_number}: {path}"
            )
        index[key] = payload
    return index


def enrich_helper_callsite_event(
    event: PersistedHelperCallsiteEvent,
    callsite_index: dict[tuple[str, str], dict[str, object]] | None,
) -> PersistedHelperCallsiteEvent:
    normalized = msgspec.structs.replace(
        event,
        caller_static_rel=normalize_caller_static_rel(event.caller_static_rel),
    )
    if callsite_index is None:
        return normalized

    key = (normalized.callee_name, normalized.caller_static_rel)
    row = callsite_index.get(key)
    if row is None:
        return msgspec.structs.replace(
            normalized,
            callsite_status="unmapped",
        )

    call_index = row.get("call_index")
    if not isinstance(call_index, int):
        raise RuntimeError(f"callsite map entry {event.callee_name} {key[1]} has non-int call_index")

    return msgspec.structs.replace(
        normalized,
        within_function=str(row["within_function"]),
        within_entry=str(row["within_entry"]),
        call_instruction=str(row["call_instruction"]),
        call_index=call_index,
        callsite_status="mapped",
    )


class JsonlWriter:
    def __init__(
        self,
        run_root: Path,
        *,
        mode: str | None = None,
        process_name: str | None = None,
        launch_path: str | None = None,
        launch_save: str | None = None,
        callsite_artifact_path: Path | None = None,
        callsite_index: dict[tuple[str, str], dict[str, object]] | None = None,
        requires_callsite_map: bool = False,
        run_id: str | None = None,
    ) -> None:
        self.run_root = run_root.resolve()
        self.run_root.mkdir(parents=True, exist_ok=True)
        self.run_id = default_run_id() if run_id is None else run_id
        self.bundle_root = self.run_root / self.run_id
        if self.bundle_root.exists():
            raise RuntimeError(f"life_trace run bundle already exists: {self.bundle_root}")
        self.bundle_root.mkdir(parents=True, exist_ok=False)
        self.raw_output_path = self.bundle_root / "raw.jsonl"
        self.enriched_output_path = self.bundle_root / "enriched.jsonl"
        self.manifest_path = self.bundle_root / "manifest.json"
        self.screenshot_dir = self.bundle_root / "screenshots"
        self.screenshot_dir.mkdir(parents=True, exist_ok=True)
        self.raw_handle = self.raw_output_path.open("w", encoding="utf-8", newline="\n")
        self.enriched_handle = self.enriched_output_path.open("w", encoding="utf-8", newline="\n")
        self._event_counter = 0
        self.callsite_index = callsite_index
        self.requires_callsite_map = requires_callsite_map
        self.last_helper_callsite_status: str | None = None
        self.last_helper_callsite_event_id: str | None = None
        self.last_helper_callsite_rel: str | None = None
        self.started_at_utc = utc_now_iso()
        self._manifest = {
            "schema_version": "life-trace-run-bundle-v1",
            "run_id": self.run_id,
            "mode": mode,
            "process_name": process_name,
            "pid": None,
            "launch_path": launch_path,
            "launch_save": launch_save,
            "callsite_artifact_path": None if callsite_artifact_path is None else str(callsite_artifact_path),
            "callsite_map_loaded": callsite_index is not None,
            "callsite_index_entries": 0 if callsite_index is None else len(callsite_index),
            "requires_callsite_map": requires_callsite_map,
            "started_at_utc": self.started_at_utc,
            "finished_at_utc": None,
            "artifacts": {
                "manifest": "manifest.json",
                "raw_jsonl": "raw.jsonl",
                "enriched_jsonl": "enriched.jsonl",
                "screenshots_dir": "screenshots",
            },
            "raw_records_written": 0,
            "enriched_records_written": 0,
        }
        self._write_manifest()

    def register_artifact(self, key: str, relative_path: str) -> None:
        if not key:
            raise ValueError("artifact key must not be empty")
        normalized = relative_path.replace("\\", "/")
        self._manifest["artifacts"][key] = normalized
        self._write_manifest()

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

        timestamp_utc = utc_now_iso()
        raw_record = finalize_persisted_event(
            enrich_helper_callsite_event(record, None)
            if isinstance(record, PersistedHelperCallsiteEvent)
            else record,
            event_id=assigned_event_id,
            run_id=self.run_id,
            source_stream="raw",
            timestamp_utc=timestamp_utc,
        )
        enriched_record = finalize_persisted_event(
            enrich_helper_callsite_event(record, self.callsite_index)
            if isinstance(record, PersistedHelperCallsiteEvent)
            else record,
            event_id=assigned_event_id,
            run_id=self.run_id,
            source_stream="enriched",
            timestamp_utc=timestamp_utc,
        )
        raw_line = serialize_persisted_event(raw_record)
        enriched_line = serialize_persisted_event(enriched_record)
        self.raw_handle.write(f"{raw_line}\n")
        self.raw_handle.flush()
        self.enriched_handle.write(f"{enriched_line}\n")
        self.enriched_handle.flush()
        self._manifest["raw_records_written"] += 1
        self._manifest["enriched_records_written"] += 1
        self._apply_manifest_event(raw_record)
        self._write_manifest()

        if isinstance(enriched_record, PersistedHelperCallsiteEvent):
            self.last_helper_callsite_status = optional_value(enriched_record.callsite_status)
            self.last_helper_callsite_event_id = assigned_event_id
            self.last_helper_callsite_rel = enriched_record.caller_static_rel
        else:
            self.last_helper_callsite_status = None
            self.last_helper_callsite_event_id = None
            self.last_helper_callsite_rel = None

        sys.stdout.write(f"{enriched_line}\n")
        sys.stdout.flush()
        return assigned_event_id

    def close(self) -> None:
        self._manifest["finished_at_utc"] = utc_now_iso()
        self._write_manifest()
        self.raw_handle.close()
        self.enriched_handle.close()

    def _apply_manifest_event(self, event: PersistedWireEventType) -> None:
        if not isinstance(event, PersistedStatusEvent):
            return
        if event.mode is not UNSET:
            self._manifest["mode"] = event.mode
        if event.process_name is not UNSET:
            self._manifest["process_name"] = event.process_name
        if event.pid is not UNSET:
            self._manifest["pid"] = event.pid
        if event.launch_path is not UNSET:
            self._manifest["launch_path"] = event.launch_path
        if event.launch_save is not UNSET:
            self._manifest["launch_save"] = event.launch_save

    def _write_manifest(self) -> None:
        self.manifest_path.write_text(
            json.dumps(self._manifest, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


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
