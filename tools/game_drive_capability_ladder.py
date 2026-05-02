from __future__ import annotations

import argparse
import copy
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools import game_drive_runner  # noqa: E402

FIXTURE_ROOT = REPO_ROOT / "tools" / "fixtures" / "game_drive_checkpoints"
DEFAULT_OUT_ROOT = REPO_ROOT / "work" / "game_drive_capability_ladder"


class CapabilityLadderError(Exception):
    pass


@dataclass(frozen=True)
class CapabilityCase:
    id: str
    base_checkpoint: str
    actions: tuple[str, ...]
    required_signals: tuple[str, ...]
    description: str


CAPABILITIES = (
    CapabilityCase(
        id="load_visual_gate",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=(),
        required_signals=(),
        description="Named-save launch, autosave guard, runtime globals, and visual classifier gate.",
    ),
    CapabilityCase(
        id="rotation_left",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("hold_left_0_50_sec_release",),
        required_signals=("hero_beta",),
        description="Keyboard rotation changes the live Twinsen beta field.",
    ),
    CapabilityCase(
        id="translation_forward",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("hold_up_0_50_sec_release",),
        required_signals=("hero_x|hero_z",),
        description="Keyboard forward movement changes Twinsen world position.",
    ),
    CapabilityCase(
        id="magic_ball_throw",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("hold_period_0_75_sec_release",),
        required_signals=("extras",),
        description="Action key launches a Magic Ball projectile visible in runtime extras.",
    ),
    CapabilityCase(
        id="dialogue_open",
        base_checkpoint="pose_ready_voisin_dialogue.json",
        actions=("press_w_0_18_sec",),
        required_signals=("dialog",),
        description="Talk action opens a runtime dialog record through CurrentDial/PtText/PtDial.",
    ),
    CapabilityCase(
        id="behavior_cycle",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("ctrl_right_behavior_cycle",),
        required_signals=("comportement",),
        description="Ctrl+Right behavior-cycle input changes the live Comportement field.",
    ),
    CapabilityCase(
        id="direct_pose_visual_gate",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=(),
        required_signals=(),
        description="Direct-pose write to the declared safe pose plus live-window screenshot classification.",
    ),
)


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise CapabilityLadderError(f"expected JSON object: {path}")
    return value


def materialize_checkpoint(case: CapabilityCase, checkpoint_dir: Path) -> Path:
    base_path = FIXTURE_ROOT / case.base_checkpoint
    checkpoint = copy.deepcopy(load_json(base_path))
    checkpoint["id"] = f"capability_{case.id}"
    checkpoint["actions_after_checkpoint"] = list(case.actions)
    if case.id == "direct_pose_visual_gate":
        checkpoint["setup"]["pose"]["method"] = "direct_pose"
        checkpoint["visual_expect"]["source"] = "live_window_capture"
    path = checkpoint_dir / f"{checkpoint['id']}.json"
    write_json(path, checkpoint)
    return path


def has_signal(changed: dict[str, Any], signal: str) -> bool:
    if signal == "extras":
        values = changed.get("extras", [])
        return any(isinstance(value, dict) and value.get("active_extra_count", 0) > 0 for value in values)
    if signal == "dialog":
        values = changed.get("dialog", [])
        return any(isinstance(value, dict) and value.get("current_dial", 0) not in {0, -1} for value in values)
    if signal == "any_runtime_change":
        return bool(changed)
    if "|" in signal:
        return any(name in changed for name in signal.split("|"))
    return signal in changed


def action_has_signal(action: dict[str, Any], signal: str) -> bool:
    changed = action.get("poll", {}).get("changed_fields", {})
    if has_signal(changed, signal):
        return True
    samples = action.get("poll", {}).get("samples", [])
    if signal == "dialog":
        return any(
            isinstance(sample, dict)
            and isinstance(sample.get("dialog"), dict)
            and sample["dialog"].get("current_dial", 0) not in {0, -1}
            for sample in samples
        )
    if signal == "extras":
        return any(
            isinstance(sample, dict)
            and isinstance(sample.get("extras"), dict)
            and sample["extras"].get("active_extra_count", 0) > 0
            for sample in samples
        )
    return False


def evaluate_case(case: CapabilityCase, result: dict[str, Any]) -> dict[str, Any]:
    if result.get("verdict") != "passed":
        return {
            "id": case.id,
            "verdict": "failed",
            "description": case.description,
            "reason": f"checkpoint verdict was {result.get('verdict')}",
            "run_dir": result.get("run_dir"),
        }
    action = result.get("actions", [{}])[0] if case.actions else {}
    changed = action.get("poll", {}).get("changed_fields", {}) if action else {}
    missing = [signal for signal in case.required_signals if not action_has_signal(action, signal)]
    return {
        "id": case.id,
        "verdict": "passed" if not missing else "blocked",
        "description": case.description,
        "checkpoint_id": result.get("checkpoint_id"),
        "run_dir": result.get("run_dir"),
        "actions": list(case.actions),
        "required_signals": list(case.required_signals),
        "changed_fields": sorted(changed.keys()),
        "missing_signals": missing,
    }


def run_ladder(cases: tuple[CapabilityCase, ...], out_root: Path) -> dict[str, Any]:
    checkpoint_dir = out_root / "checkpoints"
    run_root = out_root / "runs"
    reports = []
    for case in cases:
        checkpoint_path = materialize_checkpoint(case, checkpoint_dir)
        try:
            result = game_drive_runner.run_checkpoint(
                checkpoint_path,
                out_root=run_root,
                save_root=game_drive_runner.DEFAULT_SAVE_DIR,
                exe=game_drive_runner.DEFAULT_GAME_EXE,
            )
            reports.append(evaluate_case(case, result))
        except Exception as error:
            reports.append(
                {
                    "id": case.id,
                    "verdict": "blocked",
                    "description": case.description,
                    "checkpoint": game_drive_runner.repo_relative(checkpoint_path),
                    "actions": list(case.actions),
                    "required_signals": list(case.required_signals),
                    "reason": str(error),
                }
            )
    payload = {
        "schema": "game-drive-capability-ladder-v1",
        "out_root": game_drive_runner.repo_relative(out_root),
        "results": reports,
        "verdict": "passed" if all(report["verdict"] == "passed" for report in reports) else "blocked",
    }
    write_json(out_root / "summary.json", payload)
    return payload


def selected_cases(names: list[str] | None) -> tuple[CapabilityCase, ...]:
    if not names:
        return CAPABILITIES
    by_id = {case.id: case for case in CAPABILITIES}
    unknown = [name for name in names if name not in by_id]
    if unknown:
        raise CapabilityLadderError(f"unknown capability case(s): {', '.join(unknown)}")
    return tuple(by_id[name] for name in names)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the original-runtime game-drive capability ladder.")
    parser.add_argument("--out-root", type=Path, default=DEFAULT_OUT_ROOT)
    parser.add_argument("--case", action="append", choices=[case.id for case in CAPABILITIES])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    try:
        payload = run_ladder(selected_cases(args.case), args.out_root)
    except Exception as error:
        if args.json:
            print(json.dumps({"schema": "game-drive-capability-ladder-v1", "verdict": "error", "error": str(error)}, indent=2))
        else:
            print(f"game-drive capability ladder failed: {error}")
        return 1

    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        for result in payload["results"]:
            print(f"{result['id']}: {result['verdict']}")
        print(f"verdict: {payload['verdict']}")
    return 0 if payload["verdict"] == "passed" else 2


if __name__ == "__main__":
    raise SystemExit(main())
