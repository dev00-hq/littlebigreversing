from __future__ import annotations

import json
from pathlib import Path
import unittest


FIXTURE = Path(__file__).resolve().parent / "fixtures" / "phase5_187_startcube_counterfactual.json"


class Phase5187StartCubeCounterfactualTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.proof = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_counterfactual_changed_start_x_cube_only(self) -> None:
        override = self.proof["start_cube_override"]

        self.assertEqual({"x": 28648, "y": 2572, "z": 23036}, override["before"]["scene_start"])
        self.assertEqual(override["before"]["scene_start"], override["after"]["scene_start"])
        self.assertEqual({"x": 55, "y": 11, "z": 44}, override["before"]["start_cube"])
        self.assertEqual({"x": 54, "y": 11, "z": 44}, override["after"]["start_cube"])

    def test_landing_is_invalid_as_transition_counterfactual(self) -> None:
        self.assertFalse(self.proof["sync_candidate_source"])
        self.assertEqual("invalid_source_probe_respawned_or_safety_reset", self.proof["final_verdict"])
        self.assertTrue(self.proof["conclusion"]["counterfactual_invalid_for_transition_causality"])
        self.assertEqual(
            {"active_cube": 185, "new_cube": -1, "x": 28416, "y": 2304, "z": 21760, "beta": 2102},
            self.proof["final_pose"],
        )

    def test_contract_rejects_start_cube_run_as_causal_model(self) -> None:
        conclusion = self.proof["conclusion"]

        self.assertFalse(conclusion["start_cube_alone_causal"])
        self.assertTrue(conclusion["decoded_position_still_rejected"])
        self.assertIn("Do not use this run as transition-branch evidence", conclusion["next_action"])


if __name__ == "__main__":
    unittest.main()
