from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Literal, Protocol
from life_trace_shared import (
    AgentWireEventType,
    JsonlWriter,
    PersistedScreenshotErrorEvent,
    PersistedScreenshotEvent,
    PersistedStatusEvent,
    REPO_ROOT,
    TracePreset,
)
from life_trace_windows import CaptureError, WindowCapture, WindowInfo


LaunchStrategy = Literal["fra_spawn", "native_launch_then_fra_attach"]


class StructuredSceneController(Protocol):
    exit_code: int
    terminal: bool
    last_error: str | None

    def begin(self) -> None: ...
    def handle_event(self, event: AgentWireEventType) -> None: ...
    def handle_timeout(self) -> None: ...
    def handle_interrupt(self) -> None: ...
    def handle_process_exit(self, reason: str) -> None: ...
    def handle_runtime_error(self, reason: str) -> None: ...
    def next_deadline(self) -> float | None: ...
    def poll(self, now: float) -> None: ...


class StructuredSceneControllerBase:
    def __init__(
        self,
        args: argparse.Namespace,
        writer: JsonlWriter,
        pid: int,
        *,
        capture: WindowCapture | None = None,
    ) -> None:
        self.args = args
        self.writer = writer
        self.pid = pid
        self.phase = "attached"
        self.exit_code = 1
        self.terminal = False
        self.last_error: str | None = None

        self.capture = WindowCapture() if capture is None else capture
        self.run_screenshot_dir = writer.screenshot_dir
        self.required_screenshots: dict[str, str] = {}

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


@dataclass(frozen=True)
class StructuredSceneSpec:
    preset: TracePreset
    controller_factory: Callable[[argparse.Namespace, JsonlWriter, int], StructuredSceneController]
    prepare_launch: Callable[[JsonlWriter, Path, int], None] | None = None
    launch_strategy: LaunchStrategy = "fra_spawn"
    requires_callsite_map: bool = False
    helper_capture_enabled: bool = False
