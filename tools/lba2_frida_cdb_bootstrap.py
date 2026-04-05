from __future__ import annotations

import argparse
import csv
import json
import os
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGET = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "LBA2.EXE"
DEFAULT_FRIDA_REPO = Path(r"D:\repos\reverse\frida")
DEFAULT_LOG_DIR = REPO_ROOT / "work" / "windbg"
WAIT_FOR_CDB_SECONDS = 3.0
FRIDA_PROBE_TIMEOUT = 10.0
POST_FRIDA_SETTLE_SECONDS = 1.5


class BootstrapError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Launch original Windows LBA2 with staged Frida, verify a Frida attach, "
            "and bootstrap a detached CDB remote server ready for WinDbg MCP."
        )
    )
    parser.add_argument(
        "--target",
        default=str(DEFAULT_TARGET),
        help="Path to the Windows LBA2.EXE to launch or attach to.",
    )
    parser.add_argument(
        "--frida-repo-root",
        default=str(DEFAULT_FRIDA_REPO),
        help="Frida repository root containing build/install-root/Program Files/Frida.",
    )
    parser.add_argument(
        "--attach-existing-pid",
        type=int,
        help="Skip launch and verify a Frida attach against an already-running LBA2 PID.",
    )
    parser.add_argument(
        "--cdb-path",
        help="Explicit path to cdb.exe. Defaults to PATH/common debugger locations/WinDbg app install.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="Remote CDB port. Use 0 to auto-pick a free localhost port.",
    )
    parser.add_argument(
        "--password",
        default="",
        help="Remote CDB password. Defaults to a random short token.",
    )
    parser.add_argument(
        "--log",
        help="Path to the CDB server log. Defaults under work/windbg/.",
    )
    parser.add_argument(
        "--result-file",
        help="Path to write the final bootstrap result JSON. Defaults beside the log file.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the final result as JSON instead of key=value lines.",
    )
    parser.add_argument(
        "--post-frida-settle-seconds",
        type=float,
        default=POST_FRIDA_SETTLE_SECONDS,
        help="Seconds to wait after Frida resume/detach before attaching cdb.",
    )
    return parser.parse_args()


def emit(text: str) -> None:
    print(text, flush=True)


def ensure_file_exists(path: Path, label: str) -> None:
    if not path.exists():
        raise BootstrapError(f"{label} does not exist: {path}")


def find_running_image_pids(image_name: str) -> list[int]:
    result = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=True,
    )
    pids: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("INFO:"):
            continue
        row = next(csv.reader([line]))
        if len(row) < 2:
            continue
        try:
            pids.append(int(row[1]))
        except ValueError:
            continue
    return pids


def ensure_staged_frida(repo_root: Path) -> tuple[Path, Path]:
    frida_root = repo_root / "build" / "install-root" / "Program Files" / "Frida"
    site_packages = frida_root / "lib" / "site-packages"
    frida_bin = frida_root / "bin"
    frida_lib = frida_root / "lib" / "frida" / "x86_64"

    missing = [path for path in (frida_root, site_packages, frida_bin, frida_lib) if not path.exists()]
    if missing:
        joined = "\n".join(str(path) for path in missing)
        raise BootstrapError(
            "Missing staged Frida paths:\n"
            f"{joined}\n"
            "Build and install the local Frida repo before running this bootstrap."
        )

    sys.path.insert(0, str(site_packages))
    os.environ["PYTHONPATH"] = str(site_packages)
    os.environ["PATH"] = os.pathsep.join([str(frida_bin), str(frida_lib), os.environ.get("PATH", "")])
    return frida_root, site_packages


def import_frida(repo_root: Path) -> tuple[Any, Path, Path]:
    frida_root, site_packages = ensure_staged_frida(repo_root)
    import frida  # type: ignore

    return frida, frida_root, site_packages


def verify_frida_attach(frida: Any, pid: int, timeout_seconds: float) -> dict[str, Any]:
    session = None
    script = None
    message_event = threading.Event()
    state: dict[str, Any] = {"message": None}

    try:
        session = frida.attach(pid)
        script = session.create_script(
            """
            send({
              pid: Process.id,
              arch: Process.arch,
              platform: Process.platform,
              mainModule: Process.mainModule !== null ? Process.mainModule.name : null
            });
            """
        )

        def on_message(message: Any, data: Any) -> None:
            state["message"] = message
            message_event.set()

        script.on("message", on_message)
        script.load()

        if not message_event.wait(timeout_seconds):
            raise BootstrapError(
                f"Timed out after {timeout_seconds:.1f}s waiting for the Frida probe message on PID {pid}."
            )

        message = state["message"]
        payload = message.get("payload") if isinstance(message, dict) else None
        if not isinstance(payload, dict):
            raise BootstrapError(f"Unexpected Frida message payload on PID {pid}: {message!r}")

        return payload
    finally:
        if script is not None:
            try:
                script.unload()
            except Exception:
                pass
        if session is not None:
            try:
                session.detach()
            except Exception:
                pass


def launch_with_frida(frida: Any, target: Path, timeout_seconds: float) -> tuple[int, dict[str, Any]]:
    pid = None
    left_running = False
    try:
        pid = frida.spawn([str(target)])
        payload = verify_frida_attach(frida, pid, timeout_seconds)
        frida.resume(pid)
        left_running = True
        return pid, payload
    except Exception:
        if pid is not None and not left_running:
            try:
                frida.kill(pid)
            except Exception:
                pass
        raise


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def resolve_cdb_path(explicit_path: str | None) -> Path:
    candidates: list[Path] = []
    if explicit_path:
        candidates.append(Path(explicit_path))

    which = shutil.which("cdb.exe") or shutil.which("cdb")
    if which:
        candidates.append(Path(which))

    candidates.extend(
        [
            Path(r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"),
            Path(r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x86\cdb.exe"),
            Path(r"C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe"),
            Path(r"C:\Program Files\Windows Kits\10\Debuggers\x86\cdb.exe"),
        ]
    )

    windows_apps = Path(r"C:\Program Files\WindowsApps")
    if windows_apps.exists():
        for install_dir in sorted(windows_apps.glob("Microsoft.WinDbg_*"), reverse=True):
            candidates.extend(
                [
                    install_dir / "amd64" / "cdb.exe",
                    install_dir / "x86" / "cdb.exe",
                    install_dir / "arm64" / "cdb.exe",
                ]
            )

    seen: set[str] = set()
    for candidate in candidates:
        candidate_text = str(candidate)
        if candidate_text in seen:
            continue
        seen.add(candidate_text)
        if candidate.exists():
            return candidate

    raise BootstrapError(
        "Unable to find cdb.exe. Put it on PATH, pass --cdb-path, or install WinDbg/Debugging Tools."
    )


def read_log_tail(log_path: Path, max_chars: int = 1200) -> str:
    if not log_path.exists():
        return ""

    data = log_path.read_bytes()
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        text = data.decode("utf-16", errors="replace")
    else:
        text = data.decode("ascii", errors="replace")
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def start_cdb_server(cdb_path: Path, target_pid: int, port: int, password: str, log_path: Path) -> subprocess.Popen[Any]:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    if log_path.exists():
        last_error: Exception | None = None
        for _ in range(10):
            try:
                log_path.unlink()
                last_error = None
                break
            except PermissionError as exc:
                last_error = exc
                time.sleep(0.2)
        if last_error is not None:
            raise BootstrapError(
                f"Unable to remove existing log file because it is still locked: {log_path}\n"
                "Wait a moment for the previous cdb process to release it, or use a different --log path."
            ) from last_error

    args = [
        str(cdb_path),
        "-server",
        f"tcp:port={port},password={password}",
        "-logo",
        str(log_path),
        "-p",
        str(target_pid),
    ]

    creationflags = 0
    creationflags |= getattr(subprocess, "DETACHED_PROCESS", 0)
    creationflags |= getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    creationflags |= getattr(subprocess, "CREATE_BREAKAWAY_FROM_JOB", 0)

    process = subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=creationflags,
        cwd=str(cdb_path.parent),
    )

    time.sleep(WAIT_FOR_CDB_SECONDS)
    if process.poll() is not None:
        tail = read_log_tail(log_path)
        details = f"CDB exited with code {process.returncode}."
        if tail:
            details += f"\nLog tail:\n{tail}"
        raise BootstrapError(details)

    return process


def main() -> int:
    args = parse_args()

    target = Path(args.target).resolve()
    frida_repo_root = Path(args.frida_repo_root).resolve()
    log_path = Path(args.log).resolve() if args.log else (DEFAULT_LOG_DIR / "frida-cdb-bootstrap.log").resolve()
    result_path = Path(args.result_file).resolve() if args.result_file else log_path.with_suffix(".json")
    ensure_file_exists(target, "Target executable")
    ensure_file_exists(frida_repo_root, "Frida repo root")

    if args.attach_existing_pid is None:
        existing_pids = find_running_image_pids(target.name)
        if existing_pids:
            joined = ", ".join(str(pid) for pid in existing_pids)
            raise BootstrapError(
                f"{target.name} is already running on PID(s): {joined}\n"
                "Close the existing game first, or rerun with --attach-existing-pid <pid>."
            )

    port = args.port if args.port != 0 else find_free_port()
    password = args.password or secrets.token_hex(4)
    cdb_path = resolve_cdb_path(args.cdb_path)
    frida, frida_root, site_packages = import_frida(frida_repo_root)

    launch_mode = "attach-existing" if args.attach_existing_pid else "spawn"
    if args.attach_existing_pid:
        target_pid = int(args.attach_existing_pid)
        frida_payload = verify_frida_attach(frida, target_pid, FRIDA_PROBE_TIMEOUT)
    else:
        target_pid, frida_payload = launch_with_frida(frida, target, FRIDA_PROBE_TIMEOUT)

    if args.post_frida_settle_seconds > 0:
        time.sleep(args.post_frida_settle_seconds)

    cdb_process = start_cdb_server(cdb_path, target_pid, port, password, log_path)
    connection_string = f"tcp:Port={port},Server=127.0.0.1,Password={password}"

    result = {
        "launch_mode": launch_mode,
        "target": str(target),
        "target_pid": target_pid,
        "frida_module": getattr(frida, "__file__", None),
        "frida_version": getattr(frida, "__version__", None),
        "frida_repo_root": str(frida_repo_root),
        "frida_root": str(frida_root),
        "frida_site_packages": str(site_packages),
        "frida_probe": frida_payload,
        "cdb_path": str(cdb_path),
        "cdb_pid": cdb_process.pid,
        "log_path": str(log_path),
        "connection_string": connection_string,
        "mcp_open_hint": f'open_windbg_remote(connection_string="{connection_string}")',
    }

    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    if args.json:
        print(json.dumps(result, indent=2), flush=True)
    else:
        for key, value in result.items():
            if isinstance(value, dict):
                print(f"{key}={json.dumps(value, sort_keys=True)}", flush=True)
            else:
                print(f"{key}={value}", flush=True)
        print(f"result_file={result_path}", flush=True)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BootstrapError as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
