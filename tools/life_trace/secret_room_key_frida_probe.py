from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_FRIDA_REPO = Path(r"D:\repos\reverse\frida")
DEFAULT_PROCESS_NAME = "LBA2.EXE"

ADDR_NB_LITTLE_KEYS = 0x0049A0A6
ADDR_LIST_EXTRA = 0x004A7428
EXTRA_STRIDE = 0x44
MAX_EXTRAS = 50
SPRITE_CLE = 6


@dataclass(frozen=True)
class ProbeEvent:
    kind: str
    payload: dict[str, Any]


def ensure_staged_frida(repo_root: Path) -> None:
    frida_root = repo_root / "build" / "install-root" / "Program Files" / "Frida"
    site_packages = frida_root / "lib" / "site-packages"
    frida_bin = frida_root / "bin"
    frida_lib = frida_root / "lib" / "frida" / "x86_64"
    missing = [path for path in (frida_root, site_packages, frida_bin, frida_lib) if not path.exists()]
    if missing:
        joined = "\n".join(str(path) for path in missing)
        raise RuntimeError(f"missing staged Frida paths:\n{joined}")
    sys.path.insert(0, str(site_packages))
    os.environ["PYTHONPATH"] = str(site_packages)
    os.environ["PATH"] = os.pathsep.join([str(frida_bin), str(frida_lib), os.environ.get("PATH", "")])


def import_frida(repo_root: Path):
    ensure_staged_frida(repo_root)
    import frida  # type: ignore

    return frida


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
        raise RuntimeError(f"tasklist failed: {detail}")

    matches: list[int] = []
    for raw_line in completed.stdout.splitlines():
        columns = [part.strip('"') for part in raw_line.split('","')]
        if len(columns) < 2:
            continue
        if columns[0].lower() != target:
            continue
        matches.append(int(columns[1]))

    if not matches:
        raise RuntimeError(f"process not found: {process_name}")
    if len(matches) > 1:
        raise RuntimeError(f"multiple {process_name} processes found; pass --attach-pid")
    return matches[0]


def build_script(*, poll_ms: int, hook_life: bool = True) -> str:
    life_hook_block = ""
    if hook_life:
        life_hook_block = """
Interceptor.attach(ADDR.doLifeEntry, {
  onEnter(args) {
    const objectIndex = this.context.eax.toUInt32() & 0xff;
    stackFor(this.threadId).push(objectState(objectIndex));
  },
  onLeave(retval) {
    const stack = stackFor(this.threadId);
    if (stack.length > 0) stack.pop();
    if (stack.length === 0) delete stacks[this.threadId];
  },
});

Interceptor.attach(ADDR.doLifeLoop, function () {
  const state = currentState(this.threadId);
  if (state === null || state.object_index !== 0) return;

  const ptrPrg = readPointer(ADDR.ptrPrg);
  if (ptrPrg.isNull()) return;
  const opcode = readU8(ptrPrg);
  if (opcode !== 46) return;

  const operand = readU8(ptrPrg.add(1));
  const event = {
    thread_id: this.threadId,
    object_index: state.object_index,
    ptr_life: pointerString(state.ptr_life_ptr),
    offset_life: state.offset_life,
    ptr_prg: pointerString(ptrPrg),
    ptr_prg_offset: pointerDelta(ptrPrg, state.ptr_life_ptr),
    opcode: opcode,
    operand: operand,
    key_state: snapshotKeyState('lm_found_object'),
  };
  if (operand === 0) foundObjectSeen = true;
  sendProbe('lm_found_object', event);
});
"""

    return rf"""
const imageBase = ptr('0x00400000');
const mainModule = Process.enumerateModules().find((module) => module.name.toLowerCase() === 'lba2.exe') || Process.enumerateModules()[0];
const base = mainModule.base;

function absolute(absoluteAddress) {{
  return base.add(ptr(absoluteAddress).sub(imageBase));
}}

const ADDR = {{
  doLifeEntry: base.add(0x00020574),
  doLifeLoop: base.add(0x000205bc),
  ptrPrg: base.add(0x000976d0),
  objectBase: base.add(0x0009a19c),
  nbLittleKeys: absolute('0x{ADDR_NB_LITTLE_KEYS:08x}'),
  listExtra: absolute('0x{ADDR_LIST_EXTRA:08x}'),
}};

const OFF = {{
  objectStride: 0x21b,
  ptrLife: 0x1ee,
  offsetLife: 0x1f2,
  extraPosX: 0x00,
  extraPosY: 0x04,
  extraPosZ: 0x08,
  extraOrgX: 0x0c,
  extraOrgY: 0x10,
  extraOrgZ: 0x14,
  extraSprite: 0x20,
  extraVx: 0x22,
  extraVy: 0x24,
  extraVz: 0x26,
  extraFlags: 0x28,
  extraTimeOut: 0x34,
  extraDivers: 0x36,
}};

const EXTRA_STRIDE = {EXTRA_STRIDE};
const MAX_EXTRAS = {MAX_EXTRAS};
const SPRITE_CLE = {SPRITE_CLE};
const stacks = {{}};
let lastNbLittleKeys = null;
let lastKeyExtraSignature = null;
let foundObjectSeen = false;

function readU8(address) {{ try {{ return address.readU8(); }} catch (e) {{ return null; }} }}
function readS16(address) {{ try {{ return address.readS16(); }} catch (e) {{ return null; }} }}
function readS32(address) {{ try {{ return address.readS32(); }} catch (e) {{ return null; }} }}
function readU32(address) {{ try {{ return address.readU32(); }} catch (e) {{ return null; }} }}
function readPointer(address) {{ try {{ return address.readPointer(); }} catch (e) {{ return ptr(0); }} }}

function pointerString(value) {{
  return value.isNull() ? '0x0' : value.toString();
}}

function pointerDelta(value, baseValue) {{
  if (value.isNull() || baseValue.isNull()) return null;
  return (value.toUInt32() - baseValue.toUInt32()) | 0;
}}

function objectState(objectIndex) {{
  const object = ADDR.objectBase.add(objectIndex * OFF.objectStride);
  return {{
    object_index: objectIndex,
    current_object: pointerString(object),
    ptr_life_ptr: readPointer(object.add(OFF.ptrLife)),
    offset_life: readS16(object.add(OFF.offsetLife)),
  }};
}}

function stackFor(threadId) {{
  if (stacks[threadId] === undefined) stacks[threadId] = [];
  return stacks[threadId];
}}

function currentState(threadId) {{
  const stack = stacks[threadId];
  if (stack === undefined || stack.length === 0) return null;
  return stack[stack.length - 1];
}}

function sendProbe(kind, payload) {{
  send({{
    kind: kind,
    payload: payload,
  }});
}}

function extraSnapshot(index) {{
  const address = ADDR.listExtra.add(index * EXTRA_STRIDE);
  return {{
    index: index,
    address: pointerString(address),
    pos_x: readS32(address.add(OFF.extraPosX)),
    pos_y: readS32(address.add(OFF.extraPosY)),
    pos_z: readS32(address.add(OFF.extraPosZ)),
    org_x: readS32(address.add(OFF.extraOrgX)),
    org_y: readS32(address.add(OFF.extraOrgY)),
    org_z: readS32(address.add(OFF.extraOrgZ)),
    sprite: readS16(address.add(OFF.extraSprite)),
    vx: readS16(address.add(OFF.extraVx)),
    vy: readS16(address.add(OFF.extraVy)),
    vz: readS16(address.add(OFF.extraVz)),
    flags: readU32(address.add(OFF.extraFlags)),
    timeout: readS16(address.add(OFF.extraTimeOut)),
    divers: readS16(address.add(OFF.extraDivers)),
  }};
}}

function keyExtras() {{
  const found = [];
  for (let index = 0; index < MAX_EXTRAS; index++) {{
    const extra = extraSnapshot(index);
    if (extra.sprite === SPRITE_CLE) found.push(extra);
  }}
  return found;
}}

function keyExtraSignature(extras) {{
  return JSON.stringify(extras.map((extra) => [
    extra.index,
    extra.pos_x,
    extra.pos_y,
    extra.pos_z,
    extra.org_x,
    extra.org_y,
    extra.org_z,
    extra.divers,
    extra.flags,
  ]));
}}

function snapshotKeyState(reason) {{
  const nbLittleKeys = readU8(ADDR.nbLittleKeys);
  const extras = keyExtras();
  return {{
    reason: reason,
    module_base: pointerString(base),
    nb_little_keys: nbLittleKeys,
    key_extras: extras,
  }};
}}

{life_hook_block}

setInterval(function () {{
  const nbLittleKeys = readU8(ADDR.nbLittleKeys);
  if (lastNbLittleKeys === null) {{
    lastNbLittleKeys = nbLittleKeys;
    sendProbe('initial_key_counter', snapshotKeyState('initial'));
  }} else if (nbLittleKeys !== lastNbLittleKeys) {{
    const previous = lastNbLittleKeys;
    lastNbLittleKeys = nbLittleKeys;
    const state = snapshotKeyState('key_counter_change');
    state.previous_nb_little_keys = previous;
    sendProbe('key_counter_change', state);
  }}

  const extras = keyExtras();
  const signature = keyExtraSignature(extras);
  if (signature !== lastKeyExtraSignature) {{
    lastKeyExtraSignature = signature;
    if (extras.length > 0 || foundObjectSeen) {{
      sendProbe('key_extra_state', {{
        reason: 'key_extra_signature_change',
        nb_little_keys: nbLittleKeys,
        key_extras: extras,
        found_object_seen: foundObjectSeen,
      }});
    }}
  }}
}}, {max(1, poll_ms)});

rpc.exports = {{
  snapshot() {{
    return snapshotKeyState('rpc_snapshot');
  }},
}};
"""


def normalize_message(message: dict[str, Any]) -> ProbeEvent | None:
    if message.get("type") != "send":
        return ProbeEvent("frida_message", {"message": message})
    payload = message.get("payload")
    if not isinstance(payload, dict):
        return ProbeEvent("frida_message", {"message": message})
    kind = payload.get("kind")
    event_payload = payload.get("payload")
    if not isinstance(kind, str) or not isinstance(event_payload, dict):
        return ProbeEvent("frida_message", {"message": message})
    return ProbeEvent(kind, event_payload)


def summarize_events(events: Iterable[dict[str, Any]]) -> dict[str, Any]:
    found_hits = [
        event
        for event in events
        if event.get("kind") == "lm_found_object" and event.get("payload", {}).get("operand") == 0
    ]
    extra_events = [
        event
        for event in events
        if event.get("kind") == "key_extra_state" and event.get("payload", {}).get("key_extras")
    ]
    counter_changes = [
        event
        for event in events
        if event.get("kind") == "key_counter_change"
    ]
    first_extra_time = next(
        (
            event.get("t")
            for event in extra_events
            if isinstance(event.get("t"), (int, float))
        ),
        None,
    )
    first_increment_time = next(
        (
            event.get("t")
            for event in counter_changes
            if int(event["payload"].get("nb_little_keys", -1)) > int(event["payload"].get("previous_nb_little_keys", -1))
            and isinstance(event.get("t"), (int, float))
        ),
        None,
    )
    return {
        "lm_found_object_0_hits": len(found_hits),
        "key_extra_state_events": len(extra_events),
        "key_counter_changes": len(counter_changes),
        "observed_found_to_key_extra": bool(found_hits and extra_events),
        "observed_key_extra_to_counter_increment": (
            first_extra_time is not None
            and first_increment_time is not None
            and first_extra_time <= first_increment_time
        ),
        "observed_key_counter_increment": any(
            int(event["payload"].get("nb_little_keys", -1)) > int(event["payload"].get("previous_nb_little_keys", -1))
            for event in counter_changes
        ),
        "first_key_extra_time": first_extra_time,
        "first_key_counter_increment_time": first_increment_time,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Attach a Frida probe for the 0013 secret-room default-action key source and pickup seam."
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--attach-pid", type=int, help="Attach to an already-running LBA2.EXE pid.")
    target.add_argument("--process-name", help="Resolve an already-running process by exact name.")
    parser.add_argument("--out", required=True, help="JSONL output path.")
    parser.add_argument("--summary-out", help="Optional JSON summary path. Defaults to <out>.summary.json.")
    parser.add_argument("--frida-repo-root", default=str(DEFAULT_FRIDA_REPO), help="Frida repo root containing build/install-root.")
    parser.add_argument("--duration-sec", type=float, default=30.0, help="Capture duration.")
    parser.add_argument("--poll-ms", type=int, default=20, help="Polling interval for key extras and key counter.")
    parser.add_argument(
        "--poll-only",
        action="store_true",
        help="Do not hook the life interpreter; only poll the key counter and extra table.",
    )
    return parser.parse_args(argv)


def run_probe(args: argparse.Namespace) -> int:
    frida = import_frida(Path(args.frida_repo_root))
    device = frida.get_local_device()
    pid = args.attach_pid if args.attach_pid is not None else find_pid_by_name(args.process_name or DEFAULT_PROCESS_NAME)
    out_path = Path(args.out).resolve()
    summary_path = Path(args.summary_out).resolve() if args.summary_out else out_path.with_suffix(out_path.suffix + ".summary.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    events: list[dict[str, Any]] = []

    def write_event(kind: str, payload: dict[str, Any]) -> None:
        row = {
            "t": round(time.time() - started, 3),
            "kind": kind,
            "payload": payload,
        }
        events.append(row)
        with out_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, separators=(",", ":")) + "\n")

    def on_message(message: dict[str, Any], data: bytes | None) -> None:
        del data
        event = normalize_message(message)
        if event is not None:
            write_event(event.kind, event.payload)

    session = device.attach(pid)
    script = session.create_script(build_script(poll_ms=max(1, args.poll_ms), hook_life=not args.poll_only))
    script.on("message", on_message)

    global started
    started = time.time()
    out_path.write_text("", encoding="utf-8")
    try:
        script.load()
        write_event(
            "attached",
            {
                "pid": pid,
                "duration_sec": args.duration_sec,
                "poll_ms": args.poll_ms,
                "poll_only": bool(args.poll_only),
            },
        )
        deadline = started + max(0.1, args.duration_sec)
        while time.time() < deadline:
            time.sleep(0.05)
        try:
            write_event("final_snapshot", script.exports_sync.snapshot())
        except Exception as exc:
            write_event("final_snapshot_error", {"error": str(exc)})
    finally:
        try:
            try:
                script.unload()
            except Exception as exc:
                write_event("script_unload_error", {"error": str(exc)})
        finally:
            try:
                session.detach()
            except Exception as exc:
                write_event("session_detach_error", {"error": str(exc)})

    summary = summarize_events(events)
    summary.update({
        "pid": pid,
        "out": str(out_path),
    })
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


started = 0.0


def main(argv: list[str] | None = None) -> int:
    return run_probe(parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
