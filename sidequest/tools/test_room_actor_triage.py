from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from room_actor_triage import load_actor_summaries, render_report


def actor(
    *,
    scene_object_index: int,
    array_index: int,
    life_status: str,
    life_instruction_count: int,
    track_instruction_count: int,
    move_speed: int,
    life_points: int,
    armor: int,
    bonus_count: int,
    file3d_index: int,
) -> dict[str, object]:
    return {
        "scene_object_index": scene_object_index,
        "array_index": array_index,
        "life": {
            "audit": {
                "status": life_status,
                "instruction_count": life_instruction_count,
            }
        },
        "track": {"instruction_count": track_instruction_count},
        "mapped": {
            "movement": {"move": move_speed},
            "combat": {
                "life_points": life_points,
                "armor": armor,
                "bonus_count": bonus_count,
            },
            "render_source": {"file3d_index": file3d_index},
        },
    }


def payload(actors: list[dict[str, object]]) -> dict[str, object]:
    return {
        "selection": {
            "scene": {"resolved_entry_index": 11},
            "background": {"resolved_entry_index": 10},
        },
        "actors": actors,
    }


class RoomActorTriageTests(unittest.TestCase):
    def write_payload(self, root: Path, name: str, contents: dict[str, object]) -> Path:
        path = root / name
        path.write_text(json.dumps(contents), encoding="utf-8")
        return path

    def test_render_report_prefers_richer_life_and_track_over_mobility_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            path = self.write_payload(
                root,
                "11-10.json",
                payload(
                    [
                        actor(
                            scene_object_index=2,
                            array_index=1,
                            life_status="decoded",
                            life_instruction_count=81,
                            track_instruction_count=29,
                            move_speed=8,
                            life_points=255,
                            armor=51,
                            bonus_count=0,
                            file3d_index=42,
                        ),
                        actor(
                            scene_object_index=12,
                            array_index=11,
                            life_status="decoded",
                            life_instruction_count=59,
                            track_instruction_count=29,
                            move_speed=0,
                            life_points=255,
                            armor=51,
                            bonus_count=0,
                            file3d_index=16,
                        ),
                        actor(
                            scene_object_index=30,
                            array_index=29,
                            life_status="decoded",
                            life_instruction_count=8,
                            track_instruction_count=35,
                            move_speed=7,
                            life_points=45,
                            armor=11,
                            bonus_count=8,
                            file3d_index=31,
                        ),
                    ]
                ),
            )

            report = render_report(load_actor_summaries(path), top_n=3)

            self.assertLess(report.index("1. actor 2"), report.index("2. actor 12"))
            self.assertLess(report.index("2. actor 12"), report.index("3. actor 30"))

    def test_render_report_demotes_non_decoded_actor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            path = self.write_payload(
                root,
                "11-10.json",
                payload(
                    [
                        actor(
                            scene_object_index=5,
                            array_index=4,
                            life_status="raw_only",
                            life_instruction_count=120,
                            track_instruction_count=40,
                            move_speed=8,
                            life_points=255,
                            armor=51,
                            bonus_count=0,
                            file3d_index=42,
                        ),
                        actor(
                            scene_object_index=6,
                            array_index=5,
                            life_status="decoded",
                            life_instruction_count=12,
                            track_instruction_count=5,
                            move_speed=0,
                            life_points=10,
                            armor=1,
                            bonus_count=0,
                            file3d_index=14,
                        ),
                    ]
                ),
            )

            report = render_report(load_actor_summaries(path), top_n=2)

            self.assertLess(report.index("1. actor 6"), report.index("2. actor 5"))
            self.assertIn("actor 5 [decode-risk]", report)


if __name__ == "__main__":
    unittest.main()
