from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from life_trace_debugger import CdbMemoryReader, DebuggerReadError, resolve_cdb_path
from life_trace_shared import (
    JsonlWriter,
    PersistedMemorySnapshotEvent,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PersistedVerdictEvent,
    PointerWindow,
    REPO_ROOT,
    SCENE11_ADELINE_ENTER_DELAY_SEC,
    SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
    TRACE_COMPLETE_STATUS_MESSAGE,
    TRACE_FINISHED_STATUS_MESSAGE,
    TracePreset,
)
from life_trace_windows import CaptureError, WindowCapture, WindowInfo, WindowInput
from scenes.base import StructuredSceneSpec
from scenes.load_game import (
    cleanup_staged_load_game_save,
    default_source_save_path,
    drive_single_save_load_game_startup,
    stage_single_load_game_save,
)


OBJECT_BASE = 0x0049A19C
OBJECT_STRIDE = 0x21B
PTR_LIFE_OFFSET = 0x1EE
OFFSET_LIFE_OFFSET = 0x1F2
PTR_PRG_GLOBAL = 0x004976D0
WINDOW_BEFORE = 8
WINDOW_AFTER = 8


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
    launch_save=str(default_source_save_path("S8741.LBA")),
)


@dataclass(frozen=True)
class Scene11ObjectSnapshotSpec:
    label: str
    object_index: int
    target_offset: int
    expected_opcode: int


@dataclass(frozen=True)
class Scene11ObjectSnapshot:
    spec: Scene11ObjectSnapshotSpec
    current_object: int
    ptr_life_field: int
    ptr_life: int
    offset_life_field: int
    offset_life: int
    target_address: int | None
    target_window: PointerWindow
    target_byte: int | None


@dataclass(frozen=True)
class Scene11DebuggerSnapshot:
    ptr_prg: int
    primary: Scene11ObjectSnapshot
    comparison: Scene11ObjectSnapshot


@dataclass(frozen=True)
class Scene11RuntimeCandidate:
    object_index: int
    ptr_life: int
    offset_life: int
    opcode: int
    opcode_offset: int
    target_window: PointerWindow


DISCOVERY_SCAN_OBJECT_LIMIT = 48
DISCOVERY_SCAN_BYTE_LIMIT = 160
DISCOVERY_OPCODES = {
    0x74: "LM_DEFAULT",
    0x76: "LM_END_SWITCH",
}


class Scene11SnapshotReader(Protocol):
    def read_scalars(
        self,
        *,
        dword_addresses: tuple[int, ...],
        word_addresses: tuple[int, ...],
    ) -> tuple[dict[int, int], dict[int, int]]: ...

    def read_bytes(self, address: int, count: int) -> bytes: ...


PRIMARY_SNAPSHOT = Scene11ObjectSnapshotSpec(
    label="primary",
    object_index=SCENE11_PAIR_PRESET.target_object,
    target_offset=SCENE11_PAIR_PRESET.target_offset,
    expected_opcode=SCENE11_PAIR_PRESET.target_opcode,
)
COMPARISON_SNAPSHOT = Scene11ObjectSnapshotSpec(
    label="comparison",
    object_index=SCENE11_PAIR_PRESET.comparison_object or 18,
    target_offset=SCENE11_PAIR_PRESET.comparison_offset or 84,
    expected_opcode=SCENE11_PAIR_PRESET.comparison_opcode or 0x76,
)


def stage_scene11_load_game_save(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
) -> tuple[Path, Path]:
    return stage_single_load_game_save(
        args,
        writer,
        launch_path,
        lane_name="scene11-pair",
        default_source=default_source_save_path("S8741.LBA"),
    )


def drive_scene11_launch_startup(
    writer: JsonlWriter,
    pid: int,
    *,
    post_load_settle_delay_sec: float = 5.0,
    post_load_status_message: str = "waited for the sole staged save to settle before capturing the debugger snapshot lane",
    capture: WindowCapture | None = None,
    window_input: WindowInput | None = None,
) -> None:
    drive_single_save_load_game_startup(
        writer,
        pid,
        scene_label="Scene11",
        adeline_enter_delay_sec=SCENE11_ADELINE_ENTER_DELAY_SEC,
        startup_window_timeout_sec=SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
        post_load_settle_delay_sec=post_load_settle_delay_sec,
        post_load_status_message=post_load_status_message,
        capture=capture,
        window_input=window_input,
    )


def prepare_scene11_launch(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
    pid: int,
) -> None:
    stage_scene11_load_game_save(args, writer, launch_path)
    drive_scene11_launch_startup(writer, pid)


def cleanup_scene11_launch(args: argparse.Namespace, writer: JsonlWriter, launch_path: Path) -> None:
    cleanup_staged_load_game_save(args, writer, launch_path)


def object_record_address(object_index: int) -> int:
    return OBJECT_BASE + (object_index * OBJECT_STRIDE)


def ptr_life_field_address(object_index: int) -> int:
    return object_record_address(object_index) + PTR_LIFE_OFFSET


def offset_life_field_address(object_index: int) -> int:
    return object_record_address(object_index) + OFFSET_LIFE_OFFSET


def format_hex_u32(value: int | None) -> str | None:
    if value is None:
        return None
    return f"0x{value & 0xFFFFFFFF:08X}"


def format_hex_u16(value: int | None) -> str | None:
    if value is None:
        return None
    return f"0x{value & 0xFFFF:04X}"


def bytes_to_hex(data: bytes) -> str:
    return " ".join(f"{value:02X}" for value in data)


def aligned_dword_addresses(start_address: int, byte_count: int) -> tuple[int, ...]:
    if byte_count < 1:
        raise ValueError("byte_count must be at least 1")
    aligned_start = start_address & ~0x3
    aligned_end = (start_address + byte_count + 3) & ~0x3
    return tuple(range(aligned_start, aligned_end, 4))


def bytes_from_dwords(
    dwords: dict[int, int],
    *,
    start_address: int,
    byte_count: int,
) -> bytes:
    aligned_start = start_address & ~0x3
    raw = bytearray()
    for address in aligned_dword_addresses(start_address, byte_count):
        raw.extend(dwords[address].to_bytes(4, "little", signed=False))
    start_offset = start_address - aligned_start
    return bytes(raw[start_offset : start_offset + byte_count])


def read_byte_range_from_dwords(
    reader: Scene11SnapshotReader,
    *,
    start_address: int,
    byte_count: int,
) -> bytes:
    dwords, _ = reader.read_scalars(
        dword_addresses=aligned_dword_addresses(start_address, byte_count),
        word_addresses=tuple(),
    )
    expected_addresses = aligned_dword_addresses(start_address, byte_count)
    if any(address not in dwords for address in expected_addresses):
        return reader.read_bytes(start_address, byte_count)
    return bytes_from_dwords(
        dwords,
        start_address=start_address,
        byte_count=byte_count,
    )


def snapshot_window(
    reader: Scene11SnapshotReader,
    *,
    ptr_life: int,
    target_offset: int,
    window_before: int,
    window_after: int,
) -> tuple[int | None, PointerWindow]:
    start_offset = max(0, target_offset - window_before)
    cursor_index = target_offset - start_offset
    byte_count = cursor_index + 1 + window_after
    start_address = ptr_life + start_offset

    try:
        raw = read_byte_range_from_dwords(
            reader,
            start_address=start_address,
            byte_count=byte_count,
        )
    except DebuggerReadError as error:
        return None, PointerWindow(
            start=format_hex_u32(start_address) or "0x00000000",
            cursor_index=cursor_index,
            bytes_hex=None,
            error=str(error),
        )

    return raw[cursor_index], PointerWindow(
        start=format_hex_u32(start_address) or "0x00000000",
        cursor_index=cursor_index,
        bytes_hex=bytes_to_hex(raw),
    )


def collect_object_snapshot(
    reader: Scene11SnapshotReader,
    spec: Scene11ObjectSnapshotSpec,
    dwords: dict[int, int],
    words: dict[int, int],
    *,
    window_before: int,
    window_after: int,
) -> Scene11ObjectSnapshot:
    current_object = object_record_address(spec.object_index)
    ptr_life_field = ptr_life_field_address(spec.object_index)
    offset_life_field = offset_life_field_address(spec.object_index)
    ptr_life = dwords[ptr_life_field]
    offset_life = words[offset_life_field]

    if ptr_life == 0:
        return Scene11ObjectSnapshot(
            spec=spec,
            current_object=current_object,
            ptr_life_field=ptr_life_field,
            ptr_life=ptr_life,
            offset_life_field=offset_life_field,
            offset_life=offset_life,
            target_address=None,
            target_window=PointerWindow(
                start="0x00000000",
                cursor_index=max(0, min(spec.target_offset, window_before)),
                bytes_hex=None,
                error=f"PtrLife for object {spec.object_index} was null",
            ),
            target_byte=None,
        )

    target_byte, target_window = snapshot_window(
        reader,
        ptr_life=ptr_life,
        target_offset=spec.target_offset,
        window_before=window_before,
        window_after=window_after,
    )
    return Scene11ObjectSnapshot(
        spec=spec,
        current_object=current_object,
        ptr_life_field=ptr_life_field,
        ptr_life=ptr_life,
        offset_life_field=offset_life_field,
        offset_life=offset_life,
        target_address=ptr_life + spec.target_offset,
        target_window=target_window,
        target_byte=target_byte,
    )


def collect_scene11_debugger_snapshot(
    reader: Scene11SnapshotReader,
    *,
    window_before: int = WINDOW_BEFORE,
    window_after: int = WINDOW_AFTER,
) -> Scene11DebuggerSnapshot:
    dwords, words = reader.read_scalars(
        dword_addresses=(
            PTR_PRG_GLOBAL,
            ptr_life_field_address(PRIMARY_SNAPSHOT.object_index),
            ptr_life_field_address(COMPARISON_SNAPSHOT.object_index),
        ),
        word_addresses=(
            offset_life_field_address(PRIMARY_SNAPSHOT.object_index),
            offset_life_field_address(COMPARISON_SNAPSHOT.object_index),
        ),
    )
    return Scene11DebuggerSnapshot(
        ptr_prg=dwords[PTR_PRG_GLOBAL],
        primary=collect_object_snapshot(
            reader,
            PRIMARY_SNAPSHOT,
            dwords,
            words,
            window_before=window_before,
            window_after=window_after,
        ),
        comparison=collect_object_snapshot(
            reader,
            COMPARISON_SNAPSHOT,
            dwords,
            words,
            window_before=window_before,
            window_after=window_after,
        ),
    )


def determine_scene11_snapshot_verdict(snapshot: Scene11DebuggerSnapshot) -> tuple[str, str]:
    for object_snapshot in (snapshot.primary, snapshot.comparison):
        if object_snapshot.ptr_life == 0:
            return (
                f"scene11_{object_snapshot.spec.label}_ptr_life_missing",
                f"object {object_snapshot.spec.object_index} PtrLife was null after the Scene11 load snapshot",
            )
        if object_snapshot.target_byte is None:
            return (
                f"scene11_{object_snapshot.spec.label}_window_unavailable",
                f"could not read the object {object_snapshot.spec.object_index} target window at offset {object_snapshot.spec.target_offset}",
            )
        if object_snapshot.target_byte != object_snapshot.spec.expected_opcode:
            return (
                f"scene11_{object_snapshot.spec.label}_target_mismatch",
                f"object {object_snapshot.spec.object_index} byte at offset {object_snapshot.spec.target_offset} was 0x{object_snapshot.target_byte:02X}, expected 0x{object_snapshot.spec.expected_opcode:02X}",
            )

    return (
        "scene11_snapshot_complete",
        "captured debugger-owned Scene11 snapshot evidence for object 12 LM_DEFAULT and object 18 LM_END_SWITCH",
    )


def discover_scene11_runtime_candidates(
    reader: Scene11SnapshotReader,
    *,
    scan_object_limit: int = DISCOVERY_SCAN_OBJECT_LIMIT,
    scan_byte_limit: int = DISCOVERY_SCAN_BYTE_LIMIT,
    window_before: int = WINDOW_BEFORE,
    window_after: int = WINDOW_AFTER,
) -> tuple[Scene11RuntimeCandidate, ...]:
    dwords, words = reader.read_scalars(
        dword_addresses=tuple(ptr_life_field_address(i) for i in range(scan_object_limit)),
        word_addresses=tuple(offset_life_field_address(i) for i in range(scan_object_limit)),
    )

    candidates: list[Scene11RuntimeCandidate] = []
    for object_index in range(scan_object_limit):
        ptr_life_field = ptr_life_field_address(object_index)
        ptr_life = dwords[ptr_life_field]
        if ptr_life == 0:
            continue

        blob = read_byte_range_from_dwords(
            reader,
            start_address=ptr_life,
            byte_count=scan_byte_limit,
        )
        offset_life = words[offset_life_field_address(object_index)]
        for offset, opcode in enumerate(blob):
            if opcode not in DISCOVERY_OPCODES:
                continue
            start_offset = max(0, offset - window_before)
            cursor_index = offset - start_offset
            end_offset = min(len(blob), offset + window_after + 1)
            candidates.append(
                Scene11RuntimeCandidate(
                    object_index=object_index,
                    ptr_life=ptr_life,
                    offset_life=offset_life,
                    opcode=opcode,
                    opcode_offset=offset,
                    target_window=PointerWindow(
                        start=format_hex_u32(ptr_life + start_offset) or "0x00000000",
                        cursor_index=cursor_index,
                        bytes_hex=bytes_to_hex(blob[start_offset:end_offset]),
                    ),
                )
            )

    return tuple(candidates)


def summarize_scene11_runtime_mismatch(
    snapshot: Scene11DebuggerSnapshot,
    candidates: tuple[Scene11RuntimeCandidate, ...],
) -> tuple[str, str] | None:
    default_candidate = next((candidate for candidate in candidates if candidate.opcode == 0x74), None)
    end_switch_candidate = next((candidate for candidate in candidates if candidate.opcode == 0x76), None)
    if default_candidate is None and end_switch_candidate is None:
        return None

    problems: list[str] = []
    if snapshot.primary.ptr_life == 0:
        problems.append("canonical object 12 PtrLife was null")
    elif snapshot.primary.target_byte != snapshot.primary.spec.expected_opcode:
        problems.append(
            f"canonical object 12 byte at offset 38 was 0x{snapshot.primary.target_byte:02X}"
            if snapshot.primary.target_byte is not None
            else "canonical object 12 target window was unavailable"
        )
    if snapshot.comparison.ptr_life == 0:
        problems.append("canonical object 18 PtrLife was null")
    elif snapshot.comparison.target_byte != snapshot.comparison.spec.expected_opcode:
        problems.append(
            f"canonical object 18 byte at offset 84 was 0x{snapshot.comparison.target_byte:02X}"
            if snapshot.comparison.target_byte is not None
            else "canonical object 18 target window was unavailable"
        )

    discoveries: list[str] = []
    if default_candidate is not None:
        discoveries.append(
            f"live object {default_candidate.object_index} exposed LM_DEFAULT at offset {default_candidate.opcode_offset}"
        )
    if end_switch_candidate is not None:
        discoveries.append(
            f"live object {end_switch_candidate.object_index} exposed LM_END_SWITCH at offset {end_switch_candidate.opcode_offset}"
        )

    return (
        "scene11_static_runtime_mismatch",
        "; ".join([*problems, *discoveries]),
    )


def write_memory_snapshot_event(
    writer: JsonlWriter,
    *,
    snapshot_name: str,
    debugger: str,
    address: int,
    object_index: int | None = None,
    current_object: int | None = None,
    relative_to: str | None = None,
    relative_offset: int | None = None,
    value_u16: int | None = None,
    value_u32: int | None = None,
    window: PointerWindow | None = None,
) -> str:
    event_kwargs = {
        "snapshot_name": snapshot_name,
        "debugger": debugger,
        "address": format_hex_u32(address) or "0x00000000",
        "object_index": object_index,
        "current_object": format_hex_u32(current_object),
        "relative_to": relative_to,
        "relative_offset": relative_offset,
        "value_hex": format_hex_u32(value_u32)
        if value_u32 is not None
        else format_hex_u16(value_u16),
        "value_u16": value_u16,
        "value_u32": value_u32,
    }
    if window is not None:
        event_kwargs["window"] = window
    return writer.write_event(PersistedMemorySnapshotEvent(**event_kwargs))


def capture_snapshot_poi(
    writer: JsonlWriter,
    capture: WindowCapture,
    *,
    pid: int,
    poi: str,
    event_id: str,
    object_index: int,
    offset_value: int,
) -> tuple[str | None, str | None]:
    filename = f"{event_id}__{poi}__obj{object_index}__off{offset_value:03d}.png"
    absolute_path = writer.screenshot_dir / filename
    try:
        window = capture.capture(pid, absolute_path)
    except CaptureError as error:
        writer.write_event(
            PersistedScreenshotErrorEvent(
                poi=poi,
                reason=str(error),
                capture_status="failed",
            ),
            event_id=event_id,
        )
        return None, str(error)

    relative_path = str(absolute_path.relative_to(REPO_ROOT)).replace("\\", "/")
    writer.write_event(
        PersistedScreenshotEvent(
            poi=poi,
            screenshot_path=relative_path,
            source_window_title=window.title,
            capture_status="captured",
        ),
        event_id=event_id,
    )
    return relative_path, None


def run_scene11_debugger_snapshot(
    args: argparse.Namespace,
    writer: JsonlWriter,
    pid: int,
) -> tuple[int, str | None]:
    capture = WindowCapture()
    screenshot_error: str | None = None

    writer.write_event(
        PersistedStatusEvent(
            phase="capturing_snapshot",
            message="capturing Scene11 through the debugger snapshot lane",
            pid=pid,
        )
    )

    loaded_scene_event_id = writer.next_event_id()
    _, loaded_scene_error = capture_snapshot_poi(
        writer,
        capture,
        pid=pid,
        poi="loaded_scene",
        event_id=loaded_scene_event_id,
        object_index=PRIMARY_SNAPSHOT.object_index,
        offset_value=PRIMARY_SNAPSHOT.target_offset,
    )
    if loaded_scene_error is not None:
        screenshot_error = f"required screenshot failed for loaded_scene: {loaded_scene_error}"

    cdb_path = resolve_cdb_path(args.cdb_path)
    writer.write_event(
        PersistedStatusEvent(
            message=f"attached cdb-agent snapshot backend via {cdb_path}",
            pid=pid,
        )
    )
    snapshot = collect_scene11_debugger_snapshot(
        CdbMemoryReader(cdb_path, pid),
        window_before=args.window_before,
        window_after=args.window_after,
    )

    write_memory_snapshot_event(
        writer,
        snapshot_name="global_ptr_prg",
        debugger="cdb-agent",
        address=PTR_PRG_GLOBAL,
        value_u32=snapshot.ptr_prg,
    )
    write_memory_snapshot_event(
        writer,
        snapshot_name="primary_ptr_life",
        debugger="cdb-agent",
        address=snapshot.primary.ptr_life_field,
        object_index=snapshot.primary.spec.object_index,
        current_object=snapshot.primary.current_object,
        value_u32=snapshot.primary.ptr_life,
    )
    write_memory_snapshot_event(
        writer,
        snapshot_name="primary_offset_life",
        debugger="cdb-agent",
        address=snapshot.primary.offset_life_field,
        object_index=snapshot.primary.spec.object_index,
        current_object=snapshot.primary.current_object,
        value_u16=snapshot.primary.offset_life,
    )
    primary_window_event_id = write_memory_snapshot_event(
        writer,
        snapshot_name="primary_target_window",
        debugger="cdb-agent",
        address=snapshot.primary.target_address or 0,
        object_index=snapshot.primary.spec.object_index,
        current_object=snapshot.primary.current_object,
        relative_to="ptr_life",
        relative_offset=snapshot.primary.spec.target_offset,
        window=snapshot.primary.target_window,
    )

    write_memory_snapshot_event(
        writer,
        snapshot_name="comparison_ptr_life",
        debugger="cdb-agent",
        address=snapshot.comparison.ptr_life_field,
        object_index=snapshot.comparison.spec.object_index,
        current_object=snapshot.comparison.current_object,
        value_u32=snapshot.comparison.ptr_life,
    )
    write_memory_snapshot_event(
        writer,
        snapshot_name="comparison_offset_life",
        debugger="cdb-agent",
        address=snapshot.comparison.offset_life_field,
        object_index=snapshot.comparison.spec.object_index,
        current_object=snapshot.comparison.current_object,
        value_u16=snapshot.comparison.offset_life,
    )
    comparison_window_event_id = write_memory_snapshot_event(
        writer,
        snapshot_name="comparison_target_window",
        debugger="cdb-agent",
        address=snapshot.comparison.target_address or 0,
        object_index=snapshot.comparison.spec.object_index,
        current_object=snapshot.comparison.current_object,
        relative_to="ptr_life",
        relative_offset=snapshot.comparison.spec.target_offset,
        window=snapshot.comparison.target_window,
    )

    result, reason = determine_scene11_snapshot_verdict(snapshot)
    if result != "scene11_snapshot_complete":
        discovery_candidates = discover_scene11_runtime_candidates(
            CdbMemoryReader(cdb_path, pid),
            window_before=args.window_before,
            window_after=args.window_after,
        )
        if discovery_candidates:
            writer.write_event(
                PersistedStatusEvent(
                    message=(
                        "scene11 runtime discovery found "
                        + ", ".join(
                            f"{DISCOVERY_OPCODES[candidate.opcode]} on object {candidate.object_index} at offset {candidate.opcode_offset}"
                            for candidate in discovery_candidates
                        )
                    ),
                    pid=pid,
                )
            )
        for candidate in discovery_candidates:
            write_memory_snapshot_event(
                writer,
                snapshot_name=f"discovery_{DISCOVERY_OPCODES[candidate.opcode].lower()}_window",
                debugger="cdb-agent",
                address=candidate.ptr_life + candidate.opcode_offset,
                object_index=candidate.object_index,
                current_object=object_record_address(candidate.object_index),
                relative_to="ptr_life",
                relative_offset=candidate.opcode_offset,
                window=candidate.target_window,
            )
        mismatch = summarize_scene11_runtime_mismatch(snapshot, discovery_candidates)
        if mismatch is not None:
            result, reason = mismatch

    verdict_event_id = writer.next_event_id()
    _, final_screenshot_error = capture_snapshot_poi(
        writer,
        capture,
        pid=pid,
        poi="final_verdict",
        event_id=verdict_event_id,
        object_index=PRIMARY_SNAPSHOT.object_index,
        offset_value=PRIMARY_SNAPSHOT.target_offset,
    )
    if final_screenshot_error is not None:
        screenshot_error = f"required screenshot failed for final_verdict: {final_screenshot_error}"

    if screenshot_error is not None:
        result = "screenshot_capture_failed"
        reason = screenshot_error

    writer.write_event(
        PersistedVerdictEvent(
            phase="completed",
            matched_fingerprint=False,
            required_screenshots_complete=screenshot_error is None,
            result=result,
            reason=reason,
            primary_event_id=primary_window_event_id,
            comparison_event_id=comparison_window_event_id,
        ),
        event_id=verdict_event_id,
    )
    writer.write_event(
        PersistedStatusEvent(
            phase="completed",
            message=TRACE_COMPLETE_STATUS_MESSAGE if result == "scene11_snapshot_complete" else TRACE_FINISHED_STATUS_MESSAGE,
            pid=pid,
        )
    )

    return (0, None) if result == "scene11_snapshot_complete" else (1, reason)


SCENE_SPEC = StructuredSceneSpec(
    preset=SCENE11_PAIR_PRESET,
    snapshot_runner=run_scene11_debugger_snapshot,
    prepare_launch=prepare_scene11_launch,
    cleanup_launch=cleanup_scene11_launch,
    launch_strategy="native_launch_then_attach",
    runtime_backend="debugger_snapshot",
    requires_callsite_map=False,
    helper_capture_enabled=False,
)
