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


if __name__ == "__main__":
    unittest.main()
