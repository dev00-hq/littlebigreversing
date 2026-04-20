from __future__ import annotations

import argparse
import ctypes
import json
import msgspec
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from ctypes import wintypes
from pathlib import Path

from life_trace_shared import (
    AgentErrorEvent,
    AgentTraceEvent,
    AgentWireEventType,
    FraProbeRuntime,
    JsonlWriter,
    PersistedErrorEvent,
    PersistedStatusEvent,
    REPO_ROOT,
    SPAWNED_PROCESS_TERMINATE_GRACE_SEC,
    SPAWNED_PROCESS_TERMINATE_POLL_SEC,
    build_trace_config,
    normalize_script_message,
)
from life_trace_windows import WindowCapture
from scenes.load_game import direct_launch_argv
from scenes.base import StructuredSceneController
from scenes.registry import get_structured_scene_spec


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

    def handle_event(self, event: AgentWireEventType) -> None:
        self.writer.write_event(event)
        if isinstance(event, AgentTraceEvent) and event.matches_target:
            self.matched_hits += 1
            if self.matched_hits >= self.args.max_hits:
                self.terminal = True
        elif isinstance(event, AgentErrorEvent):
            self.last_error = event.description or "unknown error"
            self.exit_code = 1
            self.terminal = True

    def handle_timeout(self) -> None:
        description = f"timed out without a matched hit after {self.args.timeout_sec:g} seconds"
        self.writer.write_event(
            PersistedStatusEvent(
                message=description,
                matched_hits=self.matched_hits,
                timed_out=True,
            )
        )
        self.last_error = description
        self.exit_code = 1
        self.terminal = True

    def handle_interrupt(self) -> None:
        self.writer.write_event(
            PersistedStatusEvent(
                message="interrupted",
                matched_hits=self.matched_hits,
            )
        )
        self.last_error = "interrupted"
        self.exit_code = 1
        self.terminal = True

    def handle_process_exit(self, reason: str) -> None:
        self.last_error = reason
        self.exit_code = 1
        self.terminal = True

    def handle_runtime_error(self, reason: str) -> None:
        self.last_error = reason
        self.exit_code = 1
        self.terminal = True

    def next_deadline(self) -> float | None:
        return None

    def poll(self, now: float) -> None:
        return


OWNED_LAUNCH_PREKILL_PROCESS_NAMES = ("cdb.exe",)
TASKKILL_NOT_FOUND_MARKERS = (
    "not found",
    "no se encontr",
    "no tasks are running",
    "no hay tareas en ejec",
)


def resolve_launch_save_path(launch_save: str | None) -> Path | None:
    if launch_save is None:
        return None
    launch_save_path = Path(launch_save)
    if not launch_save_path.exists():
        raise RuntimeError(f"launch save path does not exist: {launch_save_path}")
    return launch_save_path


def build_owned_launch_argv(launch_path: Path, launch_save: str | None) -> list[str]:
    launch_save_path = resolve_launch_save_path(launch_save)
    if launch_save_path is None:
        return [str(launch_path)]
    return direct_launch_argv(launch_path, launch_save_path)


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
    if args.mode != "basic":
        scene_spec = get_structured_scene_spec(args.mode)
        if scene_spec.runtime_backend not in {"fra_probe", "frida_probe"}:
            raise RuntimeError(f"--mode {args.mode} does not use the Frida agent backend")

    config = build_trace_config(args)
    template_path = Path(__file__).with_name("agent.js")
    agent_root = template_path.with_name("agent")
    template = template_path.read_text(encoding="utf-8")
    fragment_names = (
        "shared.js",
        "scene_basic.js",
        "scene_tavern.js",
        "scene_scene11_live.js",
        "bootstrap.js",
    )
    fragments: dict[str, str] = {}
    for name in fragment_names:
        fragment_path = agent_root / name
        if not fragment_path.exists():
            raise RuntimeError(f"life_trace agent fragment is missing: {fragment_path}")
        fragment_text = fragment_path.read_text(encoding="utf-8")
        if not fragment_text.strip():
            raise RuntimeError(f"life_trace agent fragment is empty: {fragment_path}")
        fragments[name] = fragment_text

    replacements = {
        "__TRACE_CONFIG__": json.dumps(msgspec.to_builtins(config), separators=(",", ":")),
        "__TRACE_AGENT_SHARED__": fragments["shared.js"],
        "__TRACE_AGENT_SCENES__": "\n\n".join(
            [
                fragments["scene_basic.js"],
                fragments["scene_tavern.js"],
                fragments["scene_scene11_live.js"],
            ]
        ),
        "__TRACE_AGENT_BOOTSTRAP__": fragments["bootstrap.js"],
    }
    for placeholder, value in replacements.items():
        template = template.replace(placeholder, value)
    if "__TRACE_" in template:
        raise RuntimeError("life_trace agent assembly left an unreplaced placeholder")
    return template


def find_process(device, process_name: str):
    target = process_name.lower()
    for process in device.enumerate_processes():
        if process.name.lower() == target:
            return process
    raise RuntimeError(f"process not found: {process_name}")


def process_exists(device, pid: int) -> bool:
    try:
        return any(process.pid == pid for process in device.enumerate_processes())
    except Exception:
        return False


def process_exists_pid(pid: int) -> bool:
    process_query_limited_information = 0x1000
    still_active = 259
    kernel32 = ctypes.windll.kernel32
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.GetExitCodeProcess.restype = wintypes.BOOL
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL
    handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
    if handle == 0:
        return False
    try:
        exit_code = wintypes.DWORD(0)
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
            return False
        return exit_code.value == still_active
    finally:
        kernel32.CloseHandle(handle)


def preflight_owned_launch_processes(
    writer: JsonlWriter,
    process_name: str,
    *,
    extra_process_names: tuple[str, ...] = OWNED_LAUNCH_PREKILL_PROCESS_NAMES,
) -> None:
    targets: list[str] = []
    for candidate in (process_name, *extra_process_names):
        normalized = candidate.strip()
        if not normalized:
            continue
        if normalized.lower() in {name.lower() for name in targets}:
            continue
        targets.append(normalized)

    for target in targets:
        completed = subprocess.run(
            ["taskkill", "/IM", target, "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode == 0:
            writer.write_event(
                PersistedStatusEvent(
                    message=f"preflight killed existing {target}",
                )
            )
            continue

        detail = f"{completed.stdout or ''}\n{completed.stderr or ''}".strip().lower()
        if any(marker in detail for marker in TASKKILL_NOT_FOUND_MARKERS):
            continue

        raise RuntimeError(
            f"preflight taskkill failed for {target} ({completed.returncode}): "
            f"{(completed.stderr or completed.stdout).strip() or '<no output>'}"
        )


def application_error_dialog_title(
    pid: int,
    *,
    capture: WindowCapture | None = None,
    process_name: str | None = None,
    launch_path: str | None = None,
) -> str | None:
    active_capture = WindowCapture() if capture is None else capture
    try:
        window = active_capture.find_window(pid)
    except Exception:
        window = None
    if window is not None and "application error" in window.title.lower():
        return window.title

    fragments = ["application error"]
    if process_name:
        fragments.append(process_name.lower())
    if launch_path:
        fragments.append(Path(launch_path).name.lower())
    try:
        matched = active_capture.find_window_title_fragments(*fragments)
    except Exception:
        return None
    title = None if matched is None else getattr(matched, "title", None)
    if not isinstance(title, str) or not title:
        return None
    return title


def detect_application_error_dialog(
    writer: JsonlWriter,
    pid: int,
    *,
    capture: WindowCapture | None = None,
    process_name: str | None = None,
    launch_path: str | None = None,
) -> str | None:
    title = application_error_dialog_title(
        pid,
        capture=capture,
        process_name=process_name,
        launch_path=launch_path,
    )
    if title is None:
        return None
    writer.write_event(
        PersistedStatusEvent(
            message=f"detected Application Error dialog: {title}",
            pid=pid,
        )
    )
    return title


def wait_for_process_exit(pid: int, timeout_sec: float, poll_sec: float = SPAWNED_PROCESS_TERMINATE_POLL_SEC) -> bool:
    deadline = time.monotonic() + max(0.0, timeout_sec)
    while time.monotonic() < deadline:
        if not process_exists_pid(pid):
            return True
        time.sleep(max(0.01, poll_sec))
    return not process_exists_pid(pid)


def terminate_spawned_process(
    writer: JsonlWriter,
    fra_launcher: list[str],
    target_id: str,
    pid: int,
) -> None:
    fra_terminate_failed = False
    try:
        run_fra_json(
            fra_launcher,
            "target",
            "terminate",
            "--target",
            target_id,
            "--format",
            "json",
        )
    except Exception as error:
        fra_terminate_failed = True
        writer.write_event(
            PersistedStatusEvent(
                message=f"fra target terminate failed; falling back to direct kill: {error}",
                pid=pid,
            )
        )

    if wait_for_process_exit(pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
        writer.write_event(
            PersistedStatusEvent(
                message="killed spawned process",
                pid=pid,
            )
        )
        return

    writer.write_event(
        PersistedStatusEvent(
            message=(
                "spawned process still alive after fra target terminate; forcing direct kill"
                if not fra_terminate_failed
                else "spawned process still alive after fra terminate failure; forcing direct kill"
            ),
            pid=pid,
        )
    )

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        writer.write_event(
            PersistedStatusEvent(
                message="spawned process exited before direct kill",
                pid=pid,
            )
        )
        return
    except Exception as error:
        writer.write_event(
            PersistedStatusEvent(
                message=f"direct kill failed: {error}",
                pid=pid,
            )
        )
        return

    if wait_for_process_exit(pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
        writer.write_event(
            PersistedStatusEvent(
                message="force-killed spawned process",
                pid=pid,
            )
        )
        return

    writer.write_event(
        PersistedStatusEvent(
            message="spawned process still alive after direct kill",
            pid=pid,
        )
    )


def resolve_fra_launcher(repo_root: Path) -> list[str]:
    python_exe = repo_root / ".venv" / "Scripts" / "python.exe"
    if not python_exe.exists():
        raise RuntimeError(
            "missing fra launcher: "
            f"{python_exe}\n"
            "build or restore the frida-agent-cli virtual environment first"
        )
    return [str(python_exe), "-m", "fra"]


def run_fra_json(
    fra_launcher: list[str],
    *fra_args: str,
    input_text: str | None = None,
) -> dict | list:
    completed = subprocess.run(
        [*fra_launcher, *fra_args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        input=input_text,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or "<no output>"
        raise RuntimeError(
            f"fra command failed ({completed.returncode}): {' '.join(fra_args)}\n{detail}"
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"fra command returned invalid JSON: {' '.join(fra_args)}"
        ) from exc


def resolve_fra_output_payload(payload: object) -> object:
    if not isinstance(payload, dict) or "artifact_path" not in payload:
        return payload

    artifact_path = payload.get("artifact_path")
    artifact_format = payload.get("format")
    if not isinstance(artifact_path, str) or not artifact_path:
        raise RuntimeError("fra output artifact envelope is missing artifact_path")
    if artifact_format not in {"json", "ndjson", "text"}:
        raise RuntimeError(f"fra output artifact envelope has unsupported format: {artifact_format!r}")

    artifact_file = Path(artifact_path)
    if not artifact_file.exists():
        raise RuntimeError(f"fra output artifact path does not exist: {artifact_file}")
    text = artifact_file.read_text(encoding="utf-8")

    if artifact_format == "json":
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"fra output artifact is not valid JSON: {artifact_file}") from exc
    if artifact_format == "ndjson":
        records: list[object] = []
        for line in text.splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            try:
                records.append(json.loads(stripped))
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"fra output artifact is not valid NDJSON: {artifact_file}") from exc
        return records
    return text


def fra_status_fields(doctor_report: dict) -> dict[str, str | None]:
    if not doctor_report.get("ok"):
        failing_checks = [
            f"{check.get('name')}: {check.get('detail')}"
            for check in doctor_report.get("checks", [])
            if isinstance(check, dict) and not check.get("ok")
        ]
        details = "\n".join(failing_checks) if failing_checks else json.dumps(doctor_report, indent=2)
        raise RuntimeError(f"fra doctor failed:\n{details}")

    bootstrap = doctor_report.get("bootstrap") if isinstance(doctor_report.get("bootstrap"), dict) else {}
    paths = bootstrap.get("paths") if isinstance(bootstrap.get("paths"), dict) else {}
    frida = doctor_report.get("frida") if isinstance(doctor_report.get("frida"), dict) else {}
    return {
        "frida_module": frida.get("module_path"),
        "frida_repo_root": paths.get("repo_root"),
        "frida_root": paths.get("staged_root"),
        "frida_site_packages": paths.get("site_packages"),
        "frida_lib": paths.get("dll_dir"),
    }


def read_fra_probe_records(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
) -> list[dict]:
    payload = resolve_fra_output_payload(
        run_fra_json(
            fra_launcher,
            "probe",
            "tail",
            "--artifact",
            str(runtime.artifact_path),
            "--format",
            "json",
        )
    )
    if not isinstance(payload, list):
        raise RuntimeError("fra probe tail returned an unexpected payload")
    if runtime.consumed_records > len(payload):
        raise RuntimeError("fra probe tail returned fewer records than the tracer already consumed")

    new_records = payload[runtime.consumed_records :]
    runtime.consumed_records = len(payload)

    normalized: list[dict] = []
    for record in new_records:
        if not isinstance(record, dict):
            raise RuntimeError("fra probe tail returned a non-dict record")
        normalized.append(record)
    return normalized


def queue_fra_probe_messages(
    runtime: FraProbeRuntime,
    records: list[dict],
    message_queue: queue.Queue[AgentWireEventType],
) -> None:
    for record in records:
        if record.get("kind") != "probe_message":
            continue
        message = record.get("message")
        if not isinstance(message, dict):
            raise RuntimeError("fra probe tail returned a non-dict message")
        event = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)


def try_wait_for_fra_probe_lifecycle(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
    event: str,
) -> dict | None:
    completed = subprocess.run(
        [
            *fra_launcher,
            "probe",
            "wait",
            "--artifact",
            str(runtime.artifact_path),
            "--lifecycle-event",
            event,
            "--timeout",
            "0",
            "--format",
            "json",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode == 0:
        try:
            payload = resolve_fra_output_payload(json.loads(completed.stdout))
        except json.JSONDecodeError as exc:
            raise RuntimeError(
                f"fra probe wait returned invalid JSON for lifecycle {event}"
            ) from exc
        if not isinstance(payload, dict):
            raise RuntimeError("fra probe wait returned an unexpected payload")
        return payload

    detail = (completed.stderr or completed.stdout).strip()
    if "timed out waiting for a matching probe artifact record" in detail:
        return None
    raise RuntimeError(
        f"fra probe wait failed ({completed.returncode}) for lifecycle {event}: {detail or '<no output>'}"
    )


def refresh_fra_probe_terminal_state(
    fra_launcher: list[str],
    runtime: FraProbeRuntime,
) -> None:
    if runtime.terminal_event is not None:
        return

    for event in ("terminated", "detached", "removed"):
        record = try_wait_for_fra_probe_lifecycle(fra_launcher, runtime, event)
        if record is None:
            continue
        runtime.terminal_event = event
        reason = record.get("reason")
        runtime.terminal_reason = None if reason is None else str(reason)
        return


def run_direct_frida_trace(
    args: argparse.Namespace,
    writer: JsonlWriter,
    interrupted: threading.Event,
) -> tuple[BasicTraceController | None, int | None]:
    message_queue: queue.Queue[AgentWireEventType] = queue.Queue()

    repo_root = Path(args.frida_repo_root).resolve()
    frida_root, site_packages, frida_lib = ensure_staged_frida(repo_root)

    import frida

    device = frida.get_local_device()
    session = None
    script = None
    spawned_pid: int | None = None
    controller: BasicTraceController | None = None

    def on_message(message: dict, data) -> None:
        event = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)

    try:
        if args.launch:
            preflight_owned_launch_processes(writer, args.process)
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawn_argv = build_owned_launch_argv(launch_path, args.launch_save)
            spawned_pid = device.spawn(spawn_argv, cwd=str(launch_path.parent))
            pid = spawned_pid
        else:
            process = find_process(device, args.process)
            pid = process.pid

        controller = BasicTraceController(args, writer)
        session = device.attach(pid)
        script = session.create_script(load_agent_source(args))
        script.on("message", on_message)
        script.load()

        writer.write_event(
            PersistedStatusEvent(
                frida_module=getattr(frida, "__file__", None),
                frida_repo_root=str(repo_root),
                frida_root=str(frida_root),
                frida_site_packages=str(site_packages),
                frida_lib=str(frida_lib),
                message="attached",
                mode=args.mode,
                output_path=str(writer.bundle_root),
                pid=pid,
                process_name=args.process,
                launch_path=args.launch,
                launch_save=args.launch_save,
            )
        )

        if spawned_pid is not None:
            device.resume(spawned_pid)
            writer.write_event(
                PersistedStatusEvent(
                    message="resumed spawned process",
                    pid=spawned_pid,
                )
            )

        controller.begin()

        deadline = None
        if args.timeout_sec is not None and args.timeout_sec > 0:
            deadline = time.monotonic() + args.timeout_sec

        while not controller.terminal:
            if interrupted.is_set():
                controller.handle_interrupt()
                break

            crash_title = detect_application_error_dialog(
                writer,
                pid,
                process_name=args.process,
                launch_path=args.launch,
            )
            if crash_title is not None:
                controller.handle_process_exit(f"Application Error dialog detected: {crash_title}")
                break

            if not process_exists(device, pid):
                writer.write_event(
                    PersistedStatusEvent(
                        message="target process exited",
                        pid=pid,
                    )
                )
                controller.handle_process_exit(f"process {pid} exited")
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
    except Exception as error:
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        if controller is not None and not controller.terminal:
            controller.handle_runtime_error(str(error))
        elif controller is None:
            print(str(error), file=sys.stderr)
            return None, 1
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

        if spawned_pid is not None:
            if args.keep_alive:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving spawned process alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    device.kill(spawned_pid)
                    writer.write_event(
                        PersistedStatusEvent(
                            message="killed spawned process",
                            pid=spawned_pid,
                        )
                    )
                except Exception:
                    pass

    return controller, None


def run_structured_trace_via_frida(
    args: argparse.Namespace,
    writer: JsonlWriter,
    interrupted: threading.Event,
) -> tuple[StructuredSceneController | None, int | None]:
    message_queue: queue.Queue[AgentWireEventType] = queue.Queue()
    scene_spec = get_structured_scene_spec(args.mode)

    repo_root = Path(args.frida_repo_root).resolve()
    frida_root, site_packages, frida_lib = ensure_staged_frida(repo_root)

    import frida

    device = frida.get_local_device()
    session = None
    script = None
    controller: StructuredSceneController | None = None
    spawned_pid: int | None = None
    pid: int | None = None
    launch_path: Path | None = None
    launched_process: subprocess.Popen[str] | subprocess.Popen[bytes] | None = None

    def on_message(message: dict, data) -> None:
        del data
        event = normalize_script_message(message)
        if event is not None:
            message_queue.put(event)

    try:
        if scene_spec.controller_factory is None:
            raise RuntimeError(f"--mode {args.mode} does not define a Frida controller")

        if args.launch and scene_spec.launch_strategy == "native_launch_then_attach":
            preflight_owned_launch_processes(writer, args.process)
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            launched_process = subprocess.Popen(
                build_owned_launch_argv(launch_path, args.launch_save),
                cwd=str(launch_path.parent),
            )
            pid = int(launched_process.pid)
            spawned_pid = pid
            writer.write_event(
                PersistedStatusEvent(
                    message="launched process before late Frida attach",
                    pid=pid,
                    launch_path=str(launch_path),
                )
            )
            if scene_spec.prepare_launch is not None:
                scene_spec.prepare_launch(args, writer, launch_path, pid)
        elif args.launch:
            preflight_owned_launch_processes(writer, args.process)
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawn_argv = build_owned_launch_argv(launch_path, args.launch_save)
            spawned_pid = device.spawn(spawn_argv, cwd=str(launch_path.parent))
            pid = spawned_pid
        else:
            process = find_process(device, args.process)
            pid = process.pid

        if pid is None:
            raise RuntimeError("structured Frida trace did not resolve a target pid")

        controller = scene_spec.controller_factory(args, writer, pid)
        session = device.attach(pid)
        script = session.create_script(load_agent_source(args))
        script.on("message", on_message)
        script.load()

        writer.write_event(
            PersistedStatusEvent(
                phase="attached",
                frida_module=getattr(frida, "__file__", None),
                frida_repo_root=str(repo_root),
                frida_root=str(frida_root),
                frida_site_packages=str(site_packages),
                frida_lib=str(frida_lib),
                message="attached",
                mode=args.mode,
                output_path=str(writer.bundle_root),
                pid=pid,
                process_name=args.process,
                launch_path=args.launch,
                launch_save=args.launch_save,
            )
        )

        if args.launch and scene_spec.launch_strategy != "native_launch_then_attach" and spawned_pid is not None:
            device.resume(spawned_pid)
            writer.write_event(
                PersistedStatusEvent(
                    message="resumed spawned process",
                    pid=spawned_pid,
                )
            )

        controller.begin()

        deadline = None
        if args.timeout_sec is not None and args.timeout_sec > 0:
            deadline = time.monotonic() + args.timeout_sec

        while controller is not None and not controller.terminal:
            if interrupted.is_set():
                controller.handle_interrupt()
                break

            crash_title = detect_application_error_dialog(
                writer,
                pid,
                process_name=args.process,
                launch_path=str(launch_path) if launch_path is not None else args.launch,
            )
            if crash_title is not None:
                controller.handle_process_exit(
                    f"Application Error dialog detected before the structured trace completed: {crash_title}"
                )
                break

            if not process_exists(device, pid):
                writer.write_event(
                    PersistedStatusEvent(
                        message="target process exited",
                        pid=pid,
                    )
                )
                controller.handle_process_exit(
                    f"process {pid} exited before the structured trace completed"
                )
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
    except Exception as error:
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        if controller is not None and not controller.terminal:
            controller.handle_runtime_error(str(error))
        elif controller is None:
            print(str(error), file=sys.stderr)
            return None, 1
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

        if spawned_pid is not None:
            if args.keep_alive:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving spawned process alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    if launched_process is not None:
                        launched_process.terminate()
                    else:
                        device.kill(spawned_pid)
                except ProcessLookupError:
                    writer.write_event(
                        PersistedStatusEvent(
                            message="spawned process exited before direct kill",
                            pid=spawned_pid,
                        )
                    )
                except PermissionError:
                    if process_exists_pid(spawned_pid):
                        try:
                            if launched_process is not None:
                                launched_process.kill()
                            else:
                                raise
                        except Exception:
                            pass
                    else:
                        writer.write_event(
                            PersistedStatusEvent(
                                message="spawned process exited before direct kill",
                                pid=spawned_pid,
                            )
                        )
                except Exception:
                    pass
                else:
                    if wait_for_process_exit(spawned_pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
                        writer.write_event(
                            PersistedStatusEvent(
                                message="killed spawned process",
                                pid=spawned_pid,
                            )
                        )
                    elif launched_process is not None:
                        try:
                            launched_process.kill()
                        except Exception:
                            pass
                        if wait_for_process_exit(spawned_pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
                            writer.write_event(
                                PersistedStatusEvent(
                                    message="force-killed spawned process",
                                    pid=spawned_pid,
                                )
                            )
                        else:
                            writer.write_event(
                                PersistedStatusEvent(
                                    message="spawned process still alive after direct kill",
                                    pid=spawned_pid,
                                )
                            )

        if launch_path is not None and scene_spec.cleanup_launch is not None:
            if args.keep_alive and spawned_pid is not None:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving staged load-game save in place because the spawned process is still alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    scene_spec.cleanup_launch(args, writer, launch_path)
                except Exception as error:
                    writer.write_event(
                        PersistedErrorEvent(
                            description=f"launch cleanup failed: {error}",
                            stack=None,
                        )
                    )

    return controller, None


def run_structured_trace_via_fra(
    args: argparse.Namespace,
    writer: JsonlWriter,
    interrupted: threading.Event,
) -> tuple[StructuredSceneController | None, int | None]:
    message_queue: queue.Queue[AgentWireEventType] = queue.Queue()
    scene_spec = get_structured_scene_spec(args.mode)

    fra_repo_root = Path(args.fra_repo_root).resolve()
    fra_launcher = resolve_fra_launcher(fra_repo_root)
    doctor_report = run_fra_json(fra_launcher, "doctor", "--format", "json")
    status_fields = fra_status_fields(doctor_report if isinstance(doctor_report, dict) else {})

    target_id: str | None = None
    probe_runtime: FraProbeRuntime | None = None
    controller: StructuredSceneController | None = None
    spawned_pid: int | None = None
    pid: int | None = None
    fra_spawned_target = False
    launch_path: Path | None = None

    try:
        if scene_spec.controller_factory is None:
            raise RuntimeError(f"--mode {args.mode} does not define an FRA controller")

        if args.launch and scene_spec.launch_strategy == "native_launch_then_attach":
            preflight_owned_launch_processes(writer, args.process)
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            launched_process = subprocess.Popen(
                build_owned_launch_argv(launch_path, args.launch_save),
                cwd=str(launch_path.parent),
            )
            pid = int(launched_process.pid)
            spawned_pid = pid
            writer.write_event(
                PersistedStatusEvent(
                    message="launched process before late fra attach",
                    pid=pid,
                    launch_path=str(launch_path),
                )
            )
            if scene_spec.prepare_launch is not None:
                scene_spec.prepare_launch(args, writer, launch_path, pid)
            target_record = run_fra_json(
                fra_launcher,
                "target",
                "attach",
                "--format",
                "json",
                str(pid),
            )
        elif args.launch:
            preflight_owned_launch_processes(writer, args.process)
            launch_path = Path(args.launch)
            if not launch_path.exists():
                raise RuntimeError(f"launch path does not exist: {launch_path}")
            spawn_args = [
                "target",
                "spawn",
                "--format",
                "json",
                "--cwd",
                str(launch_path.parent),
            ]
            spawn_args.extend(build_owned_launch_argv(launch_path, args.launch_save))
            target_record = run_fra_json(fra_launcher, *spawn_args)
            fra_spawned_target = True
        else:
            target_record = run_fra_json(
                fra_launcher,
                "target",
                "attach",
                "--format",
                "json",
                args.process,
            )
        if not isinstance(target_record, dict):
            raise RuntimeError("fra target command returned an unexpected payload")

        target_id = str(target_record["target_id"])
        pid = int(target_record["pid"])
        if args.launch and spawned_pid is None:
            spawned_pid = pid

        writer.write_event(
            PersistedStatusEvent(
                phase="attached",
                frida_module=status_fields["frida_module"],
                frida_repo_root=status_fields["frida_repo_root"],
                frida_root=status_fields["frida_root"],
                frida_site_packages=status_fields["frida_site_packages"],
                frida_lib=status_fields["frida_lib"],
                message="attached",
                mode=args.mode,
                output_path=str(writer.bundle_root),
                pid=pid,
                process_name=args.process,
                launch_path=args.launch,
                launch_save=args.launch_save,
            )
        )

        if fra_spawned_target and spawned_pid is not None:
            run_fra_json(
                fra_launcher,
                "target",
                "resume",
                "--target",
                target_id,
                "--format",
                "json",
            )
            writer.write_event(
                PersistedStatusEvent(
                    message="resumed spawned process",
                    pid=spawned_pid,
                )
            )

        controller = scene_spec.controller_factory(args, writer, pid)
        probe_record = run_fra_json(
            fra_launcher,
            "probe",
            "add",
            "--target",
            target_id,
            "--format",
            "json",
            "--stdin",
            input_text=load_agent_source(args),
        )
        if not isinstance(probe_record, dict):
            raise RuntimeError("fra probe add returned an unexpected payload")
        probe_runtime = FraProbeRuntime(
            target_id=target_id,
            probe_id=str(probe_record["probe_id"]),
            artifact_path=Path(str(probe_record["event_artifact"])),
        )

        controller.begin()

        deadline = None
        if args.timeout_sec is not None and args.timeout_sec > 0:
            deadline = time.monotonic() + args.timeout_sec

        while controller is not None and not controller.terminal:
            if interrupted.is_set():
                controller.handle_interrupt()
                break

            if probe_runtime is not None:
                queue_fra_probe_messages(
                    probe_runtime,
                    read_fra_probe_records(fra_launcher, probe_runtime),
                    message_queue,
                )
                crash_title = detect_application_error_dialog(
                    writer,
                    pid,
                    process_name=args.process,
                    launch_path=str(launch_path) if launch_path is not None else args.launch,
                )
                if crash_title is not None:
                    controller.handle_process_exit(
                        f"Application Error dialog detected before the structured trace completed: {crash_title}"
                    )
                    break
                refresh_fra_probe_terminal_state(fra_launcher, probe_runtime)
                if probe_runtime.terminal_event in {"detached", "terminated", "removed"}:
                    reason_suffix = (
                        ""
                        if not probe_runtime.terminal_reason
                        else f" ({probe_runtime.terminal_reason})"
                    )
                    writer.write_event(
                        PersistedStatusEvent(
                            message=f"fra probe {probe_runtime.terminal_event}{reason_suffix}",
                            pid=pid,
                        )
                    )
                    controller.handle_process_exit(
                        f"fra probe {probe_runtime.terminal_event} ended before the structured trace completed{reason_suffix}"
                    )
                    break

            if pid is not None and not process_exists_pid(pid):
                writer.write_event(
                    PersistedStatusEvent(
                        message="target process exited",
                        pid=pid,
                    )
                )
                controller.handle_process_exit(
                    f"process {pid} exited before the structured trace completed"
                )
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
    except Exception as error:
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        if controller is not None and not controller.terminal:
            controller.handle_runtime_error(str(error))
        elif controller is None:
            print(str(error), file=sys.stderr)
            return None, 1
    finally:
        if probe_runtime is not None:
            try:
                run_fra_json(
                    fra_launcher,
                    "probe",
                    "remove",
                    "--format",
                    "json",
                    probe_runtime.probe_id,
                )
            except Exception:
                pass

        if target_id is not None:
            if spawned_pid is not None:
                if args.keep_alive:
                    try:
                        run_fra_json(
                            fra_launcher,
                            "target",
                            "detach",
                            "--target",
                            target_id,
                            "--format",
                            "json",
                        )
                        writer.write_event(
                            PersistedStatusEvent(
                                message="leaving spawned process alive",
                                pid=spawned_pid,
                            )
                        )
                    except Exception:
                        pass
                else:
                    try:
                        terminate_spawned_process(
                            writer,
                            fra_launcher,
                            target_id,
                            spawned_pid,
                        )
                    except Exception:
                        pass
            else:
                try:
                    run_fra_json(
                        fra_launcher,
                        "target",
                        "detach",
                        "--target",
                        target_id,
                        "--format",
                        "json",
                    )
                except Exception:
                    pass

        if launch_path is not None and scene_spec.cleanup_launch is not None:
            if args.keep_alive and spawned_pid is not None:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving staged load-game save in place because the spawned process is still alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    scene_spec.cleanup_launch(args, writer, launch_path)
                except Exception as error:
                    writer.write_event(
                        PersistedErrorEvent(
                            description=f"launch cleanup failed: {error}",
                            stack=None,
                        )
                    )

    return controller, None


def run_structured_debugger_snapshot(
    args: argparse.Namespace,
    writer: JsonlWriter,
    interrupted: threading.Event,
) -> tuple[StructuredSceneController | None, int | None]:
    scene_spec = get_structured_scene_spec(args.mode)
    if scene_spec.snapshot_runner is None:
        raise RuntimeError(f"--mode {args.mode} does not define a debugger snapshot runner")
    if not args.launch:
        raise RuntimeError(f"--mode {args.mode} requires --launch")

    launch_path = Path(args.launch)
    if not launch_path.exists():
        raise RuntimeError(f"launch path does not exist: {launch_path}")

    launched_process: subprocess.Popen[str] | subprocess.Popen[bytes] | None = None
    spawned_pid: int | None = None
    exit_code = 1
    last_error: str | None = None

    try:
        preflight_owned_launch_processes(writer, args.process)
        launched_process = subprocess.Popen(
            build_owned_launch_argv(launch_path, args.launch_save),
            cwd=str(launch_path.parent),
        )
        spawned_pid = int(launched_process.pid)
        writer.write_event(
            PersistedStatusEvent(
                message="launched process before the debugger snapshot lane",
                pid=spawned_pid,
                launch_path=str(launch_path),
            )
        )

        if scene_spec.prepare_launch is not None:
            scene_spec.prepare_launch(args, writer, launch_path, spawned_pid)

        if interrupted.is_set():
            writer.write_event(
                PersistedStatusEvent(
                    message="interrupted before the debugger snapshot lane started",
                    pid=spawned_pid,
                )
            )
            last_error = "interrupted before debugger snapshot"
        else:
            crash_title = detect_application_error_dialog(
                writer,
                spawned_pid,
                process_name=args.process,
                launch_path=args.launch,
            )
            if crash_title is not None:
                last_error = f"Application Error dialog detected before debugger snapshot: {crash_title}"
                writer.write_event(
                    PersistedStatusEvent(
                        phase="completed",
                        message=last_error,
                        pid=spawned_pid,
                    )
                )
                exit_code = 1
            else:
                writer.write_event(
                    PersistedStatusEvent(
                        phase="attached",
                        message="ready to capture the debugger snapshot lane",
                        mode=args.mode,
                        output_path=str(writer.bundle_root),
                        pid=spawned_pid,
                        process_name=args.process,
                        launch_path=args.launch,
                        launch_save=args.launch_save,
                    )
                )
                exit_code, last_error = scene_spec.snapshot_runner(args, writer, spawned_pid)
    except Exception as error:
        writer.write_event(
            PersistedErrorEvent(
                description=str(error),
                stack=None,
            )
        )
        print(str(error), file=sys.stderr)
        return None, 1
    finally:
        if spawned_pid is not None:
            if args.keep_alive:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving spawned process alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    if launched_process is not None:
                        launched_process.terminate()
                    else:
                        os.kill(spawned_pid, signal.SIGTERM)
                except ProcessLookupError:
                    writer.write_event(
                        PersistedStatusEvent(
                            message="spawned process exited before direct kill",
                            pid=spawned_pid,
                        )
                    )
                except PermissionError:
                    if process_exists_pid(spawned_pid):
                        try:
                            if launched_process is not None:
                                launched_process.kill()
                            else:
                                raise
                        except Exception as error:
                            writer.write_event(
                                PersistedErrorEvent(
                                    description=f"direct kill failed: {error}",
                                    stack=None,
                                )
                            )
                            spawned_pid = None
                    else:
                        writer.write_event(
                            PersistedStatusEvent(
                                message="spawned process exited before direct kill",
                                pid=spawned_pid,
                            )
                        )
                else:
                    if wait_for_process_exit(spawned_pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
                        writer.write_event(
                            PersistedStatusEvent(
                                message="killed spawned process",
                                pid=spawned_pid,
                            )
                        )
                    else:
                        try:
                            if launched_process is not None:
                                launched_process.kill()
                        except Exception as error:
                            writer.write_event(
                                PersistedErrorEvent(
                                    description=f"direct kill failed: {error}",
                                    stack=None,
                                )
                            )
                        if wait_for_process_exit(spawned_pid, SPAWNED_PROCESS_TERMINATE_GRACE_SEC):
                            writer.write_event(
                                PersistedStatusEvent(
                                    message="force-killed spawned process",
                                    pid=spawned_pid,
                                )
                            )
                        else:
                            writer.write_event(
                                PersistedStatusEvent(
                                    message="spawned process still alive after direct kill",
                                    pid=spawned_pid,
                                )
                            )

        if scene_spec.cleanup_launch is not None:
            if args.keep_alive and spawned_pid is not None:
                writer.write_event(
                    PersistedStatusEvent(
                        message="leaving staged load-game save in place because the spawned process is still alive",
                        pid=spawned_pid,
                    )
                )
            else:
                try:
                    scene_spec.cleanup_launch(args, writer, launch_path)
                except Exception as error:
                    writer.write_event(
                        PersistedErrorEvent(
                            description=f"launch cleanup failed: {error}",
                            stack=None,
                        )
                    )

    if last_error:
        print(last_error, file=sys.stderr)
    return None, exit_code
