from __future__ import annotations

import argparse
import ctypes
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path


PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
DEFAULT_PROCESS_NAME = "LBA2.EXE"
DEFAULT_TEXT_READ_CAP = 512
DEFAULT_DIAL_READ_CAP = 96
CURSOR_MARKER = "<<CURSOR>>"
ROOM36_PAGE2_PREFIX = "Sendell to contact you in case of danger."

# Pinned decoder globals from the current room-36 classic proof lane.
BUF_TEXT_GLOBAL = 0x004CC494
PT_TEXT_GLOBAL = 0x004CC498
SIZE_TEXT_GLOBAL = 0x004CC49C
BUF_ORDER_GLOBAL = 0x004CC4A0
PT_DIAL_GLOBAL = 0x004CCDF0
CURRENT_DIAL_GLOBAL = 0x004CCF10


@dataclass(frozen=True)
class GlobalField:
    name: str
    address: int
    size: int = 4


GLOBAL_FIELDS = (
    GlobalField("BufOrder", BUF_ORDER_GLOBAL),
    GlobalField("BufText", BUF_TEXT_GLOBAL),
    GlobalField("PtText", PT_TEXT_GLOBAL),
    GlobalField("SizeText", SIZE_TEXT_GLOBAL),
    GlobalField("PtDial", PT_DIAL_GLOBAL),
    GlobalField("CurrentDial", CURRENT_DIAL_GLOBAL, 2),
)


@dataclass(frozen=True)
class DecodedDialog:
    text: str
    record_byte_length: int
    source_offsets: tuple[int, ...]


class ProcessReadError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Dump the pinned original-runtime dialog globals plus the decoded text/cursor "
            "state from a live LBA2.EXE process."
        )
    )
    parser.add_argument("--process-name", default=DEFAULT_PROCESS_NAME)
    parser.add_argument("--attach-pid", type=int)
    parser.add_argument("--text-read-cap", type=int, default=DEFAULT_TEXT_READ_CAP)
    parser.add_argument("--dial-read-cap", type=int, default=DEFAULT_DIAL_READ_CAP)
    parser.add_argument("--label", help="Optional label to include in the output payload.")
    parser.add_argument("--out", help="Optional JSON output path. Defaults to stdout.")
    return parser.parse_args()


def find_pid_by_name(process_name: str) -> int:
    target = process_name.lower()
    completed = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip() or "<no output>"
        raise ProcessReadError(f"tasklist failed: {detail}")
    for raw_line in completed.stdout.splitlines():
        line = raw_line.strip().strip('"')
        if not line:
            continue
        columns = [part.strip('"') for part in raw_line.split('","')]
        if len(columns) < 2:
            continue
        name, pid_text = columns[0], columns[1]
        if name.lower() != target:
            continue
        try:
            return int(pid_text)
        except ValueError as exc:
            raise ProcessReadError(f"tasklist returned a non-integer pid for {name}: {pid_text}") from exc
    raise ProcessReadError(f"process not found: {process_name}")


class ProcessReader:
    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.kernel32 = ctypes.windll.kernel32
        self.handle = self.kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
        if not self.handle:
            raise ProcessReadError(f"OpenProcess failed for pid {pid}")

    def close(self) -> None:
        if self.handle:
            self.kernel32.CloseHandle(self.handle)
            self.handle = 0

    def read(self, address: int, size: int) -> bytes:
        buffer = (ctypes.c_ubyte * size)()
        read = ctypes.c_size_t(0)
        ok = self.kernel32.ReadProcessMemory(
            self.handle,
            ctypes.c_void_p(address),
            ctypes.byref(buffer),
            size,
            ctypes.byref(read),
        )
        if not ok or read.value != size:
            raise ProcessReadError(f"ReadProcessMemory failed at 0x{address:08X}")
        return bytes(buffer)

    def read_u16(self, address: int) -> int:
        return int.from_bytes(self.read(address, 2), "little", signed=False)

    def read_u32(self, address: int) -> int:
        return int.from_bytes(self.read(address, 4), "little", signed=False)

    def __enter__(self) -> "ProcessReader":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()


def field_value(field: GlobalField, reader: ProcessReader) -> int:
    if field.size == 4:
        return reader.read_u32(field.address)
    if field.size == 2:
        return reader.read_u16(field.address)
    raise ValueError(f"unsupported size for {field.name}: {field.size}")


def read_c_string(reader: ProcessReader, address: int, cap: int) -> bytes:
    if address == 0:
        return b""
    chunk = reader.read(address, cap)
    terminator = chunk.find(b"\x00")
    return chunk if terminator < 0 else chunk[:terminator]


def decode_dialog_bytes(raw: bytes) -> DecodedDialog:
    chars: list[str] = []
    source_offsets: list[int] = []
    index = 0
    while index < len(raw):
        value = raw[index]
        if value == 0x00:
            break
        if value == 0x01:
            chars.append("\n")
            source_offsets.append(index)
            index += 1
            continue
        chars.append(chr(value) if 0x20 <= value <= 0x7E else f"\\x{value:02X}")
        source_offsets.append(index)
        index += 1
    return DecodedDialog(
        text="".join(chars),
        record_byte_length=index,
        source_offsets=tuple(source_offsets),
    )


def cursor_state(cursor_offset: int | None, record_byte_length: int) -> str:
    if cursor_offset is None:
        return "unknown"
    if cursor_offset < 0:
        return "before_record"
    if cursor_offset < record_byte_length:
        return "inside_record"
    if cursor_offset == record_byte_length:
        return "at_terminator"
    return "after_record"


def annotate_cursor(decoded: DecodedDialog, cursor_offset: int | None) -> str:
    if cursor_offset is None:
        return decoded.text

    state = cursor_state(cursor_offset, decoded.record_byte_length)
    if state in {"at_terminator", "after_record"} or not decoded.source_offsets:
        if state == "after_record":
            return f"{decoded.text}{CURSOR_MARKER}+{cursor_offset - decoded.record_byte_length}"
        return f"{decoded.text}{CURSOR_MARKER}"

    insertion_index = len(decoded.text)
    for char_index, source_offset in enumerate(decoded.source_offsets):
        if cursor_offset <= source_offset:
            insertion_index = char_index
            break
    return f"{decoded.text[:insertion_index]}{CURSOR_MARKER}{decoded.text[insertion_index:]}"


def split_text_at_cursor(decoded: DecodedDialog, cursor_offset: int | None) -> tuple[str, str]:
    if cursor_offset is None:
        return decoded.text, ""

    state = cursor_state(cursor_offset, decoded.record_byte_length)
    if state == "after_record":
        return decoded.text, ""
    if state == "at_terminator":
        return decoded.text, ""
    if not decoded.source_offsets:
        return "", decoded.text

    split_index = len(decoded.text)
    for char_index, source_offset in enumerate(decoded.source_offsets):
        if cursor_offset <= source_offset:
            split_index = char_index
            break
    return decoded.text[:split_index], decoded.text[split_index:]


def infer_next_page_split(decoded: DecodedDialog, cursor_offset: int | None) -> dict[str, object]:
    text_before_cursor, text_from_cursor = split_text_at_cursor(decoded, cursor_offset)
    return {
        "text_before_cursor": text_before_cursor,
        "text_from_cursor": text_from_cursor,
        "cursor_is_next_page_boundary": bool(text_from_cursor),
    }


def snapshot_dialog_state(reader: ProcessReader, *, text_read_cap: int, dial_read_cap: int) -> dict[str, object]:
    globals_snapshot = {field.name: field_value(field, reader) for field in GLOBAL_FIELDS}
    pt_text = int(globals_snapshot["PtText"])
    pt_dial = int(globals_snapshot["PtDial"])
    size_text = int(globals_snapshot["SizeText"])

    text_bytes = read_c_string(reader, pt_text, max(1, text_read_cap)) if pt_text else b""
    dial_bytes = reader.read(pt_dial, max(1, dial_read_cap)) if pt_dial else b""

    decoded = decode_dialog_bytes(text_bytes)
    offset = None
    if pt_text and pt_dial and pt_dial >= pt_text:
        offset = pt_dial - pt_text
    cursor_before, cursor_after = split_text_at_cursor(decoded, offset)
    cursor_state_name = cursor_state(offset, decoded.record_byte_length)
    next_page_split = infer_next_page_split(decoded, offset)

    return {
        "globals": {
            name: (f"0x{value:08X}" if name not in {"CurrentDial", "SizeText"} else value)
            for name, value in globals_snapshot.items()
        },
        "cursor": {
            "pt_dial_minus_pt_text": offset,
            "state": cursor_state_name,
            "annotated_text": annotate_cursor(decoded, offset),
            "text_before_cursor": cursor_before,
            "text_from_cursor": cursor_after,
            "interpretation": (
                "PtDial points at the next unread / next-page text"
                if cursor_state_name == "inside_record"
                else "PtDial is at or beyond the record terminator"
            ),
            "record_byte_length": decoded.record_byte_length,
        },
        "next_page_split": next_page_split,
        "decoded_text": decoded.text,
        "decoded_text_hex": text_bytes.hex(" "),
        "pt_dial_window_hex": dial_bytes.hex(" "),
        "pt_dial_window_ascii": decode_dialog_bytes(dial_bytes).text,
        "text_read_cap": text_read_cap,
        "dial_read_cap": dial_read_cap,
    }


def main() -> int:
    args = parse_args()
    pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name)
    with ProcessReader(pid) as reader:
        payload = snapshot_dialog_state(
            reader,
            text_read_cap=max(1, args.text_read_cap),
            dial_read_cap=max(1, args.dial_read_cap),
        )
    payload["pid"] = pid
    payload["process_name"] = args.process_name
    if args.label:
        payload["label"] = args.label

    rendered = json.dumps(payload, indent=2)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(rendered + "\n", encoding="utf-8")
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
