from __future__ import annotations

from pathlib import Path
import unittest

from tools.life_trace import save_object_context_dump


REPO_ROOT = Path(__file__).resolve().parents[1]
SAVE_DIR = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2" / "SAVE"


class SaveObjectContextDumpTests(unittest.TestCase):
    def test_lever_magic_ball_saved_slots_match_radar_room_runtime_probe_targets(self) -> None:
        payload = save_object_context_dump.dump_save_objects(SAVE_DIR / "lever-magic-ball.LBA")
        self.assertEqual("lba2-save-object-context-v1", payload["schema"])
        self.assertEqual(22, payload["object_count"])
        objects = {row["index"]: row for row in payload["objects"]}

        self.assertEqual((19205, 2816, 8432, 2954), self.object_pose(objects[0]))
        self.assertEqual(242, objects[19]["gen_anim"])
        self.assertEqual(242, objects[19]["next_gen_anim"])
        self.assertEqual((27617, 512, 12245, 2800), self.object_pose(objects[19]))
        self.assertEqual(3, objects[21]["label_track"])
        self.assertEqual((17280, 512, 12768, 1776), self.object_pose(objects[21]))

    def test_moon_switches_saved_slots_match_promoted_switch_targets(self) -> None:
        payload = save_object_context_dump.dump_save_objects(SAVE_DIR / "moon-switches-room.LBA")
        self.assertEqual(17, payload["object_count"])
        objects = {row["index"]: row for row in payload["objects"]}

        self.assertEqual((4866, 512, 8324, 2995), self.object_pose(objects[0]))
        self.assertEqual((2304, 1536, 9984, 0), self.object_pose(objects[2]))
        self.assertEqual((2304, 1536, 8448, 0), self.object_pose(objects[3]))
        self.assertEqual((2304, 1536, 6912, 0), self.object_pose(objects[4]))
        self.assertEqual(4, objects[3]["label_track"])
        self.assertEqual(2, objects[4]["label_track"])

    @staticmethod
    def object_pose(row: dict[str, int]) -> tuple[int, int, int, int]:
        return row["obj_x"], row["obj_y"], row["obj_z"], row["obj_beta"]


if __name__ == "__main__":
    unittest.main()
