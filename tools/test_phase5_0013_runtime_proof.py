from __future__ import annotations

import json
from pathlib import Path
import unittest


FIXTURE = Path(__file__).resolve().parent / "fixtures" / "phase5_0013_runtime_proof.json"


class Phase50013RuntimeProofTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.proof = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_generated_save_load_contract_is_canonical(self) -> None:
        save = self.proof["generated_save"]

        self.assertEqual("phase5-0013-runtime-proof-v1", self.proof["schema_version"])
        self.assertEqual("SAVE\\scene2-bg1-key-midpoint-facing-key.LBA", save["game_pathname"])
        self.assertEqual("scene2-bg1-key-midpoint-facing-key", save["player_name"])
        self.assertEqual(0xA4, save["num_version"])
        self.assertEqual(
            {"active_cube": 0, "x": 3478, "y": 2048, "z": 4772, "beta": 3584},
            save["start_pose"],
        )

    def test_key_spawn_pickup_and_counter_contract(self) -> None:
        key = self.proof["key"]

        self.assertEqual(6, key["spawn_extra"]["sprite"])
        self.assertEqual(1, key["spawn_extra"]["divers"])
        self.assertEqual({"x": 3072, "y": 3072, "z": 5120}, key["spawn_extra"]["origin"])
        self.assertEqual({"x": 3768, "y": 2144, "z": 4366}, key["landing"])
        self.assertEqual(0, key["pickup"]["nb_little_keys_before"])
        self.assertEqual(1, key["pickup"]["nb_little_keys_after"])
        self.assertEqual(0, key["pickup"]["key_extras_after"])
        self.assertEqual(1428, self.proof["controls"]["pickup_key"]["heading_beta"])

    def test_door_consumes_key_and_enters_cellar(self) -> None:
        door = self.proof["door"]

        self.assertEqual({"scene": 2, "background": 1, "active_cube": 0}, door["source"])
        self.assertEqual({"scene": 2, "background": 0, "active_cube": 1}, door["target"])
        self.assertEqual(2583, self.proof["controls"]["walk_through_door"]["heading_beta"])
        self.assertEqual(1, door["key_consumed"]["nb_little_keys_before"])
        self.assertEqual(0, door["key_consumed"]["nb_little_keys_after"])
        self.assertEqual(0, door["cellar_transition"]["active_cube_before"])
        self.assertEqual(1, door["cellar_transition"]["active_cube_after"])
        self.assertEqual({"x": 9723, "y": 1277, "z": 762}, door["cellar_transition"]["new_pos"])
        self.assertEqual(1, door["final_cellar"]["active_cube"])

    def test_cellar_return_is_free_and_commits_house_doorway(self) -> None:
        ret = self.proof["return"]

        self.assertEqual({"scene": 2, "background": 0, "active_cube": 1}, ret["source"])
        self.assertEqual({"scene": 2, "background": 1, "active_cube": 0}, ret["target"])
        self.assertEqual("DOWN", self.proof["controls"]["return_to_house"]["key"])
        self.assertEqual(1, ret["transition"]["active_cube_before"])
        self.assertEqual(0, ret["transition"]["active_cube_after"])
        self.assertEqual({"x": 2562, "y": 2049, "z": 3686}, ret["transition"]["new_pos"])
        self.assertEqual(
            {"x": 2562, "y": 2048, "z": 3686, "beta": 2583},
            ret["final_house"]["hero"],
        )

    def test_review_screenshot_set_names_key_moments(self) -> None:
        self.assertEqual(
            [
                "01_loaded_midpoint_facing_key.png",
                "04_key_picked_up.png",
                "05_facing_door_after_pickup.png",
                "06_door_unlocked_key_consumed.png",
                "08_final_cellar.png",
                "10_final_house_return.png",
            ],
            self.proof["screenshots"],
        )


if __name__ == "__main__":
    unittest.main()
