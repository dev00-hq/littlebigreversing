from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


LIFE_TRACE_PATH = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_PATH))
MODULE_PATH = LIFE_TRACE_PATH / "phase5_33_cellar_probe.py"
SPEC = importlib.util.spec_from_file_location("phase5_33_cellar_probe", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
phase5_33_cellar_probe = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = phase5_33_cellar_probe
SPEC.loader.exec_module(phase5_33_cellar_probe)


class Phase533CellarProbeTests(unittest.TestCase):
    def test_probe_uses_0013_weapon_as_cellar_source_only(self) -> None:
        self.assertEqual(
            {
                "version_byte": 0xA4,
                "num_cube": 1,
                "raw_scene_entry_index": 3,
            },
            phase5_33_cellar_probe.EXPECTED_SAVE,
        )

    def test_zone1_center_stays_inside_cellar_source_destination_handoff(self) -> None:
        self.assertEqual(
            {
                "x": 4096,
                "y": 3968,
                "z": 8960,
                "beta": 0,
            },
            phase5_33_cellar_probe.zone_center(phase5_33_cellar_probe.ZONE1),
        )
        self.assertEqual(19, phase5_33_cellar_probe.ZONE1["destination_cube"])
        self.assertEqual(21, phase5_33_cellar_probe.ZONE1["port_destination_scene_entry_index"])
        self.assertEqual(19, phase5_33_cellar_probe.ZONE1["port_destination_background_entry_index"])

    def test_zone1_edge_path_crosses_from_outside_to_inside(self) -> None:
        self.assertEqual(
            {
                "x": 3520,
                "y": 3968,
                "z": 8960,
                "beta": 1024,
            },
            phase5_33_cellar_probe.zone_edge_start(phase5_33_cellar_probe.ZONE1),
        )
        path = phase5_33_cellar_probe.zone_edge_path(phase5_33_cellar_probe.ZONE1)

        self.assertEqual(4, len(path))
        self.assertLess(path[0]["x"], phase5_33_cellar_probe.ZONE1["bounds"][0])
        self.assertLess(path[1]["x"], phase5_33_cellar_probe.ZONE1["bounds"][0])
        self.assertGreater(path[2]["x"], phase5_33_cellar_probe.ZONE1["bounds"][0])
        self.assertEqual(4096, path[-1]["x"])

    def test_zone8_center_targets_second_cellar_source_destination_handoff(self) -> None:
        self.assertEqual(
            {
                "x": 27648,
                "y": 2304,
                "z": 7936,
                "beta": 0,
            },
            phase5_33_cellar_probe.zone_center(phase5_33_cellar_probe.ZONE8),
        )
        self.assertEqual(20, phase5_33_cellar_probe.ZONE8["destination_cube"])
        self.assertEqual(22, phase5_33_cellar_probe.ZONE8["port_destination_scene_entry_index"])
        self.assertEqual(20, phase5_33_cellar_probe.ZONE8["port_destination_background_entry_index"])

    def test_zone8_verdict_requires_its_own_runtime_destination(self) -> None:
        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            [{"snapshot": {"new_cube": 20, "active_cube": 1, "clovers": 5}}],
            5,
            zone=phase5_33_cellar_probe.ZONE8,
        )
        self.assertEqual("phase5_33_zone8_new_cube_observed", verdict)
        self.assertIn(verdict, phase5_33_cellar_probe.ACCEPTED_VERDICTS)

        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            [{"snapshot": {"new_cube": 19, "active_cube": 1, "clovers": 5}}],
            5,
            zone=phase5_33_cellar_probe.ZONE8,
        )
        self.assertEqual("phase5_33_zone8_transition_not_observed", verdict)
        self.assertNotIn(verdict, phase5_33_cellar_probe.ACCEPTED_VERDICTS)

    def test_verdict_requires_runtime_destination_or_reports_life_loss(self) -> None:
        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            [{"snapshot": {"new_cube": 19, "active_cube": 1, "clovers": 5}}],
            5,
        )
        self.assertEqual("phase5_33_zone1_new_cube_observed", verdict)
        self.assertIn(verdict, phase5_33_cellar_probe.ACCEPTED_VERDICTS)

        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            [{"snapshot": {"new_cube": -1, "active_cube": 1, "clovers": 4}}],
            5,
        )
        self.assertEqual("phase5_33_zone1_life_loss_detected", verdict)
        self.assertNotIn(verdict, phase5_33_cellar_probe.ACCEPTED_VERDICTS)

        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            [{"snapshot": {"new_cube": -1, "active_cube": 1, "clovers": 5}}],
            5,
        )
        self.assertEqual("phase5_33_zone1_transition_not_observed", verdict)
        self.assertNotIn(verdict, phase5_33_cellar_probe.ACCEPTED_VERDICTS)

    def test_attempt_scoped_verdicts_keep_direct_and_edge_failures_distinct(self) -> None:
        observations = [
            {
                "attempt": phase5_33_cellar_probe.ATTEMPT_DIRECT_CENTER,
                "snapshot": {"new_cube": -1, "active_cube": 1, "clovers": 5},
            },
            {
                "attempt": phase5_33_cellar_probe.ATTEMPT_EDGE_CROSSING,
                "snapshot": {"new_cube": -1, "active_cube": 1, "clovers": 5},
            },
        ]

        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            observations,
            5,
            attempt=phase5_33_cellar_probe.ATTEMPT_DIRECT_CENTER,
        )
        self.assertEqual("phase5_33_zone1_direct_center_no_transition", verdict)

        verdict, _ = phase5_33_cellar_probe.classify_verdict(
            observations,
            5,
            attempt=phase5_33_cellar_probe.ATTEMPT_EDGE_CROSSING,
        )
        self.assertEqual("phase5_33_zone1_edge_crossing_no_transition", verdict)

    def test_loaded_gate_rejects_zero_menu_snapshot(self) -> None:
        self.assertFalse(
            phase5_33_cellar_probe.runtime_looks_loaded(
                {"hero_count": 0, "active_cube": 0, "hero_x": 0, "hero_y": 0, "hero_z": 0}
            )
        )
        self.assertTrue(
            phase5_33_cellar_probe.runtime_looks_loaded(
                {"hero_count": 9, "active_cube": 1, "hero_x": 5499, "hero_y": 1024, "hero_z": 1786}
            )
        )


if __name__ == "__main__":
    unittest.main()
