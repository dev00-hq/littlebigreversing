from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


MODULE_PATH = Path(__file__).resolve().parent / "life_trace" / "secret_room_door_watch.py"
SPEC = importlib.util.spec_from_file_location("secret_room_door_watch", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
secret_room_door_watch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = secret_room_door_watch
SPEC.loader.exec_module(secret_room_door_watch)


class FakeReader:
    def __init__(self, values: dict[str, int]) -> None:
        self.by_address = {
            address: values[name]
            for name, address in secret_room_door_watch.WATCH_FIELDS.items()
        }

    def read_i32(self, address: int) -> int:
        return self.by_address[address]


class SecretRoomDoorWatchTests(unittest.TestCase):
    def base_values(self) -> dict[str, int]:
        return {
            "scene_kind": 0,
            "transition_mode": 0,
            "transition_variant": 0,
            "active_cube": 1,
            "new_cube": -1,
            "new_pos_x": 2562,
            "new_pos_y": 2049,
            "new_pos_z": 3322,
            "hero_count": 9,
            "hero_x": 9730,
            "hero_y": 1025,
            "hero_z": 762,
            "hero_beta": 2436,
            "candidate_x": 9714,
            "candidate_y": 1273,
            "candidate_z": 881,
        }

    def test_scene2_secret_room_door_membership_uses_decoded_inclusive_bounds(self) -> None:
        zones = secret_room_door_watch.zone_membership(9730, 1025, 762)

        self.assertEqual(
            [
                {
                    "index": 0,
                    "type": "change_cube",
                    "num": 0,
                    "name": "scene2_secret_room_door_cube0",
                }
            ],
            zones,
        )

    def test_snapshot_reads_transition_globals_hero_position_and_zone_membership(self) -> None:
        values = self.base_values()
        reader = FakeReader(values)

        snap = secret_room_door_watch.snapshot(reader.read_i32)

        self.assertEqual(1, snap["active_cube"])
        self.assertEqual(-1, snap["new_cube"])
        self.assertEqual(2562, snap["new_pos_x"])
        self.assertEqual(2049, snap["new_pos_y"])
        self.assertEqual(3322, snap["new_pos_z"])
        self.assertEqual(9730, snap["hero_x"])
        self.assertEqual(
            [
                {
                    "index": 0,
                    "type": "change_cube",
                    "num": 0,
                    "name": "scene2_secret_room_door_cube0",
                }
            ],
            snap["zones"],
        )

    def test_record_key_changes_when_new_position_changes(self) -> None:
        values = self.base_values()
        first = secret_room_door_watch.snapshot(FakeReader(values).read_i32)
        changed = dict(values)
        changed["new_pos_z"] = 3584
        second = secret_room_door_watch.snapshot(FakeReader(changed).read_i32)

        self.assertNotEqual(
            secret_room_door_watch.record_key(first),
            secret_room_door_watch.record_key(second),
        )

    def test_watch_once_writes_one_jsonl_row(self) -> None:
        reader = FakeReader(self.base_values())

        with tempfile.TemporaryDirectory() as temp_dir:
            out_path = Path(temp_dir) / "door-watch.jsonl"
            rows_written = secret_room_door_watch.watch(
                reader,
                out_path,
                duration_sec=0,
                poll_sec=0.001,
                once=True,
            )

            lines = out_path.read_text(encoding="utf-8").splitlines()

        self.assertEqual(1, rows_written)
        self.assertEqual(1, len(lines))
        self.assertIn('"active_cube":1', lines[0])
        self.assertIn('"new_pos_z":3322', lines[0])


if __name__ == "__main__":
    unittest.main()
