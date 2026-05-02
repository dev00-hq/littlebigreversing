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


if __name__ == "__main__":
    unittest.main()
