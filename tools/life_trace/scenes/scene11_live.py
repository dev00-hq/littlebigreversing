from __future__ import annotations

import argparse
import time
from pathlib import Path

from life_trace_shared import (
    AgentErrorEvent,
    AgentWindowTraceEvent,
    AgentWireEventType,
    JsonlWriter,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PersistedVerdictEvent,
    TRACE_COMPLETE_STATUS_MESSAGE,
    TRACE_FINISHED_STATUS_MESSAGE,
    TracePreset,
    optional_value,
)
from life_trace_windows import CaptureError, WindowCapture
from scenes.base import StructuredSceneControllerBase, StructuredSceneSpec
from scenes.load_game import default_source_save_path
from scenes.scene11 import (
    cleanup_scene11_launch,
    drive_scene11_launch_startup,
    stage_scene11_load_game_save,
)


SCENE11_LIVE_PAIR_PRESET = TracePreset(
    name="scene11-live-pair",
    target_object=2,
    target_opcode=0x76,
    target_offset=103,
    focus_offset_start=96,
    focus_offset_end=103,
    fingerprint_offset=None,
    fingerprint_hex=None,
    max_hits=1,
    default_timeout_sec=60.0,
    comparison_object=2,
    comparison_opcode=0x74,
    comparison_offset=96,
    launch_save=str(default_source_save_path("S8741.LBA")),
)

SCENE11_LIVE_PRE_ATTACH_SETTLE_POLL_COUNT = 3
SCENE11_LIVE_PRE_ATTACH_SETTLE_POLL_SEC = 2.0
SCENE11_LIVE_POST_ATTACH_SCREENSHOT_DELAY_SEC = 1.0


def prepare_scene11_live_launch(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
    pid: int,
) -> None:
    stage_scene11_load_game_save(args, writer, launch_path)
    drive_scene11_launch_startup(
        writer,
        pid,
        post_load_status_message="waited for the sole staged save to settle before Scene11 live pre-attach settle polls",
    )

    capture = WindowCapture()
    for tick in range(1, SCENE11_LIVE_PRE_ATTACH_SETTLE_POLL_COUNT + 1):
        time.sleep(SCENE11_LIVE_PRE_ATTACH_SETTLE_POLL_SEC)
        window = capture.wait_for_window(pid, timeout_sec=1.0)
        writer.write_event(
            PersistedStatusEvent(
                message=(
                    "confirmed Scene11 window during live pre-attach settle poll "
                    f"{tick}/{SCENE11_LIVE_PRE_ATTACH_SETTLE_POLL_COUNT}: {window.title}"
                ),
                pid=pid,
            )
        )


class Scene11LivePairController(StructuredSceneControllerBase):
    def __init__(
        self,
        args: argparse.Namespace,
        writer: JsonlWriter,
        pid: int,
        *,
        capture: WindowCapture | None = None,
    ) -> None:
        super().__init__(args, writer, pid, capture=capture)
        self.active_thread_id: int | None = None
        self.saw_default = False
        self.saw_end_switch = False
        self.default_event_id: str | None = None
        self.end_switch_event_id: str | None = None
        self.hit_count = 0
        self.loaded_scene_capture_deadline: float | None = None

    def begin(self) -> None:
        self._advance_phase("waiting_for_live_pair", "waiting for the live Scene11 LM pair on object 2")
        self.loaded_scene_capture_deadline = time.monotonic() + SCENE11_LIVE_POST_ATTACH_SCREENSHOT_DELAY_SEC

    def handle_event(self, event: AgentWireEventType) -> None:
        event_id = self.writer.write_event(event)
        if isinstance(event, AgentErrorEvent):
            self._finalize(
                "scene11_live_pair_runtime_error",
                event.description or "agent error",
                take_final_screenshot=True,
            )
            return

        if not isinstance(event, AgentWindowTraceEvent):
            return

        if event.object_index != self.args.target_object:
            return

        offset_value = optional_value(event.ptr_prg_offset)
        opcode_value = optional_value(event.opcode)
        if offset_value is None or opcode_value is None:
            return

        is_default = (
            offset_value == self.args.comparison_offset
            and opcode_value == self.args.comparison_opcode
        )
        is_end_switch = offset_value == self.args.target_offset and opcode_value == self.args.target_opcode
        if not is_default and not is_end_switch:
            return

        if self.active_thread_id is None:
            self.active_thread_id = event.thread_id
        if event.thread_id != self.active_thread_id:
            return

        self.hit_count += 1
        if is_default and not self.saw_default:
            self.saw_default = True
            self.default_event_id = event_id
        if is_end_switch and not self.saw_end_switch:
            self.saw_end_switch = True
            self.end_switch_event_id = event_id

        if self.saw_default and self.saw_end_switch:
            self._finalize(
                "scene11_live_pair_proved",
                "captured both LM_DEFAULT@96 and LM_END_SWITCH@103 on live object 2 via slim DoLifeLoop proof lane",
                take_final_screenshot=True,
            )

    def handle_timeout(self) -> None:
        seen_offsets: list[str] = []
        if self.saw_default:
            seen_offsets.append("LM_DEFAULT@96")
        if self.saw_end_switch:
            seen_offsets.append("LM_END_SWITCH@103")
        suffix = "none" if not seen_offsets else ", ".join(seen_offsets)
        self._finalize(
            "scene11_live_pair_timed_out",
            f"timed out after {self.args.timeout_sec:g} seconds with seen offsets: {suffix}",
            take_final_screenshot=True,
        )

    def handle_interrupt(self) -> None:
        self._finalize(
            "scene11_live_pair_interrupted",
            "interrupted before the live Scene11 pair proof completed",
            take_final_screenshot=True,
        )

    def handle_process_exit(self, reason: str) -> None:
        result = "scene11_live_pair_process_exited"
        if "Application Error dialog detected" in reason:
            result = "scene11_live_pair_application_error"
        self._finalize(result, reason, take_final_screenshot=True)

    def handle_runtime_error(self, reason: str) -> None:
        self._finalize("scene11_live_pair_runtime_error", reason, take_final_screenshot=True)

    def next_deadline(self) -> float | None:
        if "loaded_scene" not in self.required_screenshots:
            return self.loaded_scene_capture_deadline
        return None

    def poll(self, now: float) -> None:
        if self.loaded_scene_capture_deadline is None or self.terminal:
            return
        if "loaded_scene" in self.required_screenshots:
            self.loaded_scene_capture_deadline = None
            return
        if now < self.loaded_scene_capture_deadline:
            return
        self._capture_required_poi(
            poi="loaded_scene",
            event_id=self.writer.next_event_id(),
            object_index=self.args.target_object,
            offset_value=self.args.target_offset,
        )
        self.loaded_scene_capture_deadline = None

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
                reason = f"{reason}; final_verdict screenshot failed: {error}"
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
            {"loaded_scene", "final_verdict"} <= set(self.required_screenshots)
        )

        self.writer.write_event(
            PersistedVerdictEvent(
                phase="completed",
                matched_fingerprint=False,
                required_screenshots_complete=required_screenshots_complete,
                result=result,
                reason=reason,
                primary_event_id=self.default_event_id,
                comparison_event_id=self.end_switch_event_id,
            ),
            event_id=verdict_event_id,
        )
        self.writer.write_event(
            PersistedStatusEvent(
                phase="completed",
                message=TRACE_COMPLETE_STATUS_MESSAGE if result == "scene11_live_pair_proved" else TRACE_FINISHED_STATUS_MESSAGE,
                pid=self.pid,
            )
        )
        self.last_error = None if result == "scene11_live_pair_proved" else reason
        self.exit_code = 0 if result == "scene11_live_pair_proved" else 1
        self.phase = "completed"
        self.terminal = True


SCENE_SPEC = StructuredSceneSpec(
    preset=SCENE11_LIVE_PAIR_PRESET,
    controller_factory=Scene11LivePairController,
    prepare_launch=prepare_scene11_live_launch,
    cleanup_launch=cleanup_scene11_launch,
    launch_strategy="native_launch_then_attach",
    runtime_backend="frida_probe",
    requires_callsite_map=False,
    helper_capture_enabled=False,
)
