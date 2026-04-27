from __future__ import annotations

import argparse
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from life_trace_debugger import resolve_cdb_path
from secret_room_door_watch import CLOVER_COUNTER, FLAG_CLOVER, LIST_VAR_GAME_GLOBAL, LIST_VAR_GAME_SLOT_SIZE


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CAPTURE_ROOT = REPO_ROOT / "work" / "life_trace"


def parse_address(text: str) -> int:
    return int(text, 0)


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def build_cdb_commands(address: int = CLOVER_COUNTER, size: int = LIST_VAR_GAME_SLOT_SIZE) -> str:
    return "\n".join(
        [
            ".effmach x86",
            f".printf \"CDB_LIFE_LOSS_WATCH_ARMED address=0x{address:08x} size={size} flag_clover={FLAG_CLOVER}\\n\"",
            f'ba w{size} {address:08x} "r; ln @eip; u @eip L12; dw {address:08x} L1; kb 20; qd"',
            "g",
            "",
        ]
    )


def start_capture(args: argparse.Namespace) -> dict[str, Any]:
    cdb_path = resolve_cdb_path(args.cdb_path)
    capture_id = args.capture_id or f"life-loss-clover-watch-{args.pid}-{utc_stamp()}"
    capture_dir = Path(args.capture_root) / capture_id
    capture_dir.mkdir(parents=True, exist_ok=True)

    command_path = capture_dir / "cdb-commands.txt"
    log_path = capture_dir / "cdb.log"
    state_path = capture_dir / "state.json"
    command_path.write_text(build_cdb_commands(args.address, args.size), encoding="ascii")

    process = subprocess.Popen(
        [
            str(cdb_path),
            "-pd",
            "-logo",
            str(log_path),
            "-p",
            str(args.pid),
            "-cf",
            str(command_path),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=str(cdb_path.parent),
        creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
    )
    time.sleep(max(0.1, args.startup_wait_sec))

    state = {
        "capture_id": capture_id,
        "capture_dir": str(capture_dir),
        "pid": args.pid,
        "cdb_pid": process.pid,
        "cdb_path": str(cdb_path),
        "command_path": str(command_path),
        "log_path": str(log_path),
        "address": args.address,
        "size": args.size,
        "source_contract": {
            "counter": "ListVarGame[FLAG_CLOVER]",
            "list_var_game_global": f"0x{LIST_VAR_GAME_GLOBAL:08x}",
            "flag_clover": FLAG_CLOVER,
            "slot_size": LIST_VAR_GAME_SLOT_SIZE,
            "life_loss_path": "PERSO.CPP calls UseOneClover() when hero LifePoint reaches zero; OBJECT.CPP decrements ListVarGame[FLAG_CLOVER].",
        },
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "process_returncode_after_startup": process.poll(),
    }
    state_path.write_text(json.dumps(state, indent=2), encoding="utf-8")
    state["state_path"] = str(state_path)
    return state


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    data = path.read_bytes()
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16", errors="replace")
    return data.decode("utf-8", errors="replace")


def process_is_running(pid: int) -> bool:
    completed = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    return str(pid) in completed.stdout


def inspect_capture(args: argparse.Namespace) -> dict[str, Any]:
    capture_dir = Path(args.capture)
    if capture_dir.is_file():
        state_path = capture_dir
        capture_dir = state_path.parent
    else:
        state_path = capture_dir / "state.json"
    state = json.loads(state_path.read_text(encoding="utf-8"))
    log_path = Path(state["log_path"])
    log_text = read_text(log_path)
    cdb_pid = int(state["cdb_pid"])
    still_running = process_is_running(cdb_pid)

    malformed = "Malformed string" in log_text
    armed = "CDB_LIFE_LOSS_WATCH_ARMED" in log_text
    hit = ("Breakpoint 0 hit" in log_text) or ("ba w" in log_text and "eax=" in log_text and not still_running)
    claim_kind = "observed-life-loss-stack" if hit else "watch-armed-waiting" if still_running and armed else "watch-ended-no-hit"
    if malformed:
        claim_kind = "invalid-watch-command"
    if not armed and not malformed:
        claim_kind = "watch-not-armed"

    summary = {
        "capture_dir": str(capture_dir),
        "state_path": str(state_path),
        "log_path": str(log_path),
        "cdb_pid": cdb_pid,
        "cdb_still_running": still_running,
        "armed": armed,
        "hit": hit,
        "malformed": malformed,
        "claim": {
            "kind": claim_kind,
            "certainty": "observed" if hit else "none" if malformed or not armed else "pending",
            "text": (
                "CDB hardware write breakpoint hit ListVarGame[FLAG_CLOVER]; cdb.log contains registers, disassembly, and kb stack."
                if hit
                else "CDB watch is armed and waiting for a clover/life-loss write."
                if still_running and armed
                else "CDB watch ended without an observed clover/life-loss write."
            ),
        },
    }
    (capture_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Arm or inspect a CDB stack watch for LBA2 life-loss clover consumption.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start = subparsers.add_parser("start")
    start.add_argument("--pid", type=int, required=True)
    start.add_argument("--address", type=parse_address, default=CLOVER_COUNTER)
    start.add_argument("--size", type=int, choices=(1, 2, 4, 8), default=LIST_VAR_GAME_SLOT_SIZE)
    start.add_argument("--capture-id")
    start.add_argument("--capture-root", default=str(DEFAULT_CAPTURE_ROOT))
    start.add_argument("--cdb-path")
    start.add_argument("--startup-wait-sec", type=float, default=1.5)

    inspect = subparsers.add_parser("inspect")
    inspect.add_argument("capture")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "start":
        payload = start_capture(args)
    elif args.command == "inspect":
        payload = inspect_capture(args)
    else:  # pragma: no cover
        raise AssertionError(args.command)
    print(json.dumps(payload, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
