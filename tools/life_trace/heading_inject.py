from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from debug_compass import (
    describe_beta,
    degrees_to_beta,
    heading_to_beta,
    normalize_beta,
    shortest_beta_delta,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FRIDA_REPO = Path(r"D:\repos\reverse\frida")
DEFAULT_PROCESS_NAME = "LBA2.EXE"


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


def build_script() -> str:
    return r"""
const imageBase = ptr('0x00400000');
const mainModule = Process.enumerateModules().find((module) => module.name.toLowerCase() === 'lba2.exe') || Process.enumerateModules()[0];
const base = mainModule.base;

function absAddr(absolute) {
  return base.add(ptr(absolute).sub(imageBase));
}

const ADDR = {
  heroBase: absAddr('0x0049a19c'),
};

const OFF = {
  oldX: 0x08,
  oldY: 0x0c,
  oldZ: 0x10,
  x: 0x3e,
  y: 0x42,
  z: 0x46,
  beta: 0x4e,
  oldBeta: 0x166,
  boundAngle: 0x16a,
};

function heroAddr() {
  return ADDR.heroBase;
}

function readS32(address) {
  try { return address.readS32(); } catch (error) { return null; }
}

function readU32(address) {
  try { return address.readU32(); } catch (error) { return null; }
}

function readSnapshot() {
  const hero = heroAddr();
  const bound = hero.add(OFF.boundAngle);
  return {
    module_name: mainModule.name,
    module_base: base.toString(),
    hero_base: hero.toString(),
    old_x: readS32(hero.add(OFF.oldX)),
    old_y: readS32(hero.add(OFF.oldY)),
    old_z: readS32(hero.add(OFF.oldZ)),
    x: readS32(hero.add(OFF.x)),
    y: readS32(hero.add(OFF.y)),
    z: readS32(hero.add(OFF.z)),
    beta: readU32(hero.add(OFF.beta)),
    old_beta: readS32(hero.add(OFF.oldBeta)),
    bound_angle: {
      move_speed: readS32(bound.add(0x0)),
      move_acc: readS32(bound.add(0x4)),
      move_last_timer: readU32(bound.add(0x8)),
      cur: readS32(bound.add(0xc)),
      end: readS32(bound.add(0x10)),
    },
  };
}

function applyHeading(targetBeta, syncBoundAngle, setOldBeta) {
  const beta = ((targetBeta % 4096) + 4096) % 4096;
  const hero = heroAddr();
  const bound = hero.add(OFF.boundAngle);

  hero.add(OFF.beta).writeU16(beta);
  if (setOldBeta) {
    hero.add(OFF.oldBeta).writeS32(beta);
  }
  if (syncBoundAngle) {
    bound.add(0x0).writeS32(0);       // Move.Speed
    bound.add(0x4).writeS32(0);       // Move.Acc
    bound.add(0x8).writeU32(0);       // Move.LastTimer
    bound.add(0xc).writeS32(beta);    // Cur
    bound.add(0x10).writeS32(beta);   // End
  }
  return readSnapshot();
}

function applyTeleport(targetX, targetY, targetZ, syncOldPosition) {
  const hero = heroAddr();
  hero.add(OFF.x).writeS32(targetX);
  hero.add(OFF.y).writeS32(targetY);
  hero.add(OFF.z).writeS32(targetZ);
  if (syncOldPosition) {
    hero.add(OFF.oldX).writeS32(targetX);
    hero.add(OFF.oldY).writeS32(targetY);
    hero.add(OFF.oldZ).writeS32(targetZ);
  }
  return readSnapshot();
}

rpc.exports = {
  snapshot() {
    return readSnapshot();
  },
  applyheading(targetBeta, syncBoundAngle, setOldBeta) {
    return applyHeading(targetBeta, !!syncBoundAngle, !!setOldBeta);
  },
  applyteleport(targetX, targetY, targetZ, syncOldPosition) {
    return applyTeleport(targetX, targetY, targetZ, !!syncOldPosition);
  },
};
"""


def resolve_target_process(frida, device, *, pid: int | None, process_name: str | None):
    if pid is not None:
        return pid
    if not process_name:
        raise RuntimeError("either pid or process_name is required")
    target = process_name.lower()
    for process in device.enumerate_processes():
        if process.name.lower() == target:
            return process.pid
    raise RuntimeError(f"process not found: {process_name}")


def enrich_snapshot(snapshot: dict[str, Any]) -> dict[str, Any]:
    beta = int(snapshot["beta"])
    enriched = dict(snapshot)
    enriched["beta_debug"] = describe_beta(beta)
    return enriched


class HeadingInjector:
    def __init__(
        self,
        *,
        pid: int | None = None,
        process_name: str = DEFAULT_PROCESS_NAME,
        frida_repo_root: Path = DEFAULT_FRIDA_REPO,
    ) -> None:
        self.pid = pid
        self.process_name = process_name
        self.frida_repo_root = Path(frida_repo_root)
        self._frida = None
        self._device = None
        self._session = None
        self._script = None
        self.target_pid: int | None = None

    def connect(self) -> None:
        if self._script is not None:
            return
        self._frida = import_frida(self.frida_repo_root)
        self._device = self._frida.get_local_device()
        self.target_pid = resolve_target_process(
            self._frida,
            self._device,
            pid=self.pid,
            process_name=self.process_name,
        )
        self._session = self._frida.attach(self.target_pid)
        self._script = self._session.create_script(build_script())
        self._script.load()

    def close(self) -> None:
        if self._script is not None:
            try:
                self._script.unload()
            except Exception:
                pass
            self._script = None
        if self._session is not None:
            try:
                self._session.detach()
            except Exception:
                pass
            self._session = None

    def __enter__(self) -> "HeadingInjector":
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def snapshot(self) -> dict[str, Any]:
        self.connect()
        payload = self._script.exports_sync.snapshot()
        return enrich_snapshot(payload)

    def force_heading_beta(
        self,
        target_beta: int,
        *,
        sync_bound_angle: bool = True,
        set_old_beta: bool = True,
        sustain_ms: int = 0,
        interval_ms: int = 16,
        verify_tolerance_beta: int | None = 64,
    ) -> dict[str, Any]:
        self.connect()
        target_beta = normalize_beta(target_beta)
        snapshot = self._script.exports_sync.applyheading(target_beta, sync_bound_angle, set_old_beta)
        start = time.monotonic()
        if sustain_ms > 0:
            interval_sec = max(interval_ms, 1) / 1000.0
            deadline = start + sustain_ms / 1000.0
            while time.monotonic() < deadline:
                time.sleep(interval_sec)
                snapshot = self._script.exports_sync.applyheading(target_beta, sync_bound_angle, set_old_beta)
        verified = enrich_snapshot(snapshot)
        final_delta = shortest_beta_delta(int(verified["beta"]), target_beta)
        verified["target_beta"] = target_beta
        verified["target_beta_debug"] = describe_beta(target_beta)
        verified["final_delta_beta"] = final_delta
        verified["verify_tolerance_beta"] = verify_tolerance_beta
        verified["verified_within_tolerance"] = (
            None if verify_tolerance_beta is None else abs(final_delta) <= verify_tolerance_beta
        )
        verified["sync_bound_angle"] = sync_bound_angle
        verified["set_old_beta"] = set_old_beta
        verified["sustain_ms"] = sustain_ms
        verified["interval_ms"] = interval_ms
        return verified

    def teleport_xyz(
        self,
        target_x: int,
        target_y: int,
        target_z: int,
        *,
        sync_old_position: bool = True,
    ) -> dict[str, Any]:
        self.connect()
        snapshot = self._script.exports_sync.applyteleport(
            int(target_x),
            int(target_y),
            int(target_z),
            sync_old_position,
        )
        verified = enrich_snapshot(snapshot)
        verified["target_position"] = {
            "x": int(target_x),
            "y": int(target_y),
            "z": int(target_z),
        }
        verified["sync_old_position"] = sync_old_position
        verified["final_delta_position"] = {
            "x": (None if verified.get("x") is None else int(verified["x"]) - int(target_x)),
            "y": (None if verified.get("y") is None else int(verified["y"]) - int(target_y)),
            "z": (None if verified.get("z") is None else int(verified["z"]) - int(target_z)),
        }
        return verified


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Debugger-side heading injection for original-runtime LBA2.EXE."
    )
    target = parser.add_mutually_exclusive_group(required=False)
    target.add_argument("--attach-pid", type=int, help="Attach to an already running LBA2.EXE pid.")
    target.add_argument("--process-name", default=DEFAULT_PROCESS_NAME, help="Exact process name to attach to.")

    heading = parser.add_mutually_exclusive_group(required=True)
    heading.add_argument("--beta", type=int, help="Target heading in classic beta units.")
    heading.add_argument("--degrees", type=float, help="Target heading in debug-compass degrees.")
    heading.add_argument("--heading", choices=tuple(sorted({"N", "NE", "E", "SE", "S", "SW", "W", "NW"})), help="Target debug-compass heading.")

    parser.add_argument("--frida-repo-root", default=str(DEFAULT_FRIDA_REPO), help="Frida repo root containing build/install-root.")
    parser.add_argument("--sustain-ms", type=int, default=0, help="Optionally reapply the heading for this long after the first write.")
    parser.add_argument("--interval-ms", type=int, default=16, help="Reapply interval when sustain-ms is active.")
    parser.add_argument("--verify-tolerance-beta", type=int, default=64, help="Heading error tolerance for the post-write verification.")
    parser.add_argument("--no-sync-bound-angle", action="store_true", help="Only write Obj.Beta and skip BoundAngle synchronization.")
    parser.add_argument("--no-set-old-beta", action="store_true", help="Do not rewrite OldBeta to the target heading.")
    parser.add_argument("--output", help="Optional JSON output path.")
    return parser.parse_args()


def resolve_target_beta_from_args(args: argparse.Namespace) -> int:
    if args.beta is not None:
        return normalize_beta(args.beta)
    if args.degrees is not None:
        return degrees_to_beta(args.degrees)
    if args.heading is not None:
        return heading_to_beta(args.heading)
    raise RuntimeError("one of --beta/--degrees/--heading is required")


def main() -> int:
    args = parse_args()
    target_beta = resolve_target_beta_from_args(args)
    injector = HeadingInjector(
        pid=args.attach_pid,
        process_name=args.process_name,
        frida_repo_root=Path(args.frida_repo_root),
    )
    with injector:
        before = injector.snapshot()
        after = injector.force_heading_beta(
            target_beta,
            sync_bound_angle=not args.no_sync_bound_angle,
            set_old_beta=not args.no_set_old_beta,
            sustain_ms=args.sustain_ms,
            interval_ms=args.interval_ms,
            verify_tolerance_beta=args.verify_tolerance_beta,
        )
    payload = {
        "before": before,
        "after": after,
    }
    rendered = json.dumps(payload, indent=2)
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
