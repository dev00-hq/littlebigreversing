from __future__ import annotations

import unittest

from tools import game_drive_runner


class GameDriveRunnerTests(unittest.TestCase):
    def test_known_action_specs_parse_to_key_and_hold(self) -> None:
        self.assertEqual((0xBE, 0.75), game_drive_runner.action_to_key_hold("hold_period_0_75_sec_release"))
        self.assertEqual((0x57, 0.18), game_drive_runner.action_to_key_hold("press_w_0_18_sec"))

    def test_unknown_action_fails_fast(self) -> None:
        with self.assertRaisesRegex(game_drive_runner.GameDriveRunnerError, "unsupported action"):
            game_drive_runner.action_to_key_hold("walk_somewhere")

    def test_visual_prompt_includes_scene_and_target(self) -> None:
        checkpoint = {
            "id": "sample",
            "save": "sample.LBA",
            "visual_expect": {
                "source": "save_embedded_preview",
                "scene_description": "A room.",
                "target_description": "A lever.",
                "expected": {
                    "twinsen_visible": True,
                    "target_visible": True,
                    "ui_state": "gameplay",
                    "unsafe_pose_signs": False,
                },
                "summary_must_mention": ["Twinsen", "lever", "gameplay"],
            },
        }

        prompt = game_drive_runner.build_visual_prompt(checkpoint)

        self.assertIn("A room.", prompt)
        self.assertIn("A lever.", prompt)
        self.assertIn("summary_must_mention", prompt)


if __name__ == "__main__":
    unittest.main()
