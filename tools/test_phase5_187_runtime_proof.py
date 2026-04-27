from __future__ import annotations

import json
from pathlib import Path
import unittest


FIXTURE = Path(__file__).resolve().parent / "fixtures" / "phase5_187_runtime_proof.json"


class Phase5187RuntimeProofTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.proof = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_direct_save_load_contract_targets_scene187(self) -> None:
        save = self.proof["launch_save"]

        self.assertEqual("phase5-187-runtime-proof-v1", self.proof["schema_version"])
        self.assertEqual(["LBA2.EXE", "SAVE\\inside dark monk1.LBA"], save["argv"])
        self.assertEqual("inside dark monk1", save["save_name"])
        self.assertEqual(0xA4, save["num_version"])
        self.assertEqual(185, save["num_cube"])
        self.assertEqual(187, save["raw_scene_entry_index"])
        self.assertEqual(
            {"active_cube": 185, "x": 28647, "y": 2304, "z": 21741, "beta": 2102},
            save["initial_pose"],
        )

    def test_zone_source_and_decoded_destinations_are_separate_from_live_landing(self) -> None:
        zone = self.proof["zone"]
        probe = self.proof["probe"]

        self.assertEqual({"x": 1536, "y": 256, "z": 4608}, probe["source"])
        self.assertEqual({"cube": 185, "x": 13824, "y": 5120, "z": 14848}, zone["decoded_destination"])
        self.assertEqual({"cube": 185, "x": 14336, "y": 5376, "z": 15360}, zone["source_relative_destination"])
        self.assertNotEqual(zone["decoded_destination"], probe["final_pose"])
        self.assertNotEqual(zone["source_relative_destination"], probe["final_pose"])

    def test_no_scene_start_sync_run_keeps_saved_context_and_lands_at_cube_start_area(self) -> None:
        save = self.proof["launch_save"]
        probe = self.proof["probe"]

        self.assertFalse(probe["sync_scene_start"])
        self.assertEqual(save["initial_context"], probe["final_context"])
        self.assertEqual("loaded_cube185_live_zone1_destination", probe["final_verdict"])
        self.assertEqual(
            {"active_cube": 185, "new_cube": -1, "x": 28416, "y": 2304, "z": 21760, "beta": 2102},
            probe["final_pose"],
        )

    def test_port_contract_keeps_decoded_newpos_rejected(self) -> None:
        contract = self.proof["port_contract"]

        self.assertEqual("keep_rejected", contract["decoded_position_status"])
        self.assertEqual("unsupported_destination_height_mismatch", contract["decoded_rejection_reason"])
        self.assertEqual("saved_cube_start_context", contract["live_landing_model"])


if __name__ == "__main__":
    unittest.main()
