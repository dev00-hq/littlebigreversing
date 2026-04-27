from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


LIFE_TRACE_PATH = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_PATH))
MODULE_PATH = LIFE_TRACE_PATH / "runtime_watch_run.py"
SPEC = importlib.util.spec_from_file_location("runtime_watch_run", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
runtime_watch_run = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runtime_watch_run
SPEC.loader.exec_module(runtime_watch_run)


class RuntimeWatchRunTests(unittest.TestCase):
    def test_phase5_0013_load_gate_uses_exact_save_pose(self) -> None:
        self.assertEqual(
            {
                "active_cube": 0,
                "hero_x": 3478,
                "hero_y": 2048,
                "hero_z": 4772,
                "hero_beta": 3584,
                "nb_little_keys": 0,
            },
            runtime_watch_run.EXPECTED_0013_LOAD,
        )

    def test_assert_expected_load_rejects_autosave_fallback(self) -> None:
        row = dict(runtime_watch_run.EXPECTED_0013_LOAD)
        row["active_cube"] = 95

        with self.assertRaisesRegex(RuntimeError, "did not load the expected 0013 save"):
            runtime_watch_run.assert_expected_load(row)

    def test_parse_runtime_watch_log_finds_life_loss_event(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "lba2_runtime_watch.log"
            path.write_text(
                "\n".join(
                    [
                        json.dumps({"event": "watch_started"}),
                        json.dumps({"event": "life_loss_detected", "previous": 6, "current": 5}),
                    ]
                ),
                encoding="utf-8",
            )

            events = runtime_watch_run.parse_runtime_watch_log(path)

        self.assertEqual("watch_started", events[0]["event"])
        self.assertEqual("life_loss_detected", events[1]["event"])


if __name__ == "__main__":
    unittest.main()
