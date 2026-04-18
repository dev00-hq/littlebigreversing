from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from queue import Empty, SimpleQueue
from typing import Any

from heading_inject import DEFAULT_FRIDA_REPO, DEFAULT_PROCESS_NAME, import_frida, resolve_target_process


def build_script() -> str:
    return r"""
const imageBase = ptr('0x00400000');
const mainModule = Process.enumerateModules().find((module) => module.name.toLowerCase() === 'lba2.exe') || Process.enumerateModules()[0];
const base = mainModule.base;

function absAddr(absolute) {
  return base.add(ptr(absolute).sub(imageBase));
}

const ADDR = {
  fun_43a274: absAddr('0x0043a274'),
  heroBase: absAddr('0x0049a19c'),
  flagChgCube: absAddr('0x00499e40'),
  newCube: absAddr('0x00499e44'),
};

function readS32(address) {
  try { return address.readS32(); } catch (error) { return null; }
}

function readU32(address) {
  try { return address.readU32(); } catch (error) { return null; }
}

function readSnapshot() {
  const hero = ADDR.heroBase;
  return {
    globals: {
      flag_chg_cube: readS32(ADDR.flagChgCube),
      new_cube: readS32(ADDR.newCube),
    },
    hero: {
      old_x: readS32(hero.add(0x08)),
      old_y: readS32(hero.add(0x0c)),
      old_z: readS32(hero.add(0x10)),
      x: readS32(hero.add(0x3e)),
      y: readS32(hero.add(0x42)),
      z: readS32(hero.add(0x46)),
      beta: readU32(hero.add(0x4e)),
    },
  };
}

function sendEvent(kind, payload) {
  send({ kind, payload });
}

sendEvent('status', {
  message: 'collision observer loaded',
  pid: Process.id,
  module_name: mainModule.name,
  module_base: base.toString(),
  hook_43a274: ADDR.fun_43a274.toString(),
  snapshot: readSnapshot(),
});

Interceptor.attach(ADDR.fun_43a274, {
  onEnter(args) {
    this.objectIndex = args[0].toUInt32() & 0xff;
    this.log = this.objectIndex === 0;
    if (!this.log) {
      return;
    }
    this.before = readSnapshot();
  },
  onLeave(retval) {
    if (!this.log) {
      return;
    }
    const after = readSnapshot();
    const restored =
      after.hero.x === after.hero.old_x &&
      after.hero.y === after.hero.old_y &&
      after.hero.z === after.hero.old_z;
    sendEvent('hero_tick_leave', {
      object_index: this.objectIndex,
      retval: retval.toString(),
      restored_to_old: restored,
      before: this.before,
      after,
    });
  }
});
"""


def _same_position(a: dict[str, Any], b: dict[str, Any], delta: int) -> bool:
    return (
        abs(int(a["x"]) - int(b["x"])) <= delta
        and abs(int(a["y"]) - int(b["y"])) <= delta
        and abs(int(a["z"]) - int(b["z"])) <= delta
    )


def _planar_l1(a: dict[str, Any], b: dict[str, Any]) -> int:
    return abs(int(a["x"]) - int(b["x"])) + abs(int(a["z"]) - int(b["z"]))


class CollisionObserver:
    def __init__(
        self,
        *,
        pid: int | None = None,
        process_name: str = DEFAULT_PROCESS_NAME,
        frida_repo_root: Path = DEFAULT_FRIDA_REPO,
        same_pos_delta: int = 8,
        restored_streak_threshold: int = 6,
        arm_after_reset_sec: float = 0.12,
        initial_pose_delta: int = 24,
        escape_planar_l1_threshold: int = 96,
        minimum_detection_hero_ticks: int = 96,
    ) -> None:
        self.pid = pid
        self.process_name = process_name
        self.frida_repo_root = Path(frida_repo_root)
        self.same_pos_delta = same_pos_delta
        self.restored_streak_threshold = restored_streak_threshold
        self.arm_after_reset_sec = arm_after_reset_sec
        self.initial_pose_delta = initial_pose_delta
        self.escape_planar_l1_threshold = escape_planar_l1_threshold
        self.minimum_detection_hero_ticks = minimum_detection_hero_ticks
        self._frida = None
        self._device = None
        self._session = None
        self._script = None
        self._queue: SimpleQueue[dict[str, Any]] = SimpleQueue()
        self._lock = threading.Lock()
        self.target_pid: int | None = None
        self._status_payload: dict[str, Any] | None = None
        self._window_started_t_monotonic: float | None = None
        self._window_initial_hero: dict[str, Any] | None = None
        self._hero_tick_count = 0
        self._restored_streak = 0
        self._max_restored_streak = 0
        self._pin_candidate_detected = False
        self._diagnostic_pin_detected = False
        self._pin_detection_count = 0
        self._diagnostic_pin_invalidated_by_escape = False
        self._first_pin_t_monotonic: float | None = None
        self._first_pin_hero: dict[str, Any] | None = None
        self._window_max_planar_l1_from_initial = 0
        self._window_pose_changed = False
        self._escape_from_initial_detected = False
        self._first_escape_t_monotonic: float | None = None
        self._first_escape_hero: dict[str, Any] | None = None
        self._first_escape_planar_l1: int | None = None
        self._last_after: dict[str, Any] | None = None
        self._last_hero: dict[str, Any] | None = None

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

        def on_message(message: dict[str, Any], data: Any) -> None:
            if message.get("type") != "send":
                return
            payload = message.get("payload")
            if not isinstance(payload, dict):
                return
            kind = str(payload.get("kind", "send"))
            body = payload.get("payload", {})
            if not isinstance(body, dict):
                body = {"value": body}
            event = {"kind": kind, "payload": body}
            self._queue.put(event)
            self._process_event(event)

        self._script.on("message", on_message)
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

    def __enter__(self) -> "CollisionObserver":
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _process_event(self, event: dict[str, Any]) -> None:
        kind = event["kind"]
        payload = event["payload"]
        with self._lock:
            if kind == "status":
                self._status_payload = payload
                return
            if kind != "hero_tick_leave":
                return

            self._hero_tick_count += 1
            if self._window_started_t_monotonic is None:
                self._window_started_t_monotonic = time.monotonic()

            after = payload["after"]["hero"]
            self._last_hero = after
            if self._window_initial_hero is None:
                self._window_initial_hero = dict(after)
            initial = self._window_initial_hero

            planar_from_initial = _planar_l1(initial, after)
            if planar_from_initial > self._window_max_planar_l1_from_initial:
                self._window_max_planar_l1_from_initial = planar_from_initial
            if planar_from_initial > self.initial_pose_delta:
                self._window_pose_changed = True
            if (
                not self._escape_from_initial_detected
                and planar_from_initial > self.escape_planar_l1_threshold
            ):
                self._escape_from_initial_detected = True
                self._first_escape_t_monotonic = time.monotonic()
                self._first_escape_hero = dict(after)
                self._first_escape_planar_l1 = planar_from_initial
                if self._diagnostic_pin_detected:
                    self._diagnostic_pin_detected = False
                    self._diagnostic_pin_invalidated_by_escape = True

            arm_elapsed = time.monotonic() - self._window_started_t_monotonic
            if arm_elapsed < self.arm_after_reset_sec:
                self._last_after = after
                return

            restored = bool(payload.get("restored_to_old", False))
            if restored:
                if self._last_after is None or _same_position(after, self._last_after, self.same_pos_delta):
                    self._restored_streak += 1
                else:
                    self._restored_streak = 1
            else:
                self._restored_streak = 0
            if self._restored_streak > self._max_restored_streak:
                self._max_restored_streak = self._restored_streak

            if (
                not self._pin_candidate_detected
                and self._restored_streak >= self.restored_streak_threshold
                and self._hero_tick_count >= self.minimum_detection_hero_ticks
            ):
                self._pin_candidate_detected = True
                self._pin_detection_count += 1
                self._first_pin_t_monotonic = time.monotonic()
                self._first_pin_hero = dict(after)
                if not self._escape_from_initial_detected:
                    self._diagnostic_pin_detected = True

            self._last_after = after

    def drain_events(self) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        while True:
            try:
                events.append(self._queue.get_nowait())
            except Empty:
                return events

    def reset_window(self) -> None:
        self.drain_events()
        with self._lock:
            self._window_started_t_monotonic = None
            self._window_initial_hero = None
            self._hero_tick_count = 0
            self._restored_streak = 0
            self._max_restored_streak = 0
            self._pin_candidate_detected = False
            self._diagnostic_pin_detected = False
            self._pin_detection_count = 0
            self._diagnostic_pin_invalidated_by_escape = False
            self._first_pin_t_monotonic = None
            self._first_pin_hero = None
            self._window_max_planar_l1_from_initial = 0
            self._window_pose_changed = False
            self._escape_from_initial_detected = False
            self._first_escape_t_monotonic = None
            self._first_escape_hero = None
            self._first_escape_planar_l1 = None
            self._last_after = None
            self._last_hero = None

    def state(self) -> dict[str, Any]:
        with self._lock:
            arm_elapsed = (
                0.0
                if self._window_started_t_monotonic is None
                else time.monotonic() - self._window_started_t_monotonic
            )
            return {
                "pid": self.target_pid,
                "observer_kind": "diagnostic_same_pose_restore_with_escape_invalidation",
                "diagnostic_only": True,
                "observer_contract": "diagnostic restore-pin candidate only; final live collision requires no later escape beyond threshold",
                "same_pos_delta": self.same_pos_delta,
                "restored_streak_threshold": self.restored_streak_threshold,
                "arm_after_reset_sec": self.arm_after_reset_sec,
                "initial_pose_delta": self.initial_pose_delta,
                "escape_planar_l1_threshold": self.escape_planar_l1_threshold,
                "minimum_detection_hero_ticks": self.minimum_detection_hero_ticks,
                "arm_elapsed_sec": arm_elapsed,
                "hero_tick_count": self._hero_tick_count,
                "restored_streak": self._restored_streak,
                "max_restored_streak": self._max_restored_streak,
                "pin_candidate_detected": self._pin_candidate_detected,
                "diagnostic_pin_detected": self._diagnostic_pin_detected,
                "pin_detection_count": self._pin_detection_count,
                "diagnostic_pin_invalidated_by_escape": self._diagnostic_pin_invalidated_by_escape,
                "first_pin_t_monotonic": self._first_pin_t_monotonic,
                "first_pin_hero": self._first_pin_hero,
                "window_initial_hero": self._window_initial_hero,
                "window_max_planar_l1_from_initial": self._window_max_planar_l1_from_initial,
                "window_pose_changed": self._window_pose_changed,
                "escape_from_initial_detected": self._escape_from_initial_detected,
                "first_escape_t_monotonic": self._first_escape_t_monotonic,
                "first_escape_hero": self._first_escape_hero,
                "first_escape_planar_l1": self._first_escape_planar_l1,
                "last_hero": self._last_hero,
                "status": self._status_payload,
            }


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Attach a diagnostic collision observer to LBA2.EXE.")
    parser.add_argument("--attach-pid", type=int, help="Attach to an already running pid.")
    parser.add_argument("--process-name", default=DEFAULT_PROCESS_NAME)
    parser.add_argument("--frida-repo-root", default=str(DEFAULT_FRIDA_REPO))
    parser.add_argument("--same-pos-delta", type=int, default=8)
    parser.add_argument("--restored-streak-threshold", type=int, default=6)
    parser.add_argument("--arm-after-reset-sec", type=float, default=0.12)
    parser.add_argument("--initial-pose-delta", type=int, default=24)
    parser.add_argument("--escape-planar-l1-threshold", type=int, default=96)
    parser.add_argument("--minimum-detection-hero-ticks", type=int, default=96)
    parser.add_argument("--duration-sec", type=float, default=5.0)
    parser.add_argument("--output", help="Optional JSON output path.")
    args = parser.parse_args()

    with CollisionObserver(
        pid=args.attach_pid,
        process_name=args.process_name,
        frida_repo_root=Path(args.frida_repo_root),
        same_pos_delta=args.same_pos_delta,
        restored_streak_threshold=args.restored_streak_threshold,
        arm_after_reset_sec=args.arm_after_reset_sec,
        initial_pose_delta=args.initial_pose_delta,
        escape_planar_l1_threshold=args.escape_planar_l1_threshold,
        minimum_detection_hero_ticks=args.minimum_detection_hero_ticks,
    ) as observer:
        time.sleep(args.duration_sec)
        payload = {
            "state": observer.state(),
            "events": observer.drain_events(),
        }
    rendered = json.dumps(payload, indent=2)
    if args.output:
        Path(args.output).write_text(rendered, encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
