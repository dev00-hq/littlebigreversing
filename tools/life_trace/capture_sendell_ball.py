from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

from life_trace_debugger import CdbMemoryReader, DebuggerReadError, resolve_cdb_path
from life_trace_shared import (
    DEFAULT_GAME_EXE,
    DEFAULT_RUN_ROOT,
    JsonlWriter,
    LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC,
    PersistedErrorEvent,
    PersistedMemorySnapshotEvent,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PointerWindow,
    SCENE11_ADELINE_ENTER_DELAY_SEC,
    SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
)
from life_trace_windows import CaptureError, InputError, WindowCapture, WindowInput
from scenes.load_game import (
    cleanup_staged_load_game_save,
    default_source_save_path,
    drive_single_save_load_game_startup,
    stage_single_load_game_save,
)


PTR_PRG_GLOBAL = 0x004976D0
TYPE_ANSWER_GLOBAL = 0x004976D4
VALUE_GLOBAL = 0x00497D44
MAGIC_LEVEL_GLOBAL = 0x0049A0A4
MAGIC_POINT_GLOBAL = 0x0049A0A5
LIST_VAR_GAME_GLOBAL = 0x00499E98
TAB_INV_GLOBAL = 0x004BA46C
SENDLL_FLAG_INDEX = 3
LIST_VAR_GAME_SLOT_SIZE = 2
TAB_INV_SLOT_SIZE = 0x16
TAB_INV_IDOBJ3D_OFFSET = 0x10
DEFAULT_SAVE_NAME = "ball of sendell.LBA"
DEFAULT_PTR_WINDOW_COUNT = 16
DEFAULT_AFTER_CAST_DELAY_SEC = 0.8
DEFAULT_DIALOG1_DELAY_SEC = 2.6
DEFAULT_DIALOG2_DELAY_SEC = 0.6
DEFAULT_POST_DIALOG_DELAY_SEC = 1.0
DEFAULT_MENU_OPEN_DELAY_SEC = 0.5
DEFAULT_TERMINATE_GRACE_SEC = 3.0
TASKKILL_NOT_FOUND_MARKERS = (
    "not found",
    "no se encontr",
    "no tasks are running",
    "no hay tareas en ejec",
)
BASE_FLOW_CHECKPOINTS = (
    "loaded_pre_cast",
    "after_f_cast",
    "dialog_1",
    "dialog_2",
    "post_dialog_room",
)
MENU_CHECKPOINTS = (
    "pre_behavior",
    "pre_inventory",
    "post_behavior",
    "post_inventory",
)
SUMMARY_CHECKPOINTS = BASE_FLOW_CHECKPOINTS + MENU_CHECKPOINTS
CAPTURED_STATE_FIELDS = [
    "PtrPrg",
    "TypeAnswer",
    "Value",
    "PtrPrgWindow",
    "MagicLevel",
    "MagicPoint",
    "SendellInventoryValue",
    "InventoryModelId",
    "ScreenshotArtifacts",
]
MISSING_STATE_FIELDS = [
    "CurrentDial",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Stage the canonical Sendell's Ball save, drive the original game through "
            "the room event, and record checkpoint screenshots plus one-shot cdb-agent snapshots."
        )
    )
    parser.add_argument("--launch", default=str(DEFAULT_GAME_EXE), help="Path to LBA2.EXE.")
    parser.add_argument(
        "--launch-save",
        default=str(default_source_save_path(DEFAULT_SAVE_NAME)),
        help="Source save to stage into SAVE before launch.",
    )
    parser.add_argument("--run-root", default=str(DEFAULT_RUN_ROOT), help="Run bundle root directory.")
    parser.add_argument("--run-id", help="Optional explicit run id.")
    parser.add_argument("--cdb-path", help="Optional explicit path to cdb.exe.")
    parser.add_argument(
        "--cdb-timeout-sec",
        type=float,
        default=60.0,
        help="Timeout for one-shot cdb-agent reads.",
    )
    parser.add_argument(
        "--ptr-window-count",
        type=int,
        default=DEFAULT_PTR_WINDOW_COUNT,
        help="Number of bytes to read at poi(PtrPrg) when nonzero.",
    )
    parser.add_argument(
        "--adeline-enter-delay-sec",
        type=float,
        default=SCENE11_ADELINE_ENTER_DELAY_SEC,
        help="Delay before dismissing the Adeline splash.",
    )
    parser.add_argument(
        "--startup-window-timeout-sec",
        type=float,
        default=SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
        help="Window wait timeout during startup automation.",
    )
    parser.add_argument(
        "--post-load-settle-sec",
        type=float,
        default=LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC,
        help="Extra settle time after the staged save loads.",
    )
    parser.add_argument(
        "--after-cast-delay-sec",
        type=float,
        default=DEFAULT_AFTER_CAST_DELAY_SEC,
        help="Delay between sending F and capturing the immediate post-cast checkpoint.",
    )
    parser.add_argument(
        "--dialog1-delay-sec",
        type=float,
        default=DEFAULT_DIALOG1_DELAY_SEC,
        help="Additional delay before the first dialog checkpoint.",
    )
    parser.add_argument(
        "--dialog2-delay-sec",
        type=float,
        default=DEFAULT_DIALOG2_DELAY_SEC,
        help="Delay after the first Enter before the second dialog checkpoint.",
    )
    parser.add_argument(
        "--post-dialog-delay-sec",
        type=float,
        default=DEFAULT_POST_DIALOG_DELAY_SEC,
        help="Delay after dismissing the second dialog before the final room checkpoint.",
    )
    parser.add_argument(
        "--menu",
        choices=("behavior", "inventory"),
        help="Optional menu to capture as an extra screenshot lane.",
    )
    parser.add_argument(
        "--menu-phase",
        choices=("pre", "post"),
        help="Capture the optional menu before the cast or after the final dialog.",
    )
    parser.add_argument(
        "--menu-open-delay-sec",
        type=float,
        default=DEFAULT_MENU_OPEN_DELAY_SEC,
        help="Delay after sending the menu hotkey before capturing the menu checkpoint.",
    )
    parser.add_argument(
        "--keep-process",
        action="store_true",
        help="Leave LBA2.EXE running after the capture completes.",
    )
    args = parser.parse_args()
    if (args.menu is None) != (args.menu_phase is None):
        parser.error("--menu and --menu-phase must be passed together")
    return args


def format_hex_u32(value: int) -> str:
    return f"0x{value & 0xFFFFFFFF:08X}"


def bytes_to_hex(data: bytes) -> str:
    return " ".join(f"{value:02X}" for value in data)


def write_status(writer: JsonlWriter, message: str, *, pid: int | None = None) -> None:
    writer.write_event(PersistedStatusEvent(message=message, pid=pid))


def capture_variant(menu_name: str | None, menu_phase: str | None) -> str:
    if menu_name is None and menu_phase is None:
        return "full_flow"
    return f"{menu_phase}_{menu_name}"


def pointer_window_payload(
    *,
    start: str,
    cursor_index: int,
    bytes_hex: str | None,
    error: str | None = None,
) -> dict[str, object]:
    return {
        "start": start,
        "cursor_index": cursor_index,
        "bytes_hex": bytes_hex,
        "error": error,
    }


def checkpoint_signature(checkpoint: dict[str, object] | None) -> dict[str, object] | None:
    if checkpoint is None:
        return None
    ptr_prg_window = checkpoint["ptr_prg_window"]
    assert isinstance(ptr_prg_window, dict)
    return {
        "type_answer_u32": checkpoint["type_answer_u32"],
        "value_u32": checkpoint["value_u32"],
        "ptr_prg_window_bytes_hex": ptr_prg_window["bytes_hex"],
    }


def checkpoint_direct_state(checkpoint: dict[str, object] | None) -> dict[str, object] | None:
    if checkpoint is None:
        return None
    direct_state = checkpoint["direct_state"]
    assert isinstance(direct_state, dict)
    return {
        "magic_level_u8": direct_state["magic_level_u8"],
        "magic_point_u8": direct_state["magic_point_u8"],
        "sendell_inventory_value_s16": direct_state["sendell_inventory_value_s16"],
        "inventory_model_id_s16": direct_state["inventory_model_id_s16"],
    }


def build_state_delta(
    pre_value: int | None,
    post_value: int | None,
) -> dict[str, object]:
    return {
        "before": pre_value,
        "after": post_value,
        "changed": pre_value != post_value,
    }


def parse_u8(data: bytes) -> int:
    if len(data) != 1:
        raise ValueError(f"expected exactly one byte, got {len(data)}")
    return data[0]


def parse_s16le(data: bytes) -> int:
    if len(data) != 2:
        raise ValueError(f"expected exactly two bytes, got {len(data)}")
    return int.from_bytes(data, byteorder="little", signed=True)


def build_sendell_run_summary(
    *,
    writer: JsonlWriter,
    launch_save: Path,
    capture_variant_name: str,
    checkpoint_order: list[str],
    checkpoint_captures: dict[str, dict[str, object]],
) -> dict[str, object]:
    required_checkpoints_by_variant = {
        "full_flow": list(BASE_FLOW_CHECKPOINTS),
        "pre_behavior": ["loaded_pre_cast", "pre_behavior"],
        "pre_inventory": ["loaded_pre_cast", "pre_inventory"],
        "post_behavior": [*BASE_FLOW_CHECKPOINTS, "post_behavior"],
        "post_inventory": [*BASE_FLOW_CHECKPOINTS, "post_inventory"],
    }
    required_checkpoints = required_checkpoints_by_variant[capture_variant_name]
    missing_checkpoints = [name for name in required_checkpoints if name not in checkpoint_captures]

    loaded_pre_cast = checkpoint_captures.get("loaded_pre_cast")
    dialog_1 = checkpoint_captures.get("dialog_1")
    dialog_2 = checkpoint_captures.get("dialog_2")
    post_dialog_room = checkpoint_captures.get("post_dialog_room")

    dialog_transition_seen = (
        dialog_1 is not None
        and dialog_2 is not None
        and dialog_1["type_answer_u32"] == 4
        and dialog_2["type_answer_u32"] == 4
        and dialog_1["value_u32"] == 11
        and dialog_2["value_u32"] == 11
    )
    post_dialog_transition_seen = (
        loaded_pre_cast is not None
        and post_dialog_room is not None
        and (
            loaded_pre_cast["type_answer_u32"] != post_dialog_room["type_answer_u32"]
            or loaded_pre_cast["value_u32"] != post_dialog_room["value_u32"]
            or checkpoint_signature(loaded_pre_cast)["ptr_prg_window_bytes_hex"] != checkpoint_signature(post_dialog_room)["ptr_prg_window_bytes_hex"]
        )
    )
    pre_cast_state = checkpoint_direct_state(loaded_pre_cast)
    post_dialog_state = checkpoint_direct_state(post_dialog_room)
    story_state_transition = {
        "magic_level": build_state_delta(
            None if pre_cast_state is None else pre_cast_state["magic_level_u8"],
            None if post_dialog_state is None else post_dialog_state["magic_level_u8"],
        ),
        "magic_point": build_state_delta(
            None if pre_cast_state is None else pre_cast_state["magic_point_u8"],
            None if post_dialog_state is None else post_dialog_state["magic_point_u8"],
        ),
        "sendell_inventory_value": build_state_delta(
            None if pre_cast_state is None else pre_cast_state["sendell_inventory_value_s16"],
            None if post_dialog_state is None else post_dialog_state["sendell_inventory_value_s16"],
        ),
        "inventory_model_id": build_state_delta(
            None if pre_cast_state is None else pre_cast_state["inventory_model_id_s16"],
            None if post_dialog_state is None else post_dialog_state["inventory_model_id_s16"],
        ),
    }
    direct_story_state_transition_seen = any(
        transition["changed"] for transition in story_state_transition.values()
    )

    if capture_variant_name == "full_flow":
        if (
            not missing_checkpoints
            and dialog_transition_seen
            and post_dialog_transition_seen
            and direct_story_state_transition_seen
        ):
            verdict_result = "sendell_story_state_transition_observed"
            verdict_reason = (
                "captured the full room-36 lightning/dialog lane with stable dialog-state "
                "signatures and direct story-state deltas"
            )
        else:
            verdict_result = "sendell_flow_incomplete"
            verdict_reason = (
                "missing one or more full-flow checkpoints, the expected dialog/post-dialog "
                "signature transition, or a direct story-state delta"
            )
    else:
        if not missing_checkpoints:
            verdict_result = "sendell_menu_capture_complete"
            verdict_reason = "captured the requested held-key menu lane with the required checkpoints present"
        else:
            verdict_result = "sendell_menu_capture_incomplete"
            verdict_reason = "missing one or more required checkpoints for the requested menu lane"

    checkpoints_payload: dict[str, dict[str, object]] = {}
    for checkpoint_name in SUMMARY_CHECKPOINTS:
        checkpoint = checkpoint_captures.get(checkpoint_name)
        if checkpoint is None:
            checkpoints_payload[checkpoint_name] = {
                "present": False,
                "screenshot_path": None,
                "ptr_prg_value_hex": None,
                "ptr_prg_value_u32": None,
                "ptr_prg_window": None,
                "type_answer_u32": None,
                "value_u32": None,
                "direct_state": None,
                "event_ids": None,
            }
            continue
        checkpoints_payload[checkpoint_name] = {
            "present": True,
            "screenshot_path": checkpoint["screenshot_path"],
            "source_window_title": checkpoint["source_window_title"],
            "ptr_prg_value_hex": checkpoint["ptr_prg_value_hex"],
            "ptr_prg_value_u32": checkpoint["ptr_prg_value_u32"],
            "ptr_prg_window": checkpoint["ptr_prg_window"],
            "type_answer_u32": checkpoint["type_answer_u32"],
            "value_u32": checkpoint["value_u32"],
            "direct_state": checkpoint["direct_state"],
            "event_ids": checkpoint["event_ids"],
        }

    return {
        "schema_version": "sendell-run-summary-v1",
        "run_id": writer.run_id,
        "mode": "sendell-ball-room",
        "bundle_root": str(writer.bundle_root),
        "launch_save": str(launch_save),
        "debugger": "cdb-agent",
        "capture_variant": capture_variant_name,
        "checkpoint_order": checkpoint_order,
        "checkpoints": checkpoints_payload,
        "transitions": {
            "pre_cast_signature": checkpoint_signature(loaded_pre_cast),
            "dialog_signature": {
                "dialog_1": checkpoint_signature(dialog_1),
                "dialog_2": checkpoint_signature(dialog_2),
                "stable": dialog_transition_seen,
            },
            "post_dialog_signature": checkpoint_signature(post_dialog_room),
            "dialog_transition_seen": dialog_transition_seen,
            "post_dialog_transition_seen": post_dialog_transition_seen,
            "story_state_transition": story_state_transition,
            "direct_story_state_transition_seen": direct_story_state_transition_seen,
        },
        "captured_state_fields": CAPTURED_STATE_FIELDS,
        "missing_state_fields": MISSING_STATE_FIELDS,
        "verdict": {
            "result": verdict_result,
            "reason": verdict_reason,
            "missing_checkpoints": missing_checkpoints,
        },
    }


def write_sendell_run_summary(
    writer: JsonlWriter,
    *,
    launch_save: Path,
    capture_variant_name: str,
    checkpoint_order: list[str],
    checkpoint_captures: dict[str, dict[str, object]],
) -> Path:
    output_path = writer.bundle_root / "sendell_summary.json"
    summary = build_sendell_run_summary(
        writer=writer,
        launch_save=launch_save,
        capture_variant_name=capture_variant_name,
        checkpoint_order=checkpoint_order,
        checkpoint_captures=checkpoint_captures,
    )
    output_path.write_text(
        json.dumps(summary, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    writer.register_artifact("sendell_summary", output_path.name)
    return output_path


def preflight_owned_launch_processes(writer: JsonlWriter, process_names: tuple[str, ...]) -> None:
    seen: set[str] = set()
    for process_name in process_names:
        normalized = process_name.strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        completed = subprocess.run(
            ["taskkill", "/IM", normalized, "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode == 0:
            write_status(writer, f"preflight killed existing {normalized}")
            continue
        detail = f"{completed.stdout or ''}\n{completed.stderr or ''}".strip().lower()
        if any(marker in detail for marker in TASKKILL_NOT_FOUND_MARKERS):
            continue
        raise RuntimeError(
            f"preflight taskkill failed for {normalized} ({completed.returncode}): "
            f"{(completed.stderr or completed.stdout).strip() or '<no output>'}"
        )


def capture_checkpoint_screenshot(
    writer: JsonlWriter,
    capture: WindowCapture,
    pid: int,
    checkpoint_name: str,
) -> dict[str, object]:
    output_path = writer.screenshot_dir / f"{checkpoint_name}.png"
    try:
        window = capture.capture(pid, output_path)
    except CaptureError as error:
        writer.write_event(
            PersistedScreenshotErrorEvent(
                poi=checkpoint_name,
                reason=str(error),
                capture_status="error",
            )
        )
        raise RuntimeError(f"failed to capture {checkpoint_name} screenshot: {error}") from error

    relative_path = f"screenshots/{output_path.name}"
    writer.register_artifact(f"screenshot_{checkpoint_name}", relative_path)
    screenshot_event_id = writer.write_event(
        PersistedScreenshotEvent(
            poi=checkpoint_name,
            screenshot_path=relative_path,
            source_window_title=window.title,
            capture_status="ok",
        )
    )
    return {
        "screenshot_path": relative_path,
        "source_window_title": window.title,
        "event_ids": {
            "screenshot": screenshot_event_id,
        },
    }


def capture_checkpoint_debugger(
    writer: JsonlWriter,
    reader: CdbMemoryReader,
    checkpoint_name: str,
    *,
    ptr_window_count: int,
) -> dict[str, object]:
    try:
        dwords, _ = reader.read_scalars(
            dword_addresses=(PTR_PRG_GLOBAL, TYPE_ANSWER_GLOBAL, VALUE_GLOBAL),
            word_addresses=(),
        )
    except DebuggerReadError as error:
        raise RuntimeError(f"failed to read debugger scalars for {checkpoint_name}: {error}") from error

    ptr_prg = dwords[PTR_PRG_GLOBAL]
    type_answer = dwords[TYPE_ANSWER_GLOBAL]
    value = dwords[VALUE_GLOBAL]
    magic_state_bytes = reader.read_bytes(MAGIC_LEVEL_GLOBAL, 2)
    magic_level = parse_u8(magic_state_bytes[0:1])
    magic_point = parse_u8(magic_state_bytes[1:2])
    sendell_inventory_value_address = LIST_VAR_GAME_GLOBAL + (SENDLL_FLAG_INDEX * LIST_VAR_GAME_SLOT_SIZE)
    sendell_inventory_value = parse_s16le(reader.read_bytes(sendell_inventory_value_address, 2))
    inventory_model_id_address = (
        TAB_INV_GLOBAL
        + (SENDLL_FLAG_INDEX * TAB_INV_SLOT_SIZE)
        + TAB_INV_IDOBJ3D_OFFSET
    )
    inventory_model_id = parse_s16le(reader.read_bytes(inventory_model_id_address, 2))

    ptr_prg_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_ptr_prg",
            debugger="cdb-agent",
            address=format_hex_u32(PTR_PRG_GLOBAL),
            value_hex=format_hex_u32(ptr_prg),
            value_u32=ptr_prg,
        )
    )
    type_answer_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_type_answer",
            debugger="cdb-agent",
            address=format_hex_u32(TYPE_ANSWER_GLOBAL),
            value_hex=format_hex_u32(type_answer),
            value_u32=type_answer,
        )
    )
    value_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_value",
            debugger="cdb-agent",
            address=format_hex_u32(VALUE_GLOBAL),
            value_hex=format_hex_u32(value),
            value_u32=value,
        )
    )
    magic_level_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_magic_level",
            debugger="cdb-agent",
            address=format_hex_u32(MAGIC_LEVEL_GLOBAL),
            value_hex=format_hex_u32(magic_level),
            value_u32=magic_level,
        )
    )
    magic_point_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_magic_point",
            debugger="cdb-agent",
            address=format_hex_u32(MAGIC_POINT_GLOBAL),
            value_hex=format_hex_u32(magic_point),
            value_u32=magic_point,
        )
    )
    sendell_inventory_value_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_sendell_inventory_value",
            debugger="cdb-agent",
            address=format_hex_u32(sendell_inventory_value_address),
            value_hex=format_hex_u32(sendell_inventory_value),
            value_u32=sendell_inventory_value,
        )
    )
    inventory_model_id_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_inventory_model_id",
            debugger="cdb-agent",
            address=format_hex_u32(inventory_model_id_address),
            value_hex=format_hex_u32(inventory_model_id),
            value_u32=inventory_model_id,
        )
    )
    direct_state = {
        "magic_level_u8": magic_level,
        "magic_point_u8": magic_point,
        "sendell_inventory_value_s16": sendell_inventory_value,
        "inventory_model_id_s16": inventory_model_id,
    }

    if ptr_prg == 0:
        ptr_prg_window_event_id = writer.write_event(
            PersistedMemorySnapshotEvent(
                snapshot_name=f"{checkpoint_name}_ptr_prg_window",
                debugger="cdb-agent",
                address=format_hex_u32(0),
                relative_to="ptr_prg",
                window=PointerWindow(
                    start=format_hex_u32(0),
                    cursor_index=0,
                    bytes_hex=None,
                    error="PtrPrg was null",
                ),
            )
        )
        return {
            "ptr_prg_value_hex": format_hex_u32(ptr_prg),
            "ptr_prg_value_u32": ptr_prg,
            "type_answer_u32": type_answer,
            "value_u32": value,
            "direct_state": direct_state,
            "ptr_prg_window": pointer_window_payload(
                start=format_hex_u32(0),
                cursor_index=0,
                bytes_hex=None,
                error="PtrPrg was null",
            ),
            "event_ids": {
                "ptr_prg": ptr_prg_event_id,
                "type_answer": type_answer_event_id,
                "value": value_event_id,
                "magic_level": magic_level_event_id,
                "magic_point": magic_point_event_id,
                "sendell_inventory_value": sendell_inventory_value_event_id,
                "inventory_model_id": inventory_model_id_event_id,
                "ptr_prg_window": ptr_prg_window_event_id,
            },
        }

    try:
        window_bytes = reader.read_bytes(ptr_prg, ptr_window_count)
    except DebuggerReadError as error:
        writer.write_event(
            PersistedMemorySnapshotEvent(
                snapshot_name=f"{checkpoint_name}_ptr_prg_window",
                debugger="cdb-agent",
                address=format_hex_u32(ptr_prg),
                relative_to="ptr_prg",
                window=PointerWindow(
                    start=format_hex_u32(ptr_prg),
                    cursor_index=0,
                    bytes_hex=None,
                    error=str(error),
                ),
            )
        )
        raise RuntimeError(f"failed to read PtrPrg window for {checkpoint_name}: {error}") from error

    ptr_prg_window_event_id = writer.write_event(
        PersistedMemorySnapshotEvent(
            snapshot_name=f"{checkpoint_name}_ptr_prg_window",
            debugger="cdb-agent",
            address=format_hex_u32(ptr_prg),
            relative_to="ptr_prg",
            window=PointerWindow(
                start=format_hex_u32(ptr_prg),
                cursor_index=0,
                bytes_hex=bytes_to_hex(window_bytes),
            ),
        )
    )
    return {
        "ptr_prg_value_hex": format_hex_u32(ptr_prg),
        "ptr_prg_value_u32": ptr_prg,
        "type_answer_u32": type_answer,
        "value_u32": value,
        "direct_state": direct_state,
        "ptr_prg_window": pointer_window_payload(
            start=format_hex_u32(ptr_prg),
            cursor_index=0,
            bytes_hex=bytes_to_hex(window_bytes),
        ),
        "event_ids": {
            "ptr_prg": ptr_prg_event_id,
            "type_answer": type_answer_event_id,
            "value": value_event_id,
            "magic_level": magic_level_event_id,
            "magic_point": magic_point_event_id,
            "sendell_inventory_value": sendell_inventory_value_event_id,
            "inventory_model_id": inventory_model_id_event_id,
            "ptr_prg_window": ptr_prg_window_event_id,
        },
    }


def capture_checkpoint(
    writer: JsonlWriter,
    capture: WindowCapture,
    reader: CdbMemoryReader,
    pid: int,
    checkpoint_name: str,
    *,
    ptr_window_count: int,
) -> dict[str, object]:
    write_status(writer, f"capturing checkpoint {checkpoint_name}", pid=pid)
    screenshot_capture = capture_checkpoint_screenshot(writer, capture, pid, checkpoint_name)
    debugger_capture = capture_checkpoint_debugger(
        writer,
        reader,
        checkpoint_name,
        ptr_window_count=ptr_window_count,
    )
    return {
        "checkpoint_name": checkpoint_name,
        "screenshot_path": screenshot_capture["screenshot_path"],
        "source_window_title": screenshot_capture["source_window_title"],
        "ptr_prg_value_hex": debugger_capture["ptr_prg_value_hex"],
        "ptr_prg_value_u32": debugger_capture["ptr_prg_value_u32"],
        "type_answer_u32": debugger_capture["type_answer_u32"],
        "value_u32": debugger_capture["value_u32"],
        "direct_state": debugger_capture["direct_state"],
        "ptr_prg_window": debugger_capture["ptr_prg_window"],
        "event_ids": {
            **screenshot_capture["event_ids"],
            **debugger_capture["event_ids"],
        },
    }


def send_virtual_key(
    writer: JsonlWriter,
    capture: WindowCapture,
    window_input: WindowInput,
    pid: int,
    virtual_key: int,
    action_name: str,
) -> None:
    try:
        window = capture.wait_for_window(pid, timeout_sec=5.0)
        window_input.send_virtual_key(window.hwnd, virtual_key)
    except (CaptureError, InputError) as error:
        raise RuntimeError(f"failed to send {action_name}: {error}") from error
    write_status(writer, f"sent {action_name}", pid=pid)


def capture_checkpoint_with_held_key(
    writer: JsonlWriter,
    capture: WindowCapture,
    window_input: WindowInput,
    reader: CdbMemoryReader,
    pid: int,
    *,
    virtual_key: int,
    action_name: str,
    checkpoint_name: str,
    ptr_window_count: int,
    key_open_delay_sec: float,
) -> dict[str, object]:
    try:
        window = capture.wait_for_window(pid, timeout_sec=5.0)
        window_input.key_down(window.hwnd, virtual_key)
        write_status(writer, f"held {action_name}", pid=pid)
        time.sleep(key_open_delay_sec)
        return capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            checkpoint_name,
            ptr_window_count=ptr_window_count,
        )
    except (CaptureError, InputError) as error:
        raise RuntimeError(f"failed to capture {checkpoint_name} with held key: {error}") from error
    finally:
        window_input.key_up(virtual_key)


def menu_virtual_key(menu_name: str) -> int:
    if menu_name == "behavior":
        return 0xA2
    if menu_name == "inventory":
        return 0xA0
    raise ValueError(f"unsupported menu name: {menu_name}")


def terminate_process(writer: JsonlWriter, launched_process: subprocess.Popen[str], *, pid: int) -> None:
    if launched_process.poll() is not None:
        return
    launched_process.terminate()
    deadline = time.monotonic() + DEFAULT_TERMINATE_GRACE_SEC
    while time.monotonic() < deadline:
        if launched_process.poll() is not None:
            write_status(writer, "terminated launched LBA2.EXE", pid=pid)
            return
        time.sleep(0.1)
    launched_process.kill()
    launched_process.wait(timeout=5.0)
    write_status(writer, "killed launched LBA2.EXE after terminate timeout", pid=pid)


def main() -> int:
    args = parse_args()
    launch_path = Path(args.launch).resolve()
    if not launch_path.exists():
        raise RuntimeError(f"launch path does not exist: {launch_path}")

    staged_args = argparse.Namespace(launch_save=args.launch_save, staged_load_game_save_path=None)
    launch_save_path = Path(args.launch_save).resolve()
    writer = JsonlWriter(
        Path(args.run_root),
        mode="sendell-ball-room",
        process_name="LBA2.EXE",
        launch_path=str(launch_path),
        launch_save=str(launch_save_path),
        run_id=args.run_id,
    )
    capture = WindowCapture()
    window_input = WindowInput()
    launched_process: subprocess.Popen[str] | None = None
    staged = False
    pid: int | None = None
    capture_variant_name = capture_variant(args.menu, args.menu_phase)
    checkpoint_order: list[str] = []
    checkpoint_captures: dict[str, dict[str, object]] = {}

    try:
        def record_checkpoint(checkpoint: dict[str, object]) -> None:
            checkpoint_name = checkpoint["checkpoint_name"]
            assert isinstance(checkpoint_name, str)
            checkpoint_order.append(checkpoint_name)
            checkpoint_captures[checkpoint_name] = checkpoint

        preflight_owned_launch_processes(writer, ("LBA2.EXE", "cdb.exe"))
        launched_process = subprocess.Popen([str(launch_path)], cwd=str(launch_path.parent))
        pid = launched_process.pid
        writer.write_event(
            PersistedStatusEvent(
                message="launched LBA2.EXE for Sendell's Ball capture",
                mode="sendell-ball-room",
                process_name="LBA2.EXE",
                pid=pid,
                launch_path=str(launch_path),
                launch_save=str(launch_save_path),
            )
        )

        stage_single_load_game_save(
            staged_args,
            writer,
            launch_path,
            lane_name="sendell-ball-room",
            default_source=default_source_save_path(DEFAULT_SAVE_NAME),
        )
        staged = True
        drive_single_save_load_game_startup(
            writer,
            pid,
            scene_label="Sendell's Ball",
            adeline_enter_delay_sec=args.adeline_enter_delay_sec,
            startup_window_timeout_sec=args.startup_window_timeout_sec,
            post_load_settle_delay_sec=args.post_load_settle_sec,
            post_load_status_message="waited for the staged Sendell's Ball save to settle before checkpoint capture",
            capture=capture,
            window_input=window_input,
        )

        cdb_path = resolve_cdb_path(args.cdb_path)
        write_status(writer, f"resolved cdb.exe at {cdb_path}", pid=pid)
        reader = CdbMemoryReader(
            cdb_path,
            pid,
            timeout_sec=args.cdb_timeout_sec,
        )

        record_checkpoint(capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            "loaded_pre_cast",
            ptr_window_count=args.ptr_window_count,
        ))
        if args.menu == "behavior" and args.menu_phase == "pre":
            record_checkpoint(capture_checkpoint_with_held_key(
                writer,
                capture,
                window_input,
                reader,
                pid,
                virtual_key=menu_virtual_key(args.menu),
                action_name="Left Ctrl / behavior menu",
                checkpoint_name="pre_behavior",
                ptr_window_count=args.ptr_window_count,
                key_open_delay_sec=args.menu_open_delay_sec,
            ))
            write_sendell_run_summary(
                writer,
                launch_save=launch_save_path,
                capture_variant_name=capture_variant_name,
                checkpoint_order=checkpoint_order,
                checkpoint_captures=checkpoint_captures,
            )
            write_status(writer, "sendell pre-behavior capture completed", pid=pid)
            return 0
        if args.menu == "inventory" and args.menu_phase == "pre":
            record_checkpoint(capture_checkpoint_with_held_key(
                writer,
                capture,
                window_input,
                reader,
                pid,
                virtual_key=menu_virtual_key(args.menu),
                action_name="Left Shift / inventory menu",
                checkpoint_name="pre_inventory",
                ptr_window_count=args.ptr_window_count,
                key_open_delay_sec=args.menu_open_delay_sec,
            ))
            write_sendell_run_summary(
                writer,
                launch_save=launch_save_path,
                capture_variant_name=capture_variant_name,
                checkpoint_order=checkpoint_order,
                checkpoint_captures=checkpoint_captures,
            )
            write_status(writer, "sendell pre-inventory capture completed", pid=pid)
            return 0

        send_virtual_key(writer, capture, window_input, pid, 0x46, "F / lightning spell")
        time.sleep(args.after_cast_delay_sec)
        record_checkpoint(capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            "after_f_cast",
            ptr_window_count=args.ptr_window_count,
        ))

        time.sleep(args.dialog1_delay_sec)
        record_checkpoint(capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            "dialog_1",
            ptr_window_count=args.ptr_window_count,
        ))

        send_virtual_key(writer, capture, window_input, pid, WindowInput.VK_RETURN, "Enter / advance to second dialog")
        time.sleep(args.dialog2_delay_sec)
        record_checkpoint(capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            "dialog_2",
            ptr_window_count=args.ptr_window_count,
        ))

        send_virtual_key(writer, capture, window_input, pid, WindowInput.VK_RETURN, "Enter / dismiss second dialog")
        time.sleep(args.post_dialog_delay_sec)
        record_checkpoint(capture_checkpoint(
            writer,
            capture,
            reader,
            pid,
            "post_dialog_room",
            ptr_window_count=args.ptr_window_count,
        ))
        if args.menu == "behavior" and args.menu_phase == "post":
            record_checkpoint(capture_checkpoint_with_held_key(
                writer,
                capture,
                window_input,
                reader,
                pid,
                virtual_key=menu_virtual_key(args.menu),
                action_name="Left Ctrl / behavior menu",
                checkpoint_name="post_behavior",
                ptr_window_count=args.ptr_window_count,
                key_open_delay_sec=args.menu_open_delay_sec,
            ))
        if args.menu == "inventory" and args.menu_phase == "post":
            record_checkpoint(capture_checkpoint_with_held_key(
                writer,
                capture,
                window_input,
                reader,
                pid,
                virtual_key=menu_virtual_key(args.menu),
                action_name="Left Shift / inventory menu",
                checkpoint_name="post_inventory",
                ptr_window_count=args.ptr_window_count,
                key_open_delay_sec=args.menu_open_delay_sec,
            ))

        write_sendell_run_summary(
            writer,
            launch_save=launch_save_path,
            capture_variant_name=capture_variant_name,
            checkpoint_order=checkpoint_order,
            checkpoint_captures=checkpoint_captures,
        )
        write_status(writer, "sendell capture completed", pid=pid)
        return 0
    except Exception as error:
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
            )
        )
        if checkpoint_order:
            try:
                write_sendell_run_summary(
                    writer,
                    launch_save=launch_save_path,
                    capture_variant_name=capture_variant_name,
                    checkpoint_order=checkpoint_order,
                    checkpoint_captures=checkpoint_captures,
                )
            except Exception as summary_error:
                writer.write_event(
                    PersistedErrorEvent(
                        description=f"failed to write sendell summary after capture error: {summary_error}",
                    )
                )
        return 1
    finally:
        if staged:
            try:
                cleanup_staged_load_game_save(staged_args, writer, launch_path)
            except Exception as cleanup_error:
                writer.write_event(
                    PersistedErrorEvent(
                        description=f"failed to restore canonical SAVE contents: {cleanup_error}",
                    )
                )
        if launched_process is not None and pid is not None and not args.keep_process:
            try:
                terminate_process(writer, launched_process, pid=pid)
            except Exception as terminate_error:
                writer.write_event(
                    PersistedErrorEvent(
                        description=f"failed to terminate launched LBA2.EXE cleanly: {terminate_error}",
                    )
                )
        writer.close()


if __name__ == "__main__":
    raise SystemExit(main())
