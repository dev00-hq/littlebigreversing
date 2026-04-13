from __future__ import annotations

import argparse
import time
from pathlib import Path

from life_trace_shared import (
    AgentBranchTraceEvent,
    AgentDoLifeReturnEvent,
    AgentErrorEvent,
    AgentTargetValidationEvent,
    AgentWindowTraceEvent,
    AgentWireEventType,
    JsonlWriter,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PersistedVerdictEvent,
    TAVERN_ADELINE_ENTER_DELAY_SEC,
    TAVERN_POST_076_TIMEOUT_SEC,
    TAVERN_STARTUP_WINDOW_TIMEOUT_SEC,
    TRACE_COMPLETE_STATUS_MESSAGE,
    TRACE_FINISHED_STATUS_MESSAGE,
    TracePreset,
    optional_value,
)
from life_trace_windows import WindowCapture, WindowInfo, WindowInput
from scenes.base import StructuredSceneControllerBase, StructuredSceneSpec
from scenes.load_game import (
    cleanup_staged_load_game_save,
    default_source_save_path,
    drive_single_save_load_game_startup,
    stage_single_load_game_save,
)


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
    launch_save=str(default_source_save_path("inside-tavern.LBA")),
)


def stage_tavern_load_game_save(
    args: argparse.Namespace,
    writer: JsonlWriter,
    launch_path: Path,
) -> tuple[Path, Path]:
    return stage_single_load_game_save(
        args,
        writer,
        launch_path,
        lane_name="tavern-trace",
        default_source=default_source_save_path("inside-tavern.LBA"),
    )


def drive_tavern_launch_startup(
    writer: JsonlWriter,
    pid: int,
    *,
    capture: WindowCapture | None = None,
    window_input: WindowInput | None = None,
) -> None:
    drive_single_save_load_game_startup(
        writer,
        pid,
        scene_label="Tavern",
        adeline_enter_delay_sec=TAVERN_ADELINE_ENTER_DELAY_SEC,
        startup_window_timeout_sec=TAVERN_STARTUP_WINDOW_TIMEOUT_SEC,
        capture=capture,
        window_input=window_input,
    )


def prepare_tavern_launch(args: argparse.Namespace, writer: JsonlWriter, launch_path: Path, pid: int) -> None:
    stage_tavern_load_game_save(args, writer, launch_path)
    drive_tavern_launch_startup(writer, pid)


def cleanup_tavern_launch(args: argparse.Namespace, writer: JsonlWriter, launch_path: Path) -> None:
    cleanup_staged_load_game_save(args, writer, launch_path)


class TavernTraceController(StructuredSceneControllerBase):
    def __init__(
        self,
        args: argparse.Namespace,
        writer: JsonlWriter,
        pid: int,
        *,
        capture: WindowCapture | None = None,
    ) -> None:
        super().__init__(args, writer, pid, capture=capture)
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

    def handle_process_exit(self, reason: str) -> None:
        self._finalize("process_exited", reason, take_final_screenshot=False)

    def handle_runtime_error(self, reason: str) -> None:
        self._finalize("unexpected_control_flow", reason, take_final_screenshot=True)

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
        self.writer.write_event(
            PersistedStatusEvent(
                phase="completed",
                message=TRACE_COMPLETE_STATUS_MESSAGE if result == "tavern_trace_complete" else TRACE_FINISHED_STATUS_MESSAGE,
                pid=self.pid,
            )
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


SCENE_SPEC = StructuredSceneSpec(
    preset=TAVERN_TRACE_PRESET,
    controller_factory=TavernTraceController,
    prepare_launch=prepare_tavern_launch,
    cleanup_launch=cleanup_tavern_launch,
    launch_strategy="native_launch_then_attach",
    requires_callsite_map=False,
    helper_capture_enabled=False,
)
