from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from room_intelligence_triage import load_room_summary, ranked_rooms, render_report


def payload(
    *,
    scene_entry: int,
    background_entry: int,
    viewer_loadable: bool,
    scene_kind_status: str,
    fragment_status: str,
    hero_status: str,
    hero_instruction_count: int,
    actor_instruction_counts: list[int],
    fragment_layout_count: int | None = 0,
    runtime_tiles: int | None = None,
) -> dict[str, object]:
    composition: dict[str, object] = {
        "width": 64,
        "depth": 64,
        "cell_count": 4096,
        "unique_offset_count": 1,
    }
    if runtime_tiles is not None:
        composition["tiles"] = [{} for _ in range(runtime_tiles)]
        composition["height_grid"] = [0, 1]

    return {
        "selection": {
            "scene": {"resolved_entry_index": scene_entry},
            "background": {"resolved_entry_index": background_entry},
        },
        "scene": {
            "counts": {"decoded_actor_count": len(actor_instruction_counts)},
            "hero_start": {
                "life": {
                    "audit": {
                        "status": hero_status,
                        "instruction_count": hero_instruction_count,
                    }
                }
            },
        },
        "background": {"composition": composition},
        "validation": {
            "viewer_loadable": viewer_loadable,
            "scene_kind": {"status": scene_kind_status},
            "fragment_zones": {"status": fragment_status},
        },
        "actors": [
            {"life": {"audit": {"status": "decoded", "instruction_count": count}}}
            for count in actor_instruction_counts
        ],
    }
    if fragment_layout_count is not None:
        result["fragment_zone_layout"] = [{} for _ in range(fragment_layout_count)]
    return result


class RoomIntelligenceTriageTests(unittest.TestCase):
    def write_payload(self, root: Path, name: str, contents: dict[str, object]) -> Path:
        path = root / name
        path.write_text(json.dumps(contents), encoding="utf-8")
        return path

    def test_ranked_rooms_prefers_runtime_followup_with_fragment_layouts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            heavy = load_room_summary(
                self.write_payload(
                    root,
                    "11-10.json",
                    payload(
                        scene_entry=11,
                        background_entry=10,
                        viewer_loadable=True,
                        scene_kind_status="interior",
                        fragment_status="compatible",
                        hero_status="decoded",
                        hero_instruction_count=126,
                        actor_instruction_counts=[81, 40, 10],
                        fragment_layout_count=1,
                        runtime_tiles=3573,
                    ),
                )
            )
            simple = load_room_summary(
                self.write_payload(
                    root,
                    "2-2.json",
                    payload(
                        scene_entry=2,
                        background_entry=2,
                        viewer_loadable=True,
                        scene_kind_status="interior",
                        fragment_status="compatible",
                        hero_status="decoded",
                        hero_instruction_count=47,
                        actor_instruction_counts=[14, 1],
                    ),
                )
            )
            ranked = ranked_rooms([simple, heavy])

            self.assertEqual("11/10", ranked[0].summary.room_label)
            self.assertEqual("runtime-followup", ranked[0].verdict)
            self.assertEqual("2/2", ranked[1].summary.room_label)

    def test_ranked_rooms_demotes_non_viewer_loadable_rooms(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            blocked = load_room_summary(
                self.write_payload(
                    root,
                    "44-2.json",
                    payload(
                        scene_entry=44,
                        background_entry=2,
                        viewer_loadable=False,
                        scene_kind_status="non_interior",
                        fragment_status="skipped",
                        hero_status="decoded",
                        hero_instruction_count=197,
                        actor_instruction_counts=[113, 12],
                        fragment_layout_count=None,
                    ),
                )
            )
            ready = load_room_summary(
                self.write_payload(
                    root,
                    "19-19.json",
                    payload(
                        scene_entry=19,
                        background_entry=19,
                        viewer_loadable=True,
                        scene_kind_status="interior",
                        fragment_status="compatible",
                        hero_status="decoded",
                        hero_instruction_count=12,
                        actor_instruction_counts=[17, 1],
                    ),
                )
            )
            ranked = ranked_rooms([blocked, ready])
            report = render_report(ranked)

            self.assertEqual("19/19", ranked[0].summary.room_label)
            self.assertEqual("runtime-followup", ranked[0].verdict)
            self.assertEqual("decode-only", ranked[1].verdict)
            self.assertIn("44/2 [decode-only]", report)


if __name__ == "__main__":
    unittest.main()
