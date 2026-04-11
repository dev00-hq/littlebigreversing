from __future__ import annotations

import argparse
from pathlib import Path

from life_trace_shared import (
    AgentDoLifeReturnEvent,
    AgentErrorEvent,
    AgentHelperCallsiteEvent,
    AgentTargetValidationEvent,
    AgentWindowTraceEvent,
    AgentWireEventType,
    JsonlWriter,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    PersistedVerdictEvent,
    SCENE11_ADELINE_ENTER_DELAY_SEC,
    SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
    TRACE_COMPLETE_STATUS_MESSAGE,
    TRACE_FINISHED_STATUS_MESSAGE,
    TracePreset,
    optional_value,
)
from life_trace_windows import WindowCapture, WindowInput
from scenes.base import StructuredSceneControllerBase, StructuredSceneSpec
from scenes.load_game import (
    cleanup_staged_load_game_save,
    default_source_save_path,
    drive_single_save_load_game_startup,
    stage_single_load_game_save,
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
    launch_save=str(default_source_save_path("S8741.LBA")),
)


def scene11_load_game_save_paths(launch_path: Path, launch_save: str | None) -> tuple[Path, Path]:
    save_dir = launch_path.parent / "SAVE"
    source_path = default_source_save_path("S8741.LBA") if launch_save is None else Path(launch_save)
    return source_path, save_dir / source_path.name


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
    capture: WindowCapture | None = None,
    window_input: WindowInput | None = None,
) -> None:
    drive_single_save_load_game_startup(
        writer,
        pid,
        scene_label="Scene11",
        adeline_enter_delay_sec=SCENE11_ADELINE_ENTER_DELAY_SEC,
        startup_window_timeout_sec=SCENE11_STARTUP_WINDOW_TIMEOUT_SEC,
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


class Scene11PairController(StructuredSceneControllerBase):
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
        self.fingerprint_event_id: str | None = None
        self.primary_event_id: str | None = None
        self.primary_event: AgentWindowTraceEvent | AgentDoLifeReturnEvent | None = None
        self.comparison_event_id: str | None = None
        self.comparison_event: AgentWindowTraceEvent | AgentDoLifeReturnEvent | None = None

    def begin(self) -> None:
        self._advance_phase("waiting_for_fingerprint", "waiting for the canonical scene-11 fingerprint")

    def handle_event(self, event: AgentWireEventType) -> None:
        event_id = self.writer.write_event(event)
        if isinstance(event, AgentErrorEvent):
            self._finalize("unexpected_control_flow", event.description or "agent error", take_final_screenshot=True)
            return

        if (
            isinstance(event, AgentHelperCallsiteEvent)
            and self.writer.requires_callsite_map
            and self.writer.last_helper_callsite_status == "unmapped"
            and self.writer.last_helper_callsite_event_id == event_id
        ):
            helper_rel = self.writer.last_helper_callsite_rel or event.caller_static_rel
            self._finalize(
                "unmapped_callsite",
                f"helper callsite {event.callee_name} at {helper_rel} was not present in the configured static map",
                take_final_screenshot=True,
            )
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
                offset_value=optional_value(event.ptr_prg_before_offset)
                if isinstance(event, AgentWindowTraceEvent)
                else event.ptr_prg_before_offset,
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
                offset_value=optional_value(event.ptr_prg_before_offset)
                if isinstance(event, AgentWindowTraceEvent)
                else event.ptr_prg_before_offset,
            )
            if self.primary_event_id is None:
                self._advance_phase(
                    "capturing_primary",
                    "captured object 18 comparison early; still waiting for object 12 LM_DEFAULT",
                )
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

    def handle_process_exit(self, reason: str) -> None:
        self._finalize("process_exited", reason, take_final_screenshot=False)

    def handle_runtime_error(self, reason: str) -> None:
        self._finalize("unexpected_control_flow", reason, take_final_screenshot=True)

    def next_deadline(self) -> float | None:
        return None

    def poll(self, now: float) -> None:
        return

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
        self.writer.write_event(
            PersistedStatusEvent(
                phase="completed",
                message=TRACE_COMPLETE_STATUS_MESSAGE if result == "scene11_pair_complete" else TRACE_FINISHED_STATUS_MESSAGE,
                pid=self.pid,
            )
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


SCENE_SPEC = StructuredSceneSpec(
    preset=SCENE11_PAIR_PRESET,
    controller_factory=Scene11PairController,
    prepare_launch=prepare_scene11_launch,
    cleanup_launch=cleanup_scene11_launch,
    launch_strategy="native_launch_then_fra_attach",
    requires_callsite_map=True,
    helper_capture_enabled=True,
)
