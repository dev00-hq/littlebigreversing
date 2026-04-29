from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


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

    def test_parse_tasklist_csv_pids_ignores_info_rows(self) -> None:
        self.assertEqual(
            [1234, 5678],
            runtime_watch_run.parse_tasklist_csv_pids(
                '"LBA2.EXE","1234","Console","1","8,192 K"\n'
                'INFO: No tasks are running which match the specified criteria.\n'
                '"cdb.exe","5678","Console","1","4,096 K"\n'
            ),
        )

    def test_preflight_refuses_foreign_process_takeover_by_default(self) -> None:
        with mock.patch.object(
            runtime_watch_run,
            "list_running_image_pids",
            side_effect=lambda image: [111] if image == "LBA2.EXE" else [],
        ):
            with self.assertRaisesRegex(RuntimeError, "--takeover-existing-processes"):
                runtime_watch_run.preflight_process_ownership(takeover_existing_processes=False)

    def test_preflight_takeover_kills_only_running_images(self) -> None:
        with (
            mock.patch.object(
                runtime_watch_run,
                "list_running_image_pids",
                side_effect=lambda image: [111] if image == "LBA2.EXE" else [],
            ),
            mock.patch.object(runtime_watch_run, "kill_processes") as mocked_kill,
        ):
            running = runtime_watch_run.preflight_process_ownership(takeover_existing_processes=True)

        self.assertEqual({"LBA2.EXE": [111]}, running)
        mocked_kill.assert_called_once_with(("LBA2.EXE",))


if __name__ == "__main__":
    unittest.main()
