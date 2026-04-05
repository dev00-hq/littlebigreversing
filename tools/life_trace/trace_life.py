from __future__ import annotations

import argparse
import ctypes
import json
import os
import queue
import signal
import struct
import sys
import threading
import time
import zlib
from ctypes import wintypes
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TAVERN_POST_076_TIMEOUT_SEC = 2.0


def parse_int(value: str) -> int:
    return int(value, 0)


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_hex_bytes(value: str) -> tuple[int, ...]:
    return tuple(int(part, 16) for part in value.split())


@dataclass(frozen=True)
class TracePreset:
    name: str
    target_object: int
    target_opcode: int
    target_offset: int
    focus_offset_start: int
    focus_offset_end: int
    fingerprint_offset: int
    fingerprint_hex: str
    max_hits: int
    default_timeout_sec: float | None


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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bounded Frida probe for the original Windows LBA2 life interpreter."
    )
    parser.add_argument("--process", default="LBA2.EXE", help="Process name to attach to.")
    parser.add_argument("--launch", help="Launch the executable and attach before resuming it.")
    parser.add_argument(
        "--keep-alive",
        action="store_true",
        help="Leave a spawned process running after the tracer exits.",
    )
    parser.add_argument("--output", required=True, help="JSONL output path.")
    parser.add_argument("--module", default="LBA2.EXE", help="Main module name.")
    parser.add_argument(
        "--frida-repo-root",
        default=r"D:\repos\reverse\frida",
        help="Frida repository root containing build/install-root.",
    )
    parser.add_argument("--mode", choices=["basic", "tavern-trace"], default="basic")
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
        help="Root screenshot directory. Only supported with --mode tavern-trace.",
    )
    args = parser.parse_args()

    if args.max_hits < 1:
        parser.error("--max-hits must be at least 1")
    if args.timeout_sec is not None and args.timeout_sec < 0:
        parser.error("--timeout-sec must be at least 0")

    if args.mode != "tavern-trace" and args.screenshot_dir is not None:
        parser.error("--screenshot-dir requires --mode tavern-trace")

    if args.mode == "tavern-trace":
        preset = TAVERN_TRACE_PRESET
        if args.target_object is not None and args.target_object != preset.target_object:
            parser.error(f"--mode tavern-trace requires --target-object {preset.target_object}")
        if args.target_opcode is not None and args.target_opcode != preset.target_opcode:
            parser.error(f"--mode tavern-trace requires --target-opcode 0x{preset.target_opcode:02X}")
        if args.target_offset is not None and args.target_offset != preset.target_offset:
            parser.error(f"--mode tavern-trace requires --target-offset {preset.target_offset}")

        args.target_object = preset.target_object
        args.target_opcode = preset.target_opcode
        args.target_offset = preset.target_offset
        args.max_hits = preset.max_hits
        args.focus_offset_start = preset.focus_offset_start
        args.focus_offset_end = preset.focus_offset_end
        args.fingerprint_offset = preset.fingerprint_offset
        args.fingerprint_hex = preset.fingerprint_hex
        args.fingerprint_bytes = parse_hex_bytes(preset.fingerprint_hex)
        args.timeout_sec = preset.default_timeout_sec if args.timeout_sec is None else args.timeout_sec
        if args.screenshot_dir is None:
            args.screenshot_dir = str(REPO_ROOT / "work" / "life_trace" / "shots")
    else:
        args.target_object = DEFAULT_BASIC_TARGET_OBJECT if args.target_object is None else args.target_object
        args.target_opcode = DEFAULT_BASIC_TARGET_OPCODE if args.target_opcode is None else args.target_opcode
        args.target_offset = DEFAULT_BASIC_TARGET_OFFSET if args.target_offset is None else args.target_offset
        args.focus_offset_start = None
        args.focus_offset_end = None
        args.fingerprint_offset = None
        args.fingerprint_hex = None
        args.fingerprint_bytes = ()
        args.timeout_sec = 0 if args.timeout_sec is None else args.timeout_sec

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
    config = {
        "moduleName": args.module,
        "mode": args.mode,
        "logAll": args.log_all,
        "maxHits": args.max_hits,
        "targetObject": args.target_object,
        "targetOpcode": args.target_opcode,
        "targetOffset": args.target_offset,
        "windowBefore": args.window_before,
        "windowAfter": args.window_after,
        "focusOffsetStart": args.focus_offset_start,
        "focusOffsetEnd": args.focus_offset_end,
        "fingerprintOffset": args.fingerprint_offset,
        "fingerprintHex": args.fingerprint_hex,
        "fingerprintBytes": list(args.fingerprint_bytes),
    }
    template = (Path(__file__).with_name("agent.js")).read_text(encoding="utf-8")
    return template.replace("__TRACE_CONFIG__", json.dumps(config, separators=(",", ":")))


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

    def write_event(self, event: dict, *, event_id: str | None = None) -> str:
        record = dict(event)
        if event_id is None:
            event_id = self.next_event_id()
        record["event_id"] = event_id
        record.setdefault("timestamp_utc", utc_now_iso())
        line = json.dumps(record, ensure_ascii=True, sort_keys=True)
        self.handle.write(f"{line}\n")
        self.handle.flush()
        sys.stdout.write(f"{line}\n")
        sys.stdout.flush()
        return event_id

    def close(self) -> None:
        self.handle.close()


def normalize_script_message(message: dict) -> tuple[dict | None, str | None]:
    payload = message.get("payload") or {}
    if message.get("type") == "send":
        event = dict(payload)
        nested_payload = event.pop("payload", None)
        if isinstance(nested_payload, dict):
            event.update(nested_payload)
        return event, None

    if message.get("type") == "error":
        description = message.get("description") or "unknown script error"
        return {
            "kind": "error",
            "description": description,
            "stack": message.get("stack"),
        }, description

    return None, None


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

    def handle_event(self, event: dict) -> None:
        self.writer.write_event(event)
        if event.get("kind") == "trace" and event.get("matches_target"):
            self.matched_hits += 1
            if self.matched_hits >= self.args.max_hits:
                self.terminal = True
        elif event.get("kind") == "error":
            self.last_error = event.get("description") or "unknown error"
            self.exit_code = 1
            self.terminal = True

    def handle_timeout(self) -> None:
        description = f"timed out without a matched hit after {self.args.timeout_sec:g} seconds"
        self.writer.write_event(
            {
                "kind": "status",
                "matched_hits": self.matched_hits,
                "message": description,
                "timed_out": True,
            }
        )
        self.last_error = description
        self.exit_code = 1
        self.terminal = True

    def handle_interrupt(self) -> None:
        self.writer.write_event(
            {
                "kind": "status",
                "message": "interrupted",
                "matched_hits": self.matched_hits,
            }
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

    def handle_event(self, event: dict) -> None:
        event_id = self.writer.write_event(event)
        kind = event.get("kind")

        if kind == "error":
            self._finalize("unexpected_control_flow", event.get("description") or "agent error", take_final_screenshot=True)
            return

        if kind == "target_validation" and event.get("matches_fingerprint"):
            if not self.matched_fingerprint:
                self.matched_fingerprint = True
                self.active_thread_id = event.get("thread_id")
                self.fingerprint_event_id = event_id
                self._advance_phase("armed_for_window", "fingerprint matched; waiting for the switch window")
                self._capture_required_poi(
                    poi="fingerprint_match",
                    event_id=event_id,
                    object_index=event.get("object_index", 0),
                    offset_value=event.get("fingerprint_start_offset", self.args.fingerprint_offset),
                )
            return

        if not self._is_tracked_event(event):
            return

        if kind == "branch_trace":
            if self.phase == "armed_for_window":
                self._advance_phase("capturing_tavern_trace", "capturing the Tavern switch window")

            if event.get("branch_kind") == "break_jump":
                self.break_target_offset = event.get("computed_target_offset")

            if self.saw_076_fetch and self.post_076_outcome is None:
                self.post_076_outcome = f"branch_trace:{event.get('branch_kind')}"
                self.post_076_outcome_event_id = event_id
                self._finalize_tavern_verdict()
            return

        if kind == "window_trace":
            offset_value = event.get("ptr_prg_offset")
            opcode_value = event.get("opcode")
            if offset_value == self.args.target_offset and opcode_value == self.args.target_opcode:
                if not self.saw_076_fetch:
                    self.saw_076_fetch = True
                    self.post_076_thread_id = event.get("thread_id")
                    self.post_076_deadline = time.monotonic() + TAVERN_POST_076_TIMEOUT_SEC
                    self.opcode_076_event_id = event_id
                    self._advance_phase("capturing_verdict", "captured the 0x76 fetch; waiting for the next outcome")
                    self._capture_required_poi(
                        poi="opcode_076_fetch",
                        event_id=event_id,
                        object_index=event.get("object_index", 0),
                        offset_value=offset_value,
                    )
                return

            if (
                self.saw_076_fetch
                and self.post_076_outcome is None
                and event.get("thread_id") == self.post_076_thread_id
                and event.get("post_076_outcome") == "loop_reentry"
            ):
                self.saw_post_076_loop = True
                self.post_076_outcome = "loop_reentry"
                self.post_076_outcome_event_id = event_id
                self._finalize_tavern_verdict()
            return

        if kind == "do_life_return" and self.saw_076_fetch and self.post_076_outcome is None:
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

    def _is_tracked_event(self, event: dict) -> bool:
        return (
            self.active_thread_id is not None
            and event.get("thread_id") == self.active_thread_id
            and event.get("object_index") == self.args.target_object
        )

    def _advance_phase(self, phase: str, message: str) -> None:
        if self.phase == phase or self.terminal:
            return
        self.phase = phase
        self.writer.write_event({"kind": "status", "phase": phase, "message": message})

    def _capture_required_poi(self, poi: str, event_id: str, object_index: int, offset_value: int | None) -> None:
        if poi in self.required_screenshots or self.terminal:
            return

        try:
            screenshot_path, window = self._capture_window_file(poi, event_id, object_index, offset_value)
        except CaptureError as error:
            self.writer.write_event(
                {
                    "kind": "screenshot_error",
                    "poi": poi,
                    "reason": str(error),
                    "capture_status": "failed",
                },
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
            {
                "kind": "screenshot",
                "poi": poi,
                "screenshot_path": screenshot_path,
                "source_window_title": window.title,
                "capture_status": "captured",
            },
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
                    {
                        "kind": "screenshot_error",
                        "poi": "final_verdict",
                        "reason": str(error),
                        "capture_status": "failed",
                    },
                    event_id=verdict_event_id,
                )
                result = "screenshot_capture_failed"
                reason = f"required screenshot failed for final_verdict: {error}"
            else:
                self.required_screenshots["final_verdict"] = screenshot_path
                self.writer.write_event(
                    {
                        "kind": "screenshot",
                        "poi": "final_verdict",
                        "screenshot_path": screenshot_path,
                        "source_window_title": window.title,
                        "capture_status": "captured",
                    },
                    event_id=verdict_event_id,
                )

        required_screenshots_complete = (
            result != "screenshot_capture_failed"
            and self._required_pois() <= set(self.required_screenshots)
        )

        self.writer.write_event(
            {
                "kind": "verdict",
                "phase": "completed",
                "matched_fingerprint": self.matched_fingerprint,
                "break_target_offset": self.break_target_offset,
                "saw_076_fetch": self.saw_076_fetch,
                "saw_post_076_loop": self.saw_post_076_loop,
                "returned_after_076": self.returned_after_076,
                "hidden_076_case_seen": self.hidden_076_case_seen,
                "required_screenshots_complete": required_screenshots_complete,
                "result": result,
                "reason": reason,
                "fingerprint_event_id": self.fingerprint_event_id,
                "opcode_076_fetch_event_id": self.opcode_076_event_id,
                "post_076_outcome": self.post_076_outcome,
                "post_076_outcome_event_id": self.post_076_outcome_event_id,
            },
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


def main() -> int:
    args = parse_args()
    output_path = Path(args.output).resolve()
    writer = JsonlWriter(output_path)
    interrupted = threading.Event()
    message_queue: queue.Queue[dict] = queue.Queue()

    repo_root = Path(args.frida_repo_root).resolve()
    frida_root, site_packages, frida_lib = ensure_staged_frida(repo_root)

    import frida

    device = frida.get_local_device()
    session = None
    script = None
    spawned_pid: int | None = None
    controller: BasicTraceController | TavernTraceController | None = None

    def on_message(message: dict, data) -> None:
        event, _error = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)

    def handle_interrupt(signum, frame) -> None:
        interrupted.set()

    previous_sigint = signal.signal(signal.SIGINT, handle_interrupt)

    try:
        if args.launch:
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawned_pid = device.spawn([str(launch_path)], cwd=str(launch_path.parent))
            pid = spawned_pid
        else:
            process = find_process(device, args.process)
            pid = process.pid

        controller = TavernTraceController(args, writer, pid) if args.mode == "tavern-trace" else BasicTraceController(args, writer)

        session = device.attach(pid)
        script = session.create_script(load_agent_source(args))
        script.on("message", on_message)
        script.load()

        writer.write_event(
            {
                "kind": "status",
                "phase": "attached" if args.mode == "tavern-trace" else None,
                "frida_module": getattr(frida, "__file__", None),
                "frida_repo_root": str(repo_root),
                "frida_root": str(frida_root),
                "frida_site_packages": str(site_packages),
                "frida_lib": str(frida_lib),
                "message": "attached",
                "mode": args.mode,
                "output_path": str(output_path),
                "pid": pid,
                "process_name": args.process,
                "launch_path": args.launch,
            }
        )

        if spawned_pid is not None:
            device.resume(spawned_pid)
            writer.write_event(
                {
                    "kind": "status",
                    "message": "resumed spawned process",
                    "pid": spawned_pid,
                }
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
                    {
                        "kind": "status",
                        "message": "target process exited",
                        "pid": pid,
                    }
                )
                if isinstance(controller, TavernTraceController):
                    controller._finalize(
                        "process_exited",
                        f"process {pid} exited before the Tavern trace completed",
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
            {
                "kind": "error",
                "description": str(error),
                "stack": None,
            }
        )
        if controller is not None and isinstance(controller, TavernTraceController) and not controller.terminal:
            controller._finalize("unexpected_control_flow", str(error), take_final_screenshot=True)
        elif controller is not None:
            controller.last_error = str(error)
            controller.exit_code = 1
            controller.terminal = True
        elif controller is None:
            print(str(error), file=sys.stderr)
            return 1
    finally:
        signal.signal(signal.SIGINT, previous_sigint)

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
                    {
                        "kind": "status",
                        "message": "leaving spawned process alive",
                        "pid": spawned_pid,
                    }
                )
            else:
                try:
                    device.kill(spawned_pid)
                    writer.write_event(
                        {
                            "kind": "status",
                            "message": "killed spawned process",
                            "pid": spawned_pid,
                        }
                    )
                except Exception:  # noqa: BLE001
                    pass

        writer.close()

    if controller is not None and controller.last_error:
        print(controller.last_error, file=sys.stderr)
    return 0 if controller is not None and controller.exit_code == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
