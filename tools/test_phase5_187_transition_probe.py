from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parent / "life_trace" / "phase5_187_transition_probe.py"
LIFE_TRACE_PATH = MODULE_PATH.parent
if str(LIFE_TRACE_PATH) not in sys.path:
    sys.path.insert(0, str(LIFE_TRACE_PATH))
SPEC = importlib.util.spec_from_file_location("phase5_187_transition_probe", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
probe = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = probe
SPEC.loader.exec_module(probe)


class Phase5187TransitionProbeTests(unittest.TestCase):
    def row(self, *, active_cube: int, new_cube: int, new_y: int, hero_y: int) -> dict[str, object]:
        return {
            "transition_globals": {
                "active_cube": active_cube,
                "new_cube": new_cube,
                "new_pos_x": probe.EXPECTED_DESTINATION["x"],
                "new_pos_y": new_y,
                "new_pos_z": probe.EXPECTED_DESTINATION["z"],
            },
            "hero_object": {
                "x": probe.EXPECTED_DESTINATION["x"],
                "y": hero_y,
                "z": probe.EXPECTED_DESTINATION["z"],
            },
        }

    def test_target_zone_constants_match_guarded_187187_transition(self) -> None:
        self.assertEqual(1, probe.TARGET_ZONE.index)
        self.assertEqual(185, probe.TARGET_ZONE.num)
        self.assertEqual((1024, 0, 4096, 2048, 512, 5120), probe.TARGET_ZONE.bounds)
        self.assertEqual({"cube": 185, "x": 13824, "y": 5120, "z": 14848}, probe.EXPECTED_DESTINATION)
        self.assertEqual({"cube": 185, "x": 28416, "y": 2304, "z": 21760}, probe.LIVE_ZONE1_DESTINATION)
        self.assertEqual({"x": 1536, "y": 256, "z": 4608}, probe.RUNTIME_SOURCE_PROBE)

    def test_classic_context_reads_start_position_fields(self) -> None:
        values = {
            address: index
            for index, (address, _size) in enumerate(probe.CLASSIC_CONTEXT_FIELDS.values(), start=1)
        }

        class Reader:
            def read_int(self, address: int, size: int) -> int:
                assert size == 4
                return values[address]

        context = probe.read_classic_context(Reader())

        self.assertEqual(
            {
                "scene_start_x": 1,
                "scene_start_y": 2,
                "scene_start_z": 3,
                "start_x_cube": 4,
                "start_y_cube": 5,
                "start_z_cube": 6,
            },
            context,
        )

    def test_parse_start_cube_override(self) -> None:
        self.assertEqual(
            {"start_x_cube": 54, "start_y_cube": 11, "start_z_cube": 44},
            probe.parse_start_cube_override("54,11,44"),
        )
        self.assertIsNone(probe.parse_start_cube_override(None))

    def test_classic_zone_relative_destination_uses_probe_offset(self) -> None:
        destination = probe.classic_zone_relative_destination(probe.RUNTIME_SOURCE_PROBE)

        self.assertEqual({"cube": 185, "x": 14336, "y": 5376, "z": 15360}, destination)

    def write_save_stub(self, path: Path, *, version: int, num_cube: int, name: str) -> None:
        path.write_bytes(bytes([version]) + int(num_cube).to_bytes(4, "little", signed=True) + name.encode("ascii") + b"\x00payload")

    def test_default_save_targets_guarded_187_scene(self) -> None:
        self.assertEqual("inside dark monk1.LBA", probe.DEFAULT_SAVE.name)

    def test_save_header_validation_accepts_cube185_scene187(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "inside dark monk1.LBA"
            self.write_save_stub(path, version=0xA4, num_cube=185, name="inside dark monk1")

            header = probe.validate_runtime_source_save(path)

        self.assertEqual(0xA4, header["version_byte"])
        self.assertEqual(185, header["num_cube"])
        self.assertEqual(187, header["raw_scene_entry_index"])

    def test_save_header_validation_rejects_surface_statue_save(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "on dark monk statue.LBA"
            self.write_save_stub(path, version=0xA4, num_cube=95, name="on dark monk statue")

            with self.assertRaisesRegex(ValueError, "cube 95 / raw scene 97"):
                probe.validate_runtime_source_save(path)

    def test_classifies_staged_expected_destination_before_cube_load(self) -> None:
        verdict = probe.classify_observation(
            self.row(active_cube=184, new_cube=185, new_y=probe.EXPECTED_DESTINATION["y"], hero_y=256)
        )

        self.assertEqual("transition_globals_staged_expected_destination", verdict)

    def test_classifies_destination_height_outcomes_after_cube_load(self) -> None:
        live_zone1 = probe.classify_observation(
            self.row(active_cube=185, new_cube=-1, new_y=0, hero_y=2304)
            | {"hero_object": {"x": 28416, "y": 2304, "z": 21760}}
        )
        decoded = probe.classify_observation(
            self.row(active_cube=185, new_cube=185, new_y=5120, hero_y=5120)
        )
        raw_cell = probe.classify_observation(
            self.row(active_cube=185, new_cube=185, new_y=5120, hero_y=2048)
        )
        standable = probe.classify_observation(
            self.row(active_cube=185, new_cube=185, new_y=5120, hero_y=6400)
        )

        self.assertEqual(probe.INVALID_SOURCE_PROBE_VERDICT, live_zone1)
        self.assertEqual("loaded_cube185_kept_decoded_y", decoded)
        self.assertEqual("loaded_cube185_snapped_to_raw_cell_top", raw_cell)
        self.assertEqual("loaded_cube185_snapped_to_nearest_standable", standable)


if __name__ == "__main__":
    unittest.main()




