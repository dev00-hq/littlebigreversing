from __future__ import annotations

import ctypes
import os
import struct
import time
import zlib
from ctypes import wintypes
from dataclasses import dataclass
from pathlib import Path


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


class InputError(RuntimeError):
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
        candidates = self._enumerate_visible_windows(pid)
        if not candidates:
            return None

        def sort_key(window: WindowInfo) -> tuple[int, int, int]:
            owner = self.user32.GetWindow(window.hwnd, self.GW_OWNER)
            area = window.width * window.height
            return (1 if not owner else 0, area, len(window.title))

        candidates.sort(key=sort_key, reverse=True)
        return candidates[0]

    def find_window_title_fragments(self, *fragments: str) -> WindowInfo | None:
        normalized = tuple(fragment.lower() for fragment in fragments if fragment)
        if not normalized:
            return None

        candidates = [
            window
            for window in self._enumerate_visible_windows(None)
            if all(fragment in window.title.lower() for fragment in normalized)
        ]
        if not candidates:
            return None

        candidates.sort(key=lambda window: (window.width * window.height, len(window.title)), reverse=True)
        return candidates[0]

    def _enumerate_visible_windows(self, pid: int | None) -> list[WindowInfo]:
        candidates: list[WindowInfo] = []

        @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
        def enum_proc(hwnd, _lparam):
            process_id = wintypes.DWORD()
            self.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
            if pid is not None and process_id.value != pid:
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
        return candidates

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


class WindowInput:
    KEYEVENTF_KEYUP = 0x0002
    SW_RESTORE = 9
    VK_RETURN = 0x0D
    VK_UP = 0x26
    VK_DOWN = 0x28

    def __init__(self) -> None:
        if os.name != "nt":
            raise RuntimeError("window input is only supported on Windows")

        self.user32 = ctypes.windll.user32
        self.user32.IsIconic.argtypes = [wintypes.HWND]
        self.user32.IsIconic.restype = wintypes.BOOL
        self.user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
        self.user32.ShowWindow.restype = wintypes.BOOL
        self.user32.BringWindowToTop.argtypes = [wintypes.HWND]
        self.user32.BringWindowToTop.restype = wintypes.BOOL
        self.user32.SetForegroundWindow.argtypes = [wintypes.HWND]
        self.user32.SetForegroundWindow.restype = wintypes.BOOL
        self.user32.MapVirtualKeyW.argtypes = [wintypes.UINT, wintypes.UINT]
        self.user32.MapVirtualKeyW.restype = wintypes.UINT

    def send_enter(self, hwnd: int) -> None:
        self.send_virtual_key(hwnd, self.VK_RETURN)

    def send_up(self, hwnd: int) -> None:
        self.send_virtual_key(hwnd, self.VK_UP)

    def send_down(self, hwnd: int) -> None:
        self.send_virtual_key(hwnd, self.VK_DOWN)

    def send_virtual_key(self, hwnd: int, virtual_key: int) -> None:
        self._activate_window(hwnd)
        scan_code = int(self.user32.MapVirtualKeyW(virtual_key, 0))
        self.user32.keybd_event(virtual_key, scan_code, 0, 0)
        time.sleep(0.05)
        self.user32.keybd_event(virtual_key, scan_code, self.KEYEVENTF_KEYUP, 0)

    def _activate_window(self, hwnd: int) -> None:
        if self.user32.IsIconic(hwnd):
            self.user32.ShowWindow(hwnd, self.SW_RESTORE)
        self.user32.BringWindowToTop(hwnd)
        self.user32.SetForegroundWindow(hwnd)
        time.sleep(0.05)
