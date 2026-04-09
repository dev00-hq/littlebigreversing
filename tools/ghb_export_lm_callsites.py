from __future__ import annotations

import argparse
import contextlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GHB_REPO_ROOT = Path(r"D:\repos\ghb")
DEFAULT_GHIDRA_INSTALL_DIR = Path(r"D:\repos\reverse\ghidra\build\dist\ghidra_12.2_DEV")
DEFAULT_BINARY = Path(
    r"D:\repos\reverse\littlebigreversing\work\_innoextract_full\Speedrun\Windows\LBA2_cdrom\LBA2\LBA2.EXE"
)
DEFAULT_OUTPUT = REPO_ROOT / "work" / "ghidra_projects" / "callsites" / "lm_helper_callsites.jsonl"
DEFAULT_PROJECT_NAME = "lba2_lm_callsites"
DEFAULT_LAUNCH_TIMEOUT_SECONDS = 180.0
DEFAULT_WITHIN_ENTRY = "ram:00420574"

REQUIRED_FIELDS = (
    "callee_name",
    "callee_address",
    "within_function",
    "within_entry",
    "call_instruction",
    "caller_static",
    "caller_static_rel",
)


class ExportError(RuntimeError):
    pass


@dataclass(frozen=True)
class CallsiteTarget:
    name: str
    address_hex: str

    @property
    def address_literal(self) -> str:
        return f"0x{self.address_hex.upper()}L"

    @property
    def normalized_address(self) -> str:
        return f"ram:{self.address_hex.lower()}"


TARGETS = (
    CallsiteTarget(name="DoFuncLife", address_hex="0041F0A8"),
    CallsiteTarget(name="DoTest", address_hex="0041FE30"),
)


def parse_ram_address(value: str) -> str:
    text = value.strip().lower()
    if text.startswith("ram:"):
        text = text[4:]
    if text.startswith("0x"):
        text = text[2:]
    if not text or any(char not in "0123456789abcdef" for char in text):
        raise argparse.ArgumentTypeError(f"expected a hex address, got {value!r}")
    return f"ram:{text.zfill(8)}"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Launch a disposable Ghidra project through ghb, export the current LM helper "
            "callsites for DoFuncLife and DoTest, and write a canonical JSONL map."
        )
    )
    parser.add_argument(
        "--ghb-repo-root",
        default=str(DEFAULT_GHB_REPO_ROOT),
        help="Path to the local ghb repository.",
    )
    parser.add_argument(
        "--ghidra-install-dir",
        default=str(DEFAULT_GHIDRA_INSTALL_DIR),
        help="Path to the local Ghidra install root.",
    )
    parser.add_argument(
        "--binary",
        default=str(DEFAULT_BINARY),
        help="Path to the Windows LBA2.EXE to import into the disposable project.",
    )
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT),
        help="Path to the exported JSONL callsite map.",
    )
    parser.add_argument(
        "--project-root",
        help="Explicit disposable project root. Defaults under <ghb-repo-root>/tmp/.",
    )
    parser.add_argument(
        "--project-name",
        default=DEFAULT_PROJECT_NAME,
        help="Disposable Ghidra project name.",
    )
    parser.add_argument(
        "--within-entry",
        type=parse_ram_address,
        default=DEFAULT_WITHIN_ENTRY,
        help="Optional containing-function entry filter in ram:/0x hex form.",
    )
    parser.add_argument(
        "--launch-timeout",
        type=float,
        default=DEFAULT_LAUNCH_TIMEOUT_SECONDS,
        help="Seconds to wait for ghb bridge bring-up and active-program readiness.",
    )
    parser.add_argument(
        "--keep-project",
        action="store_true",
        help="Keep the disposable project directory after the export completes.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit the final export summary as JSON instead of text.",
    )
    return parser.parse_args(argv)


def ensure_ghb_importable(ghb_repo_root: Path) -> None:
    src_root = ghb_repo_root / "src"
    if not src_root.exists():
        raise ExportError(f"ghb src root does not exist: {src_root}")
    src_text = str(src_root)
    if src_text not in sys.path:
        sys.path.insert(0, src_text)


def build_env(ghb_repo_root: Path, ghidra_install_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    src_root = ghb_repo_root / "src"
    existing_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = src_root.as_posix() if not existing_pythonpath else os.pathsep.join(
        [str(src_root), existing_pythonpath]
    )
    env["GHIDRA_INSTALL_DIR"] = str(ghidra_install_dir)
    return env


def discover_live_bridge(ghb_repo_root: Path, env: dict[str, str]):
    ensure_ghb_importable(ghb_repo_root)
    from ghb.transport import discover_instance  # type: ignore

    return discover_instance(env)


def ensure_prerequisites(ghb_repo_root: Path, ghidra_install_dir: Path, binary_path: Path) -> None:
    for path, label in (
        (ghb_repo_root, "ghb repo root"),
        (ghidra_install_dir, "Ghidra install dir"),
        (binary_path, "LBA2 binary"),
    ):
        if not path.exists():
            raise ExportError(f"{label} does not exist: {path}")

    analyze = ghidra_install_dir / "support" / "analyzeHeadless.bat"
    if not analyze.exists():
        raise ExportError(f"Ghidra analyzeHeadless launcher does not exist: {analyze}")

    ghidra_bat = ghidra_install_dir / "ghidra.bat"
    if not ghidra_bat.exists():
        raise ExportError(f"Ghidra launcher does not exist: {ghidra_bat}")


def ensure_no_live_bridge(ghb_repo_root: Path, env: dict[str, str]) -> None:
    instance = discover_live_bridge(ghb_repo_root, env)
    if instance is None:
        return
    raise ExportError(
        "A live ghb bridge is already running at "
        f"{instance.host}:{instance.port} (pid {instance.pid}). "
        "Close that Ghidra session before exporting LM callsites."
    )


def resolve_project_root(args: argparse.Namespace, ghb_repo_root: Path) -> tuple[Path, bool]:
    if args.project_root:
        project_root = Path(args.project_root).resolve()
        if project_root.exists():
            if any(project_root.iterdir()):
                raise ExportError(
                    f"explicit project root already exists and is not empty: {project_root}"
                )
        else:
            project_root.mkdir(parents=True, exist_ok=True)
        return project_root, False

    temp_parent = ghb_repo_root / "tmp"
    temp_parent.mkdir(parents=True, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix="lm-ghb-callsites-", dir=temp_parent)), True


def run_command(command: list[str], *, timeout: float, cwd: Path | None = None) -> None:
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )
    if result.returncode == 0:
        return
    detail = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}"
    raise ExportError(f"`{' '.join(command)}` failed: {detail}")


def prepare_project(
    *,
    ghidra_install_dir: Path,
    project_root: Path,
    project_name: str,
    binary_path: Path,
) -> None:
    log_dir = project_root / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    analyze = ghidra_install_dir / "support" / "analyzeHeadless.bat"
    command = [
        str(analyze),
        str(project_root),
        project_name,
        "-import",
        str(binary_path),
        "-log",
        str(log_dir / "import.log"),
        "-scriptlog",
        str(log_dir / "import-script.log"),
    ]
    run_command(command, timeout=1800, cwd=ghidra_install_dir)


def launch_ghidra(
    *,
    ghidra_install_dir: Path,
    project_root: Path,
    project_name: str,
    binary_name: str,
) -> subprocess.Popen[str]:
    ghidra_bat = ghidra_install_dir / "ghidra.bat"
    project_spec = f"{project_root / (project_name + '.gpr')}:/%s" % binary_name
    return subprocess.Popen(
        [str(ghidra_bat), project_spec],
        cwd=ghidra_install_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def run_ghb(
    ghb_repo_root: Path,
    env: dict[str, str],
    *args: str,
    check: bool = True,
    stdin_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, "-m", "ghb", *args]
    result = subprocess.run(
        command,
        cwd=ghb_repo_root,
        env=env,
        input=stdin_text,
        capture_output=True,
        text=True,
        check=False,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}"
        raise ExportError(f"`{' '.join(command)}` failed: {detail}")
    return result


def run_ghb_json(
    ghb_repo_root: Path,
    env: dict[str, str],
    *args: str,
    stdin_text: str | None = None,
) -> dict[str, Any]:
    result = run_ghb(
        ghb_repo_root,
        env,
        *args,
        check=True,
        stdin_text=stdin_text,
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ExportError(
            f"`{' '.join(result.args)}` returned invalid JSON: {result.stdout.strip()!r}"
        ) from exc


def active_program_selector(programs_payload: Any) -> str | None:
    if not isinstance(programs_payload, list):
        raise ExportError(f"expected program list payload, got {json.dumps(programs_payload, sort_keys=True)}")
    active_programs = [program for program in programs_payload if program.get("active")]
    if len(active_programs) != 1:
        return None
    selector = active_programs[0].get("selector")
    return selector if isinstance(selector, str) else None


def wait_for_bridge(
    *,
    ghb_repo_root: Path,
    env: dict[str, str],
    timeout: float,
    expected_selector: str,
) -> Any:
    deadline = time.time() + timeout
    last_error = "no registry discovered yet"

    while time.time() < deadline:
        instance = discover_live_bridge(ghb_repo_root, env)
        if instance is None:
            time.sleep(1.0)
            continue

        try:
            doctor_payload = run_ghb_json(ghb_repo_root, env, "doctor", "--format", "json")
            if doctor_payload.get("ok") is not True:
                last_error = str(doctor_payload.get("summary", "doctor did not report ok"))
                time.sleep(1.0)
                continue

            bridge_payload = doctor_payload.get("bridge") or {}
            if bridge_payload.get("programs_open") != 1:
                last_error = f"expected 1 open program, saw {bridge_payload.get('programs_open')}"
                time.sleep(1.0)
                continue

            programs_payload = run_ghb_json(ghb_repo_root, env, "program", "list", "--format", "json")
            active_selector = active_program_selector(programs_payload)
            if active_selector != expected_selector:
                last_error = f"expected active selector {expected_selector}, saw {active_selector or 'none'}"
                time.sleep(1.0)
                continue

            return instance
        except ExportError as exc:
            last_error = str(exc)
            time.sleep(1.0)

    raise ExportError(f"timed out waiting for a healthy ghb bridge: {last_error}")


def build_export_script(within_entry: str | None) -> str:
    within_literal = "null" if within_entry is None else json.dumps(within_entry)
    target_lines = "\n".join(
        f'targets.put("{target.name}", toAddr({target.address_literal}));'
        for target in TARGETS
    )
    return f"""
java.util.List rows = new java.util.ArrayList();
java.util.Map targets = new java.util.LinkedHashMap();
{target_lines}

String withinEntryFilter = {within_literal};

ghidra.program.model.listing.FunctionManager fm = currentProgram.getFunctionManager();
ghidra.program.model.symbol.ReferenceManager rm = currentProgram.getReferenceManager();
ghidra.program.model.listing.Listing listing = currentProgram.getListing();
ghidra.program.model.address.Address imageBase = currentProgram.getImageBase();

java.util.Iterator itTargets = targets.entrySet().iterator();
while (itTargets.hasNext()) {{
    java.util.Map.Entry entry = (java.util.Map.Entry) itTargets.next();
    String calleeName = (String) entry.getKey();
    ghidra.program.model.address.Address calleeAddr =
        (ghidra.program.model.address.Address) entry.getValue();
    ghidra.program.model.listing.Function calleeFn = fm.getFunctionAt(calleeAddr);
    if (calleeFn == null) {{
        throw new IllegalStateException("No function at " + calleeAddr + " for " + calleeName);
    }}

    ghidra.program.model.symbol.ReferenceIterator refs = rm.getReferencesTo(calleeAddr);
    boolean sawCall = false;
    while (refs.hasNext()) {{
        ghidra.program.model.symbol.Reference ref = refs.next();
        if (!ref.getReferenceType().isCall()) {{
            continue;
        }}

        ghidra.program.model.address.Address callAddr = ref.getFromAddress();
        ghidra.program.model.listing.Function withinFn = fm.getFunctionContaining(callAddr);
        if (withinFn == null) {{
            throw new IllegalStateException("No containing function for callsite " + callAddr);
        }}
        if (withinEntryFilter != null &&
            !withinFn.getEntryPoint().toString(true).equals(withinEntryFilter)) {{
            continue;
        }}

        sawCall = true;
        ghidra.program.model.listing.Instruction instr = listing.getInstructionAt(callAddr);
        if (instr == null) {{
            throw new IllegalStateException("No instruction at callsite " + callAddr);
        }}
        ghidra.program.model.address.Address fallthrough = instr.getFallThrough();
        if (fallthrough == null) {{
            throw new IllegalStateException("No fallthrough for callsite " + callAddr);
        }}
        long rel = fallthrough.subtract(imageBase);
        java.util.Map row = new java.util.LinkedHashMap();
        row.put("callee_name", calleeName);
        row.put("callee_address", calleeAddr.toString(true));
        row.put("within_function", withinFn.getName());
        row.put("within_entry", withinFn.getEntryPoint().toString(true));
        row.put("call_instruction", callAddr.toString(true));
        row.put("caller_static", fallthrough.toString(true));
        row.put("caller_static_rel", String.format("0x%08X", rel));
        rows.add(row);
    }}

    if (!sawCall) {{
        throw new IllegalStateException(
            "No call references found for " + calleeName +
            (withinEntryFilter == null ? "" : " within " + withinEntryFilter)
        );
    }}
}}

ghb_result = rows;
println("exported " + rows.size() + " raw callsites");
""".strip()


def export_raw_rows(
    *,
    ghb_repo_root: Path,
    env: dict[str, str],
    within_entry: str | None,
) -> list[dict[str, Any]]:
    payload = run_ghb_json(
        ghb_repo_root,
        env,
        "script",
        "exec",
        "--stdin",
        "--language",
        "java",
        "--program",
        "active",
        "--format",
        "json",
        stdin_text=build_export_script(within_entry),
    )
    if payload.get("success") is not True:
        raise ExportError(f"ghb script exec reported failure: {json.dumps(payload, sort_keys=True)}")
    result = payload.get("result")
    if not isinstance(result, list):
        raise ExportError(f"ghb script exec returned unexpected result payload: {json.dumps(payload, sort_keys=True)}")
    return result


def normalize_callsite_rows(raw_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    seen_targets: dict[str, int] = {}

    for row in raw_rows:
        if not isinstance(row, dict):
            raise ExportError(f"expected each ghb result row to be an object, got {row!r}")
        for field in REQUIRED_FIELDS:
            value = row.get(field)
            if not isinstance(value, str) or not value:
                raise ExportError(f"missing or invalid {field!r} in row: {json.dumps(row, sort_keys=True)}")
        if row["caller_static"] == row["call_instruction"]:
            raise ExportError(
                "caller_static must be the fallthrough PC, not the call instruction address: "
                f"{json.dumps(row, sort_keys=True)}"
            )
        seen_targets[row["callee_name"]] = seen_targets.get(row["callee_name"], 0) + 1
        normalized.append(
            {
                "callee_name": row["callee_name"],
                "callee_address": row["callee_address"],
                "within_function": row["within_function"],
                "within_entry": row["within_entry"],
                "call_instruction": row["call_instruction"],
                "caller_static": row["caller_static"],
                "caller_static_rel": row["caller_static_rel"],
            }
        )

    missing_targets = [target.name for target in TARGETS if seen_targets.get(target.name, 0) == 0]
    if missing_targets:
        joined = ", ".join(missing_targets)
        raise ExportError(f"missing callsite rows for required targets: {joined}")

    normalized.sort(
        key=lambda row: (
            str(row["within_function"]).lower(),
            str(row["within_entry"]).lower(),
            str(row["call_instruction"]).lower(),
            str(row["callee_name"]).lower(),
        )
    )

    call_indexes: dict[tuple[str, str, str], int] = {}
    for row in normalized:
        key = (
            str(row["within_function"]),
            str(row["within_entry"]),
            str(row["callee_name"]),
        )
        call_index = call_indexes.get(key, 0)
        row["call_index"] = call_index
        call_indexes[key] = call_index + 1
    return normalized


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=True, sort_keys=False))
            handle.write("\n")


def summarize_export(
    *,
    output_path: Path,
    project_root: Path,
    project_name: str,
    binary_path: Path,
    within_entry: str | None,
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    counts: dict[str, int] = {}
    for row in rows:
        name = str(row["callee_name"])
        counts[name] = counts.get(name, 0) + 1
    return {
        "ok": True,
        "binary": str(binary_path),
        "project_root": str(project_root),
        "project_name": project_name,
        "within_entry": within_entry,
        "output": str(output_path),
        "records": len(rows),
        "targets": counts,
    }


def format_summary(summary: dict[str, Any]) -> str:
    target_bits = ", ".join(f"{name}={count}" for name, count in sorted(summary["targets"].items()))
    return (
        f"wrote {summary['records']} LM callsite records to {summary['output']} "
        f"({target_bits}; within_entry={summary['within_entry'] or 'none'})"
    )


def stop_bridge_process(pid: int) -> None:
    os.kill(pid, signal.SIGTERM)


def terminate_ghidra_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return

    if os.name == "nt" and getattr(process, "pid", None):
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            capture_output=True,
            text=True,
            check=False,
        )
    else:
        process.terminate()

    with contextlib.suppress(Exception):
        process.wait(timeout=10)


def remove_tree_with_retries(path: Path, *, attempts: int = 10, delay_seconds: float = 1.0) -> None:
    last_error: OSError | None = None
    for _ in range(attempts):
        try:
            shutil.rmtree(path)
            return
        except FileNotFoundError:
            return
        except OSError as exc:
            last_error = exc
            time.sleep(delay_seconds)
    raise ExportError(f"failed to remove disposable project root {path}: {last_error}")


def export_callsites(args: argparse.Namespace) -> dict[str, Any]:
    ghb_repo_root = Path(args.ghb_repo_root).resolve()
    ghidra_install_dir = Path(args.ghidra_install_dir).resolve()
    binary_path = Path(args.binary).resolve()
    output_path = Path(args.output).resolve()
    project_root, created_temp_root = resolve_project_root(args, ghb_repo_root)
    env = build_env(ghb_repo_root, ghidra_install_dir)
    ghidra_process: subprocess.Popen[str] | None = None
    bridge_instance: Any = None
    pending_error: Exception | None = None
    summary: dict[str, Any] | None = None

    ensure_prerequisites(ghb_repo_root, ghidra_install_dir, binary_path)
    ensure_no_live_bridge(ghb_repo_root, env)

    try:
        prepare_project(
            ghidra_install_dir=ghidra_install_dir,
            project_root=project_root,
            project_name=args.project_name,
            binary_path=binary_path,
        )
        ghidra_process = launch_ghidra(
            ghidra_install_dir=ghidra_install_dir,
            project_root=project_root,
            project_name=args.project_name,
            binary_name=binary_path.name,
        )
        expected_selector = f"{args.project_name}:/{binary_path.name}"
        bridge_instance = wait_for_bridge(
            ghb_repo_root=ghb_repo_root,
            env=env,
            timeout=args.launch_timeout,
            expected_selector=expected_selector,
        )
        rows = normalize_callsite_rows(
            export_raw_rows(
                ghb_repo_root=ghb_repo_root,
                env=env,
                within_entry=args.within_entry,
            )
        )
        write_jsonl(output_path, rows)
        summary = summarize_export(
            output_path=output_path,
            project_root=project_root,
            project_name=args.project_name,
            binary_path=binary_path,
            within_entry=args.within_entry,
            rows=rows,
        )
    except Exception as exc:
        pending_error = exc
    finally:
        if ghidra_process is not None:
            with contextlib.suppress(Exception):
                terminate_ghidra_process(ghidra_process)
        if bridge_instance is not None:
            with contextlib.suppress(Exception):
                stop_bridge_process(int(bridge_instance.pid))
        if created_temp_root and not args.keep_project:
            try:
                remove_tree_with_retries(project_root)
            except Exception as exc:
                if pending_error is None:
                    pending_error = exc

    if pending_error is not None:
        raise pending_error
    if summary is None:
        raise ExportError("LM callsite export completed without a summary payload")
    return summary


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    summary = export_callsites(args)
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(format_summary(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
