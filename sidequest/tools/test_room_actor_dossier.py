from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from room_actor_dossier import actor_lookup, load_payload, render_dossier


def payload() -> dict[str, object]:
    return {
        "selection": {
            "scene": {"resolved_entry_index": 11},
            "background": {"resolved_entry_index": 10},
        },
        "actors": [
            {
                "scene_object_index": 2,
                "array_index": 1,
                "raw": {"move": 8, "armor": 51},
                "mapped": {
                    "movement": {"move": 8, "beta": 0, "speed_rotation": 0},
                    "combat": {"life_points": 255, "armor": 51, "bonus_count": 0, "hit_force": 0},
                    "render_source": {"file3d_index": 42},
                },
                "life": {"byte_length": 10, "audit": {"status": "decoded", "instruction_count": 81}},
                "track": {
                    "instruction_count": 29,
                    "instructions": [
                        {"mnemonic": "TM_LABEL"},
                        {"mnemonic": "TM_SAMPLE_STOP"},
                        {"mnemonic": "TM_SPEED"},
                    ],
                },
            }
        ],
    }


class RoomActorDossierTests(unittest.TestCase):
    def test_render_dossier_includes_key_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            path = Path(tmp_dir) / "11-10.json"
            path.write_text(json.dumps(payload()), encoding="utf-8")

            loaded = load_payload(path)
            actor = actor_lookup(loaded)[2]
            dossier = render_dossier(loaded, actor)

            self.assertIn("room 11/10 actor 2", dossier)
            self.assertIn("classification=behavior-rich", dossier)
            self.assertIn("track preview: TM_LABEL, TM_SAMPLE_STOP, TM_SPEED", dossier)
            self.assertIn('"move": 8', dossier)
            self.assertIn('"file3d_index": 42', dossier)


if __name__ == "__main__":
    unittest.main()
