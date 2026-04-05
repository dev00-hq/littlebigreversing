from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Read only new bytes from a CDB server log.")
    parser.add_argument("--log", required=True, help="Path to the CDB log file.")
    parser.add_argument("--cursor", required=True, help="Path to the cursor file.")
    return parser.parse_args()


def read_cursor(path: Path) -> int:
    if not path.exists():
        return 0

    raw = path.read_text(encoding="ascii").strip()
    if not raw:
        return 0

    try:
        return int(raw)
    except ValueError:
        return 0


def detect_encoding(raw: bytes) -> str:
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        return "utf-16"
    return "ascii"


def main() -> int:
    args = parse_args()
    log_path = Path(args.log).resolve()
    cursor_path = Path(args.cursor).resolve()

    if not log_path.exists():
        raise SystemExit(f"log file does not exist: {log_path}")

    total_size = log_path.stat().st_size
    offset = read_cursor(cursor_path)
    if offset < 0 or offset > total_size:
        offset = 0

    with log_path.open("rb") as handle:
        handle.seek(offset)
        new_bytes = handle.read()

    if not new_bytes:
        cursor_path.parent.mkdir(parents=True, exist_ok=True)
        cursor_path.write_text(str(total_size), encoding="ascii")
        return 0

    encoding = detect_encoding(new_bytes if offset == 0 else log_path.read_bytes()[:2])
    text = new_bytes.decode(encoding, errors="replace")
    print(text, end="")

    cursor_path.parent.mkdir(parents=True, exist_ok=True)
    cursor_path.write_text(str(total_size), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
