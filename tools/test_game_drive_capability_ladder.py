from __future__ import annotations

import unittest

from tools import game_drive_capability_ladder as ladder


class GameDriveCapabilityLadderTests(unittest.TestCase):
    def test_required_position_signal_allows_x_or_z(self) -> None:
        self.assertTrue(ladder.has_signal({"hero_z": [1, 2]}, "hero_x|hero_z"))
        self.assertFalse(ladder.has_signal({"hero_beta": [1, 2]}, "hero_x|hero_z"))

    def test_magic_ball_signal_requires_active_extra(self) -> None:
        self.assertTrue(ladder.has_signal({"extras": [{"active_extra_count": 1}]}, "extras"))
        self.assertFalse(ladder.has_signal({"extras": [{"active_extra_count": 0}]}, "extras"))

    def test_dialog_signal_requires_nonzero_current_dial(self) -> None:
        self.assertTrue(ladder.has_signal({"dialog": [{"current_dial": 504}]}, "dialog"))
        self.assertFalse(ladder.has_signal({"dialog": [{"current_dial": 0}]}, "dialog"))

    def test_action_signal_can_use_stable_dialog_sample(self) -> None:
        action = {"poll": {"changed_fields": {}, "samples": [{"dialog": {"current_dial": 504}}]}}

        self.assertTrue(ladder.action_has_signal(action, "dialog"))

    def test_observed_action_sequence_compacts_before_samples_and_after(self) -> None:
        action = {
            "before": {"comportement": 1},
            "poll": {
                "samples": [
                    {"comportement": 1},
                    {"comportement": 2},
                    {"comportement": 2},
                ],
            },
            "after": {"comportement": 2},
        }

        self.assertEqual(ladder.observed_action_sequence(action, "comportement"), [1, 2])

    def test_observed_action_sequence_reads_nested_samples(self) -> None:
        action = {
            "poll": {
                "samples": [
                    {"dialog": {"current_dial": 504}},
                    {"dialog": {"current_dial": 504}},
                ],
            },
        }

        self.assertEqual(ladder.observed_action_sequence(action, "dialog.current_dial"), [504])

    def test_expected_sequence_blocks_wrong_behavior_transition(self) -> None:
        case = ladder.CapabilityCase(
            id="behavior_test",
            base_checkpoint="checkpoint.json",
            actions=("ctrl_right_behavior_cycle",),
            required_signals=("comportement",),
            description="test",
            expected_sequences=(
                ladder.ActionSequenceExpectation(
                    action="ctrl_right_behavior_cycle",
                    field="comportement",
                    values=(1, 2),
                ),
            ),
        )
        result = {
            "verdict": "passed",
            "actions": [
                {
                    "action": "ctrl_right_behavior_cycle",
                    "before": {"comportement": 1},
                    "poll": {
                        "changed_fields": {"comportement": [1, 3]},
                        "samples": [{"comportement": 3}],
                    },
                    "after": {"comportement": 3},
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "blocked")
        self.assertEqual(report["sequence_mismatches"][0]["observed"], [1, 3])

    def test_final_expectation_allows_behavior_key_from_any_starting_mode(self) -> None:
        case = ladder.CapabilityCase(
            id="behavior_direct_test",
            base_checkpoint="checkpoint.json",
            actions=("press_f5_0_08_sec",),
            required_signals=(),
            description="test",
            expected_finals=(
                ladder.ActionFinalExpectation(
                    action="press_f5_0_08_sec",
                    field="comportement",
                    value=0,
                ),
            ),
        )
        result = {
            "verdict": "checkpoint_passed_actions_recorded",
            "actions": [
                {
                    "action": "press_f5_0_08_sec",
                    "before": {"comportement": 0},
                    "poll": {"changed_fields": {}, "samples": [{"comportement": 0}]},
                    "after": {"comportement": 0},
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")
        self.assertEqual(report["observed_finals"][0]["observed"], 0)

    def test_final_expectation_blocks_wrong_behavior_key_result(self) -> None:
        case = ladder.CapabilityCase(
            id="behavior_direct_test",
            base_checkpoint="checkpoint.json",
            actions=("press_f8_0_08_sec",),
            required_signals=(),
            description="test",
            expected_finals=(
                ladder.ActionFinalExpectation(
                    action="press_f8_0_08_sec",
                    field="comportement",
                    value=3,
                ),
            ),
        )
        result = {
            "verdict": "checkpoint_passed_actions_recorded",
            "actions": [
                {
                    "action": "press_f8_0_08_sec",
                    "before": {"comportement": 1},
                    "poll": {"changed_fields": {"comportement": [1, 2]}, "samples": [{"comportement": 2}]},
                    "after": {"comportement": 2},
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "blocked")
        self.assertEqual(report["final_mismatches"][0]["observed"], 2)

    def test_materialized_capability_can_override_pose_coordinates(self) -> None:
        case = ladder.CapabilityCase(
            id="pose_override_test",
            base_checkpoint="pose_ready_magic_ball_middle_switch.json",
            actions=("press_f5_0_08_sec",),
            required_signals=(),
            description="test",
            pose_coordinates={"x": 1, "y": 2, "z": 3, "beta": 4},
        )

        path = ladder.materialize_checkpoint(case, ladder.DEFAULT_OUT_ROOT / "test_checkpoints")
        checkpoint = ladder.load_json(path)

        self.assertEqual(
            checkpoint["setup"]["pose"]["coordinates"],
            {"x": 1, "y": 2, "z": 3, "beta": 4},
        )

    def test_delta_expectation_passes_signed_range(self) -> None:
        case = ladder.CapabilityCase(
            id="translation_test",
            base_checkpoint="checkpoint.json",
            actions=("hold_up_0_50_sec_release",),
            required_signals=("hero_x",),
            description="test",
            expected_deltas=(
                ladder.ActionDeltaExpectation(
                    action="hold_up_0_50_sec_release",
                    field="hero_x",
                    min_delta=-1200,
                    max_delta=-300,
                ),
            ),
        )
        result = {
            "verdict": "passed",
            "actions": [
                {
                    "action": "hold_up_0_50_sec_release",
                    "before": {"hero_x": 4866},
                    "poll": {"changed_fields": {"hero_x": [4866, 4174]}, "samples": []},
                    "after": {"hero_x": 4174},
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")
        self.assertEqual(report["observed_deltas"][0]["observed_delta"], -692)

    def test_runner_action_recorded_verdict_is_semantically_evaluated_by_ladder(self) -> None:
        case = ladder.CapabilityCase(
            id="translation_test",
            base_checkpoint="checkpoint.json",
            actions=("hold_up_0_50_sec_release",),
            required_signals=("hero_x",),
            description="test",
            expected_deltas=(
                ladder.ActionDeltaExpectation(
                    action="hold_up_0_50_sec_release",
                    field="hero_x",
                    min_delta=-1200,
                    max_delta=-300,
                ),
            ),
        )
        result = {
            "verdict": "checkpoint_passed_actions_recorded",
            "actions": [
                {
                    "action": "hold_up_0_50_sec_release",
                    "before": {"hero_x": 4866},
                    "poll": {"changed_fields": {"hero_x": [4866, 4174]}, "samples": []},
                    "after": {"hero_x": 4174},
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")

    def test_required_signal_can_come_from_second_action(self) -> None:
        case = ladder.CapabilityCase(
            id="magic_ball_test",
            base_checkpoint="checkpoint.json",
            actions=("press_1_0_08_sec", "hold_period_0_75_sec_release"),
            required_signals=("extras",),
            description="test",
            expected_extras=(
                ladder.ActionExtrasExpectation(
                    action="hold_period_0_75_sec_release",
                    active_count_sequence=(),
                    required_rows=(ladder.ExtraRowExpectation(sprite=10, owner=0, body=-1, hit_force=30),),
                ),
            ),
        )
        result = {
            "verdict": "checkpoint_passed_actions_recorded",
            "actions": [
                {
                    "action": "press_1_0_08_sec",
                    "poll": {"changed_fields": {}, "samples": []},
                },
                {
                    "action": "hold_period_0_75_sec_release",
                    "poll": {
                        "changed_fields": {"extras": [{"active_extra_count": 1}]},
                        "samples": [
                            {
                                "extras": {
                                    "active_extra_count": 1,
                                    "active_extras": [
                                        {"sprite": 10, "owner": 0, "body": -1, "hit_force": 30},
                                    ],
                                },
                            },
                        ],
                    },
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")

    def test_delta_expectation_uses_beta4096_wrap(self) -> None:
        self.assertEqual(ladder.delta_value(3900, 100, "beta4096"), 296)

    def test_movement_time_series_reports_sample_and_segment_deltas(self) -> None:
        action = {
            "poll": {
                "samples": [
                    {"_t_ms": 0, "hero_x": 100, "hero_z": 50},
                    {"_t_ms": 50, "hero_x": 95, "hero_z": 49},
                    {"_t_ms": 100, "hero_x": 80, "hero_z": 45},
                ],
            },
        }

        report = ladder.movement_time_series(action)

        self.assertEqual(report["sample_count"], 3)
        self.assertEqual(report["samples"][2]["dx_from_start"], -20)
        self.assertEqual(report["segments"][1]["dx"], -15)

    def test_extras_expectation_requires_lifecycle_and_identity_rows(self) -> None:
        case = ladder.CapabilityCase(
            id="magic_ball_test",
            base_checkpoint="checkpoint.json",
            actions=("hold_period_0_75_sec_release",),
            required_signals=("extras",),
            description="test",
            expected_extras=(
                ladder.ActionExtrasExpectation(
                    action="hold_period_0_75_sec_release",
                    active_count_sequence=(0, 1, 0),
                    required_rows=(
                        ladder.ExtraRowExpectation(sprite=10, owner=0, body=-1, hit_force=30, min_count=2),
                        ladder.ExtraRowExpectation(sprite=14, owner=255, body=-1, hit_force=0),
                    ),
                ),
            ),
        )
        result = {
            "verdict": "passed",
            "actions": [
                {
                    "action": "hold_period_0_75_sec_release",
                    "poll": {
                        "changed_fields": {"extras": [{"active_extra_count": 1}]},
                        "samples": [
                            {"extras": {"active_extra_count": 0, "active_extras": []}},
                            {
                                "extras": {
                                    "active_extra_count": 1,
                                    "active_extras": [
                                        {"sprite": 10, "owner": 0, "body": -1, "hit_force": 30},
                                    ],
                                },
                            },
                            {
                                "extras": {
                                    "active_extra_count": 1,
                                    "active_extras": [
                                        {"sprite": 10, "owner": 0, "body": -1, "hit_force": 30},
                                    ],
                                },
                            },
                            {
                                "extras": {
                                    "active_extra_count": 1,
                                    "active_extras": [
                                        {"sprite": 14, "owner": 255, "body": -1, "hit_force": 0},
                                    ],
                                },
                            },
                            {"extras": {"active_extra_count": 0, "active_extras": []}},
                        ],
                    },
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")
        self.assertEqual(report["observed_extras"][0]["observed_active_count_sequence"], [0, 1, 0])

    def test_extras_expectation_blocks_missing_magic_ball_return_row(self) -> None:
        case = ladder.CapabilityCase(
            id="magic_ball_test",
            base_checkpoint="checkpoint.json",
            actions=("hold_period_0_75_sec_release",),
            required_signals=("extras",),
            description="test",
            expected_extras=(
                ladder.ActionExtrasExpectation(
                    action="hold_period_0_75_sec_release",
                    active_count_sequence=(0, 1, 0),
                    required_rows=(ladder.ExtraRowExpectation(sprite=14, owner=255, body=-1, hit_force=0),),
                ),
            ),
        )
        result = {
            "verdict": "passed",
            "actions": [
                {
                    "action": "hold_period_0_75_sec_release",
                    "poll": {
                        "changed_fields": {"extras": [{"active_extra_count": 1}]},
                        "samples": [
                            {"extras": {"active_extra_count": 0, "active_extras": []}},
                            {
                                "extras": {
                                    "active_extra_count": 1,
                                    "active_extras": [
                                        {"sprite": 10, "owner": 0, "body": -1, "hit_force": 30},
                                    ],
                                },
                            },
                            {"extras": {"active_extra_count": 0, "active_extras": []}},
                        ],
                    },
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "blocked")
        self.assertEqual(report["extras_mismatches"][0]["missing_rows"][0]["sprite"], 14)

    def test_extras_expectation_can_ignore_scene_ambient_extra_count_sequence(self) -> None:
        case = ladder.CapabilityCase(
            id="magic_ball_test",
            base_checkpoint="checkpoint.json",
            actions=("hold_period_0_75_sec_release",),
            required_signals=("extras",),
            description="test",
            expected_extras=(
                ladder.ActionExtrasExpectation(
                    action="hold_period_0_75_sec_release",
                    active_count_sequence=(),
                    required_rows=(
                        ladder.ExtraRowExpectation(sprite=10, owner=0, body=-1, hit_force=30),
                        ladder.ExtraRowExpectation(sprite=14, owner=255, body=-1, hit_force=0),
                    ),
                ),
            ),
        )
        result = {
            "verdict": "passed",
            "actions": [
                {
                    "action": "hold_period_0_75_sec_release",
                    "poll": {
                        "changed_fields": {"extras": [{"active_extra_count": 2}]},
                        "samples": [
                            {
                                "extras": {
                                    "active_extra_count": 2,
                                    "active_extras": [
                                        {"sprite": 4, "owner": 0, "body": -1, "hit_force": 0},
                                        {"sprite": 10, "owner": 0, "body": -1, "hit_force": 30},
                                    ],
                                },
                            },
                            {
                                "extras": {
                                    "active_extra_count": 2,
                                    "active_extras": [
                                        {"sprite": 5, "owner": 0, "body": -1, "hit_force": 0},
                                        {"sprite": 14, "owner": 255, "body": -1, "hit_force": 0},
                                    ],
                                },
                            },
                        ],
                    },
                },
            ],
        }

        report = ladder.evaluate_case(case, result)

        self.assertEqual(report["verdict"], "passed")


if __name__ == "__main__":
    unittest.main()
