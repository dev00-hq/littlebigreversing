from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import threading
from pathlib import Path

def parse_int(value: str) -> int:
    return int(value, 0)


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
    parser.add_argument("--target-object", type=parse_int, default=0, help="Object index to match.")
    parser.add_argument("--target-opcode", type=parse_int, default=0x76, help="Opcode byte to match.")
    parser.add_argument("--target-offset", type=parse_int, default=46, help="PtrPrg - PtrLife offset to match.")
    parser.add_argument("--max-hits", type=parse_int, default=1, help="Stop after this many matched hits.")
    parser.add_argument(
        "--timeout-sec",
        type=float,
        default=0,
        help="Stop with an explicit failure if no matched hit arrives within this many seconds.",
    )
    parser.add_argument("--window-before", type=parse_int, default=8, help="Bytes to include before PtrPrg.")
    parser.add_argument("--window-after", type=parse_int, default=8, help="Bytes to include after PtrPrg.")
    parser.add_argument("--log-all", action="store_true", help="Emit every DoLife loop hit instead of only matches.")
    args = parser.parse_args()
    if args.max_hits < 1:
        parser.error("--max-hits must be at least 1")
    if args.timeout_sec < 0:
        parser.error("--timeout-sec must be at least 0")
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
        "logAll": args.log_all,
        "maxHits": args.max_hits,
        "targetObject": args.target_object,
        "targetOpcode": args.target_opcode,
        "targetOffset": args.target_offset,
        "windowBefore": args.window_before,
        "windowAfter": args.window_after,
    }
    template = (Path(__file__).with_name("agent.js")).read_text(encoding="utf-8")
    return template.replace("__TRACE_CONFIG__", json.dumps(config, separators=(",", ":")))


def find_process(device, process_name: str):
    target = process_name.lower()
    for process in device.enumerate_processes():
        if process.name.lower() == target:
            return process
    raise RuntimeError(f"process not found: {process_name}")


def main() -> int:
    args = parse_args()
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    output_handle = output_path.open("w", encoding="utf-8", newline="\n")
    stop_requested = threading.Event()
    error_message: list[str] = []
    matched_hits = 0
    timed_out = False

    repo_root = Path(args.frida_repo_root).resolve()
    frida_root, site_packages, frida_lib = ensure_staged_frida(repo_root)

    import frida

    device = frida.get_local_device()
    session = None
    script = None
    spawned_pid: int | None = None

    def write_event(event: dict) -> None:
        nonlocal matched_hits
        line = json.dumps(event, ensure_ascii=True, sort_keys=True)
        output_handle.write(f"{line}\n")
        output_handle.flush()
        sys.stdout.write(f"{line}\n")
        sys.stdout.flush()

        if event.get("kind") == "trace" and event.get("matches_target"):
            matched_hits += 1
            if matched_hits >= args.max_hits:
                stop_requested.set()

    def on_message(message: dict, data) -> None:
        payload = message.get("payload") or {}

        if message.get("type") == "send":
            event = dict(payload)
            nested_payload = event.pop("payload", None)
            if isinstance(nested_payload, dict):
                event.update(nested_payload)
            write_event(event)
            return

        if message.get("type") == "error":
            description = message.get("description") or "unknown script error"
            error_message.append(description)
            write_event(
                {
                    "kind": "error",
                    "description": description,
                    "stack": message.get("stack"),
                }
            )
            stop_requested.set()

    def handle_interrupt(signum, frame) -> None:
        stop_requested.set()

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

        session = device.attach(pid)
        script = session.create_script(load_agent_source(args))
        script.on("message", on_message)
        script.load()

        write_event(
            {
                "kind": "status",
                "frida_module": getattr(frida, "__file__", None),
                "frida_repo_root": str(repo_root),
                "frida_root": str(frida_root),
                "frida_site_packages": str(site_packages),
                "frida_lib": str(frida_lib),
                "message": "attached",
                "output_path": str(output_path),
                "pid": pid,
                "process_name": args.process,
                "launch_path": args.launch,
            }
        )

        if spawned_pid is not None:
            device.resume(spawned_pid)
            write_event(
                {
                    "kind": "status",
                    "message": "resumed spawned process",
                    "pid": spawned_pid,
                }
            )

        if args.timeout_sec > 0:
            if not stop_requested.wait(args.timeout_sec):
                timed_out = True
                description = f"timed out without a matched hit after {args.timeout_sec:g} seconds"
                write_event(
                    {
                        "kind": "status",
                        "matched_hits": matched_hits,
                        "message": description,
                        "timed_out": True,
                    }
                )
                error_message.append(description)
        else:
            stop_requested.wait()
    except Exception as error:  # noqa: BLE001
        error_message.append(str(error))
        write_event(
            {
                "kind": "error",
                "description": str(error),
                "stack": None,
            }
        )
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
                write_event(
                    {
                        "kind": "status",
                        "message": "leaving spawned process alive",
                        "pid": spawned_pid,
                    }
                )
            else:
                try:
                    device.kill(spawned_pid)
                    write_event(
                        {
                            "kind": "status",
                            "message": "killed spawned process",
                            "pid": spawned_pid,
                        }
                    )
                except Exception:  # noqa: BLE001
                    pass

        output_handle.close()

    if error_message:
        print(error_message[-1], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
