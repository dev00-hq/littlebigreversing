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


RUNNER_SUCCESS_VERDICTS = {"passed", "checkpoint_passed_actions_recorded"}


@dataclass(frozen=True)
class ActionSequenceExpectation:
    action: str
    field: str
    values: tuple[Any, ...]


@dataclass(frozen=True)
class ActionFinalExpectation:
    action: str
    field: str
    value: Any


@dataclass(frozen=True)
class ActionDeltaExpectation:
    action: str
    field: str
    min_delta: int
    max_delta: int
    mode: str = "signed"


@dataclass(frozen=True)
class ExtraRowExpectation:
    sprite: int
    owner: int
    body: int
    hit_force: int
    min_count: int = 1


@dataclass(frozen=True)
class ActionExtrasExpectation:
    action: str
    active_count_sequence: tuple[int, ...]
    required_rows: tuple[ExtraRowExpectation, ...]


@dataclass(frozen=True)
class CapabilityCase:
    id: str
    base_checkpoint: str
    actions: tuple[str, ...]
    required_signals: tuple[str, ...]
    description: str
    pose_coordinates: dict[str, int] | None = None
    expected_sequences: tuple[ActionSequenceExpectation, ...] = ()
    expected_finals: tuple[ActionFinalExpectation, ...] = ()
    expected_deltas: tuple[ActionDeltaExpectation, ...] = ()
    expected_extras: tuple[ActionExtrasExpectation, ...] = ()


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
        description="Keyboard left rotation increases Twinsen beta by the expected range from the known start pose.",
        expected_deltas=(
            ActionDeltaExpectation(
                action="hold_left_0_50_sec_release",
                field="hero_beta",
                min_delta=500,
                max_delta=1300,
                mode="beta4096",
            ),
        ),
    ),
    CapabilityCase(
        id="translation_forward",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("hold_up_0_50_sec_release",),
        required_signals=("hero_x|hero_z",),
        description="Keyboard forward movement advances Twinsen along the expected axis from the known heading.",
        expected_deltas=(
            ActionDeltaExpectation(
                action="hold_up_0_50_sec_release",
                field="hero_x",
                min_delta=-1200,
                max_delta=-300,
            ),
            ActionDeltaExpectation(
                action="hold_up_0_50_sec_release",
                field="hero_z",
                min_delta=-100,
                max_delta=100,
            ),
        ),
    ),
    CapabilityCase(
        id="magic_ball_throw",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_1_0_08_sec", "hold_period_0_75_sec_release"),
        required_signals=("extras",),
        description="Selecting Magic Ball with 1, then holding action, launches and resolves the expected projectile extras.",
        expected_deltas=(
            ActionDeltaExpectation(
                action="hold_period_0_75_sec_release",
                field="magic_point",
                min_delta=-1,
                max_delta=-1,
            ),
        ),
        expected_extras=(
            ActionExtrasExpectation(
                action="hold_period_0_75_sec_release",
                active_count_sequence=(),
                required_rows=(
                    ExtraRowExpectation(sprite=10, owner=0, body=-1, hit_force=30, min_count=2),
                    ExtraRowExpectation(sprite=14, owner=255, body=-1, hit_force=0, min_count=1),
                ),
            ),
        ),
    ),
    CapabilityCase(
        id="dialogue_open",
        base_checkpoint="pose_ready_voisin_dialogue.json",
        actions=("press_w_0_18_sec",),
        required_signals=("dialog",),
        description="Talk action opens the expected Voisin dialog record through CurrentDial/PtText/PtDial.",
        expected_sequences=(
            ActionSequenceExpectation(
                action="press_w_0_18_sec",
                field="dialog.current_dial",
                values=(504,),
            ),
            ActionSequenceExpectation(
                action="press_w_0_18_sec",
                field="dialog.cursor_offset",
                values=(15,),
            ),
        ),
    ),
    CapabilityCase(
        id="behavior_cycle",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("ctrl_right_behavior_cycle",),
        required_signals=("comportement",),
        description="Ctrl+Right behavior-cycle input changes the live Comportement field from Sporty to Aggressive.",
        expected_sequences=(
            ActionSequenceExpectation(
                action="ctrl_right_behavior_cycle",
                field="comportement",
                values=(1, 2),
            ),
        ),
    ),
    CapabilityCase(
        id="behavior_direct_f5_f8",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f5_0_08_sec", "press_f6_0_08_sec", "press_f7_0_08_sec", "press_f8_0_08_sec"),
        required_signals=("comportement",),
        description="Direct F5/F6/F7/F8 behavior keys set live Comportement to Normal, Sporty, Aggressive, and Discreet after a live visual gate.",
        expected_finals=(
            ActionFinalExpectation(action="press_f5_0_08_sec", field="comportement", value=0),
            ActionFinalExpectation(action="press_f6_0_08_sec", field="comportement", value=1),
            ActionFinalExpectation(action="press_f7_0_08_sec", field="comportement", value=2),
            ActionFinalExpectation(action="press_f8_0_08_sec", field="comportement", value=3),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_normal",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f5_0_08_sec", "hold_up_0_50_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Normal mode, same safe pose, fixed 0.50s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        expected_finals=(
            ActionFinalExpectation(action="press_f5_0_08_sec", field="comportement", value=0),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_sporty",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f6_0_08_sec", "hold_up_0_50_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Sporty mode, same safe pose, fixed 0.50s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        expected_finals=(
            ActionFinalExpectation(action="press_f6_0_08_sec", field="comportement", value=1),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_aggressive",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f7_0_08_sec", "hold_up_0_50_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Aggressive mode, same safe pose, fixed 0.50s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        expected_finals=(
            ActionFinalExpectation(action="press_f7_0_08_sec", field="comportement", value=2),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_discreet",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f8_0_08_sec", "hold_up_0_50_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Discreet mode, same safe pose, fixed 0.50s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        expected_finals=(
            ActionFinalExpectation(action="press_f8_0_08_sec", field="comportement", value=3),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_0_50_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_pose2_normal",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f5_0_08_sec", "hold_up_1_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Normal mode, second safe heading, fixed 1.00s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f5_0_08_sec", field="comportement", value=0),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_pose2_sporty",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f6_0_08_sec", "hold_up_1_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Sporty mode, second safe heading, fixed 1.00s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f6_0_08_sec", field="comportement", value=1),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_pose2_aggressive",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f7_0_08_sec", "hold_up_1_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Aggressive mode, second safe heading, fixed 1.00s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f7_0_08_sec", field="comportement", value=2),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_speed_pose2_discreet",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f8_0_08_sec", "hold_up_1_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only movement-speed probe: Discreet mode, second safe heading, fixed 1.00s forward hold, records live x/z/beta deltas plus before/after screenshots.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f8_0_08_sec", field="comportement", value=3),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_1_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_normal",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f5_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Normal mode, same second safe heading, fixed 2.00s forward hold, records runtime position time series.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f5_0_08_sec", field="comportement", value=0),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_sporty",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f6_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Sporty mode, same second safe heading, fixed 2.00s forward hold, records runtime position time series.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f6_0_08_sec", field="comportement", value=1),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_aggressive",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f7_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Aggressive mode, same second safe heading, fixed 2.00s forward hold, records runtime position time series.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f7_0_08_sec", field="comportement", value=2),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_discreet",
        base_checkpoint="pose_ready_magic_ball_middle_switch.json",
        actions=("press_f8_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Discreet mode, same second safe heading, fixed 2.00s forward hold, records runtime position time series.",
        pose_coordinates={"x": 4866, "y": 512, "z": 8324, "beta": 2760},
        expected_finals=(
            ActionFinalExpectation(action="press_f8_0_08_sec", field="comportement", value=3),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_otringal_normal",
        base_checkpoint="pose_ready_otringal_open.json",
        actions=("press_f5_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Normal mode, operator-prepared open Otringal save, fixed 2.00s forward hold, records runtime position time series.",
        expected_finals=(
            ActionFinalExpectation(action="press_f5_0_08_sec", field="comportement", value=0),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_otringal_sporty",
        base_checkpoint="pose_ready_otringal_open.json",
        actions=("press_f6_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Sporty mode, operator-prepared open Otringal save, fixed 2.00s forward hold, records runtime position time series.",
        expected_finals=(
            ActionFinalExpectation(action="press_f6_0_08_sec", field="comportement", value=1),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_otringal_aggressive",
        base_checkpoint="pose_ready_otringal_open.json",
        actions=("press_f7_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Aggressive mode, operator-prepared open Otringal save, fixed 2.00s forward hold, records runtime position time series.",
        expected_finals=(
            ActionFinalExpectation(action="press_f7_0_08_sec", field="comportement", value=2),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
    ),
    CapabilityCase(
        id="behavior_accel_otringal_discreet",
        base_checkpoint="pose_ready_otringal_open.json",
        actions=("press_f8_0_08_sec", "hold_up_2_00_sec_release"),
        required_signals=("hero_x|hero_z",),
        description="Evidence-only acceleration probe: Discreet mode, operator-prepared open Otringal save, fixed 2.00s forward hold, records runtime position time series.",
        expected_finals=(
            ActionFinalExpectation(action="press_f8_0_08_sec", field="comportement", value=3),
        ),
        expected_deltas=(
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_x", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_z", min_delta=-100000, max_delta=100000),
            ActionDeltaExpectation(action="hold_up_2_00_sec_release", field="hero_beta", min_delta=0, max_delta=4095, mode="beta4096"),
        ),
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
    if case.pose_coordinates is not None:
        checkpoint["setup"]["pose"]["coordinates"] = dict(case.pose_coordinates)
    if case.id in {
        "direct_pose_visual_gate",
        "rotation_left",
        "translation_forward",
        "magic_ball_throw",
        "behavior_direct_f5_f8",
        "behavior_speed_normal",
        "behavior_speed_sporty",
        "behavior_speed_aggressive",
        "behavior_speed_discreet",
        "behavior_speed_pose2_normal",
        "behavior_speed_pose2_sporty",
        "behavior_speed_pose2_aggressive",
        "behavior_speed_pose2_discreet",
        "behavior_accel_normal",
        "behavior_accel_sporty",
        "behavior_accel_aggressive",
        "behavior_accel_discreet",
    }:
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


def compact_values(values: list[Any]) -> list[Any]:
    compacted: list[Any] = []
    for value in values:
        if not compacted or compacted[-1] != value:
            compacted.append(value)
    return compacted


def read_nested(value: dict[str, Any], field: str) -> Any:
    current: Any = value
    for part in field.split("."):
        if not isinstance(current, dict) or part not in current:
            return None
        current = current[part]
    return current


def observed_action_sequence(action: dict[str, Any], field: str) -> list[Any]:
    values: list[Any] = []
    before = read_nested(action.get("before", {}), field)
    if before is not None:
        values.append(before)
    for sample in action.get("poll", {}).get("samples", []):
        if isinstance(sample, dict):
            value = read_nested(sample, field)
            if value is not None:
                values.append(value)
    after = read_nested(action.get("after", {}), field)
    if after is not None:
        values.append(after)
    return compact_values(values)


def action_by_name(result: dict[str, Any], action_name: str) -> dict[str, Any] | None:
    for action in result.get("actions", []):
        if isinstance(action, dict) and action.get("action") == action_name:
            return action
    return None


def evaluate_sequences(case: CapabilityCase, result: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    observed = []
    mismatches = []
    for expected in case.expected_sequences:
        action = action_by_name(result, expected.action)
        sequence = observed_action_sequence(action or {}, expected.field)
        report = {
            "action": expected.action,
            "field": expected.field,
            "expected": list(expected.values),
            "observed": sequence,
        }
        observed.append(report)
        if sequence != list(expected.values):
            mismatches.append(report)
    return observed, mismatches


def evaluate_finals(case: CapabilityCase, result: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    observed = []
    mismatches = []
    for expected in case.expected_finals:
        action = action_by_name(result, expected.action)
        after = read_nested((action or {}).get("after", {}), expected.field)
        report = {
            "action": expected.action,
            "field": expected.field,
            "expected": expected.value,
            "observed": after,
        }
        observed.append(report)
        if after != expected.value:
            mismatches.append(report)
    return observed, mismatches


def delta_value(before: Any, after: Any, mode: str) -> int | None:
    if not isinstance(before, int) or not isinstance(after, int):
        return None
    if mode == "signed":
        return after - before
    if mode == "beta4096":
        return (after - before) % 4096
    raise CapabilityLadderError(f"unsupported delta expectation mode: {mode}")


def evaluate_deltas(case: CapabilityCase, result: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    observed = []
    mismatches = []
    for expected in case.expected_deltas:
        action = action_by_name(result, expected.action)
        before = read_nested((action or {}).get("before", {}), expected.field)
        after = read_nested((action or {}).get("after", {}), expected.field)
        delta = delta_value(before, after, expected.mode)
        report = {
            "action": expected.action,
            "field": expected.field,
            "mode": expected.mode,
            "expected_min_delta": expected.min_delta,
            "expected_max_delta": expected.max_delta,
            "before": before,
            "after": after,
            "observed_delta": delta,
        }
        observed.append(report)
        if delta is None or delta < expected.min_delta or delta > expected.max_delta:
            mismatches.append(report)
    return observed, mismatches


def movement_time_series(action: dict[str, Any]) -> dict[str, Any]:
    samples = [
        sample
        for sample in action.get("poll", {}).get("samples", [])
        if isinstance(sample, dict)
        and isinstance(sample.get("_t_ms"), int)
        and isinstance(sample.get("hero_x"), int)
        and isinstance(sample.get("hero_z"), int)
    ]
    if not samples:
        return {"sample_count": 0, "samples": [], "segments": []}

    start = samples[0]
    previous = start
    compact_samples = []
    segments = []
    for sample in samples:
        if sample["_t_ms"] < 0:
            continue
        row = {
            "t_ms": sample["_t_ms"],
            "hero_x": sample["hero_x"],
            "hero_z": sample["hero_z"],
            "dx_from_start": sample["hero_x"] - start["hero_x"],
            "dz_from_start": sample["hero_z"] - start["hero_z"],
        }
        animation_candidate = sample.get("hero_animation_candidate")
        if isinstance(animation_candidate, dict):
            row["hero_animation_candidate"] = {
                key: animation_candidate.get(key)
                for key in (
                    "hero_obj_gen_body",
                    "hero_obj_gen_anim",
                    "hero_obj_next_gen_anim",
                    "hero_obj_sprite_candidate",
                    "hero_obj_flag_anim_candidate",
                )
            }
        compact_samples.append(row)
        delta_t = sample["_t_ms"] - previous["_t_ms"]
        if delta_t > 0:
            segments.append(
                {
                    "t_ms": sample["_t_ms"],
                    "dt_ms": delta_t,
                    "dx": sample["hero_x"] - previous["hero_x"],
                    "dz": sample["hero_z"] - previous["hero_z"],
                }
            )
        previous = sample

    return {
        "sample_count": len(samples),
        "samples": compact_samples[:60],
        "segments": segments[:60],
        "final_dx": samples[-1]["hero_x"] - start["hero_x"],
        "final_dz": samples[-1]["hero_z"] - start["hero_z"],
    }


def evaluate_movement_time_series(case: CapabilityCase, result: dict[str, Any]) -> list[dict[str, Any]]:
    action_names = []
    for expected in case.expected_deltas:
        if expected.action in action_names:
            continue
        if expected.field not in {"hero_x", "hero_z", "hero_beta"}:
            continue
        action_names.append(expected.action)

    reports = []
    for action_name in action_names:
        action = action_by_name(result, action_name)
        reports.append(
            {
                "action": action_name,
                "movement_time_series": movement_time_series(action or {}),
            }
        )
    return reports


def extra_rows(action: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for sample in action.get("poll", {}).get("samples", []):
        extras = sample.get("extras") if isinstance(sample, dict) else None
        if not isinstance(extras, dict):
            continue
        active_extras = extras.get("active_extras", [])
        if not isinstance(active_extras, list):
            continue
        for row in active_extras:
            if isinstance(row, dict):
                rows.append(row)
    return rows


def extra_row_matches(row: dict[str, Any], expected: ExtraRowExpectation) -> bool:
    return (
        row.get("sprite") == expected.sprite
        and row.get("owner") == expected.owner
        and row.get("body") == expected.body
        and row.get("hit_force") == expected.hit_force
    )


def observed_active_extra_count_sequence(action: dict[str, Any]) -> list[int]:
    values = []
    for sample in action.get("poll", {}).get("samples", []):
        extras = sample.get("extras") if isinstance(sample, dict) else None
        if isinstance(extras, dict) and isinstance(extras.get("active_extra_count"), int):
            values.append(extras["active_extra_count"])
    return compact_values(values)


def evaluate_extras(case: CapabilityCase, result: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    observed = []
    mismatches = []
    for expected in case.expected_extras:
        action = action_by_name(result, expected.action)
        action = action or {}
        rows = extra_rows(action)
        active_sequence = observed_active_extra_count_sequence(action)
        required_reports = []
        missing_rows = []
        for row_expectation in expected.required_rows:
            count = sum(1 for row in rows if extra_row_matches(row, row_expectation))
            row_report = {
                "sprite": row_expectation.sprite,
                "owner": row_expectation.owner,
                "body": row_expectation.body,
                "hit_force": row_expectation.hit_force,
                "expected_min_count": row_expectation.min_count,
                "observed_count": count,
            }
            required_reports.append(row_report)
            if count < row_expectation.min_count:
                missing_rows.append(row_report)
        report = {
            "action": expected.action,
            "expected_active_count_sequence": list(expected.active_count_sequence),
            "observed_active_count_sequence": active_sequence,
            "required_rows": required_reports,
            "missing_rows": missing_rows,
        }
        observed.append(report)
        if (expected.active_count_sequence and active_sequence != list(expected.active_count_sequence)) or missing_rows:
            mismatches.append(report)
    return observed, mismatches


def evaluate_case(case: CapabilityCase, result: dict[str, Any]) -> dict[str, Any]:
    if result.get("verdict") not in RUNNER_SUCCESS_VERDICTS:
        return {
            "id": case.id,
            "verdict": "failed",
            "description": case.description,
            "reason": f"checkpoint verdict was {result.get('verdict')}",
            "run_dir": result.get("run_dir"),
        }
    action = result.get("actions", [{}])[0] if case.actions else {}
    changed = action.get("poll", {}).get("changed_fields", {}) if action else {}
    actions = [action for action in result.get("actions", []) if isinstance(action, dict)]
    missing = [
        signal
        for signal in case.required_signals
        if not any(action_has_signal(action, signal) for action in actions)
    ]
    observed_sequences, sequence_mismatches = evaluate_sequences(case, result)
    observed_finals, final_mismatches = evaluate_finals(case, result)
    observed_deltas, delta_mismatches = evaluate_deltas(case, result)
    observed_movement_time_series = evaluate_movement_time_series(case, result)
    observed_extras, extras_mismatches = evaluate_extras(case, result)
    return {
        "id": case.id,
        "verdict": "passed"
        if not missing and not sequence_mismatches and not final_mismatches and not delta_mismatches and not extras_mismatches
        else "blocked",
        "description": case.description,
        "checkpoint_id": result.get("checkpoint_id"),
        "run_dir": result.get("run_dir"),
        "actions": list(case.actions),
        "required_signals": list(case.required_signals),
        "changed_fields": sorted(changed.keys()),
        "missing_signals": missing,
        "observed_sequences": observed_sequences,
        "sequence_mismatches": sequence_mismatches,
        "observed_finals": observed_finals,
        "final_mismatches": final_mismatches,
        "observed_deltas": observed_deltas,
        "delta_mismatches": delta_mismatches,
        "observed_movement_time_series": observed_movement_time_series,
        "observed_extras": observed_extras,
        "extras_mismatches": extras_mismatches,
    }


def run_ladder(
    cases: tuple[CapabilityCase, ...],
    out_root: Path,
    *,
    save_root: Path = game_drive_runner.DEFAULT_SAVE_DIR,
    exe: Path = game_drive_runner.DEFAULT_GAME_EXE,
    archive: bool = False,
    archive_on_failure: bool = False,
    archive_root: Path = game_drive_runner.DEFAULT_ARCHIVE_ROOT,
    archive_event_id: str | None = None,
) -> dict[str, Any]:
    checkpoint_dir = out_root / "checkpoints"
    run_root = out_root / "runs"
    reports = []
    for case in cases:
        checkpoint_path = materialize_checkpoint(case, checkpoint_dir)
        try:
            result = game_drive_runner.run_checkpoint(
                checkpoint_path,
                out_root=run_root,
                save_root=save_root,
                exe=exe,
                archive=archive,
                archive_on_failure=archive_on_failure,
                archive_root=archive_root,
                archive_event_id=f"{archive_event_id}-{case.id}" if archive_event_id else None,
            )
            report = evaluate_case(case, result)
            if archive_on_failure and report["verdict"] != "passed" and isinstance(result.get("run_dir"), str):
                archive_seed = (
                    f"{archive_event_id}-{case.id}-{Path(result['run_dir']).name}"
                    if archive_event_id
                    else Path(result["run_dir"]).name
                )
                archive_id = game_drive_runner.safe_event_id(
                    archive_seed
                )
                result["evidence_archive"] = {
                    "archive_id": archive_id,
                    "manifest": game_drive_runner.repo_relative(archive_root / archive_id / "manifest.json"),
                    "reason": f"capability_failure:{report['verdict']}",
                }
                game_drive_runner.archive_game_drive_run(
                    result,
                    game_drive_runner.REPO_ROOT / result["run_dir"],
                    archive_root,
                    event_id=archive_id,
                    reason=f"capability_failure:{report['verdict']}",
                )
                game_drive_runner.write_json(game_drive_runner.REPO_ROOT / result["run_dir"] / "summary.json", result)
                report["evidence_archive"] = result["evidence_archive"]
            reports.append(report)
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
    parser.add_argument("--save-root", type=Path, default=game_drive_runner.DEFAULT_SAVE_DIR)
    parser.add_argument("--exe", type=Path, default=game_drive_runner.DEFAULT_GAME_EXE)
    parser.add_argument("--case", action="append", choices=[case.id for case in CAPABILITIES])
    parser.add_argument("--archive", action="store_true", help="archive compressed evidence for selected runs")
    parser.add_argument("--archive-on-failure", action="store_true", help="archive compressed evidence only for failed selected runs")
    parser.add_argument("--archive-root", type=Path, default=game_drive_runner.DEFAULT_ARCHIVE_ROOT)
    parser.add_argument("--archive-event-id", help="stable event/task/promotion id prefix for archived evidence")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    try:
        payload = run_ladder(
            selected_cases(args.case),
            args.out_root,
            save_root=args.save_root,
            exe=args.exe,
            archive=args.archive,
            archive_on_failure=args.archive_on_failure,
            archive_root=args.archive_root,
            archive_event_id=args.archive_event_id,
        )
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
