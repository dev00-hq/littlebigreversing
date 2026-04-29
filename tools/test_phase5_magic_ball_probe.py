from __future__ import annotations

import tempfile
from pathlib import Path
import sys
import unittest

LIFE_TRACE_DIR = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_DIR))

from tools.life_trace import phase5_magic_ball_probe


class Phase5MagicBallProbeTests(unittest.TestCase):
    def test_changed_fields_reports_only_deltas(self) -> None:
        before = {"magic_ball_flag": 0, "active_cube": 1}
        after = {"magic_ball_flag": 1, "active_cube": 1}

        self.assertEqual(
            {"magic_ball_flag": {"before": 0, "after": 1}},
            phase5_magic_ball_probe.changed_fields(before, after),
        )

    def test_summary_promotes_only_zero_to_positive_magic_ball_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rows = [
                {
                    "phase": "initial",
                    "snapshot": {
                        "active_cube": 1,
                        "magic_ball_flag": 0,
                    },
                },
                {
                    "phase": "change",
                    "changes": {
                        "magic_ball_flag": {"before": 0, "after": 1},
                    },
                    "snapshot": {
                        "active_cube": 1,
                        "magic_ball_flag": 1,
                    },
                },
                {
                    "phase": "final",
                    "snapshot": {
                        "active_cube": 1,
                        "magic_ball_flag": 1,
                    },
                },
            ]

            summary = phase5_magic_ball_probe.summarize(
                rows,
                [],
                pid=1234,
                out_dir=Path(tmp),
                launched_save=None,
            )

        self.assertEqual("magic_ball_pickup_observed", summary["verdict"])
        self.assertTrue(summary["observed_magic_ball_flag_0_to_positive"])
        self.assertFalse(summary["observed_magic_ball_inventory_model_change"])

    def test_summary_rejects_already_owned_initial_flag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            summary = phase5_magic_ball_probe.summarize(
                [
                    {"phase": "initial", "snapshot": {"magic_ball_flag": 1}},
                    {"phase": "final", "snapshot": {"magic_ball_flag": 1}},
                ],
                [],
                pid=1234,
                out_dir=Path(tmp),
                launched_save=None,
            )

        self.assertEqual("magic_ball_pickup_not_observed", summary["verdict"])
        self.assertFalse(summary["observed_magic_ball_flag_0_to_positive"])

    def test_stage_runtime_save_returns_canonical_save_argument(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source" / "new-game-cellar.LBA"
            save_dir = root / "runtime" / "SAVE"
            source.parent.mkdir()
            source.write_bytes(b"save")

            launch_arg = phase5_magic_ball_probe.stage_runtime_save(source, save_dir)

            self.assertEqual(Path("SAVE") / "new-game-cellar.LBA", launch_arg)
            self.assertEqual(b"save", (save_dir / "new-game-cellar.LBA").read_bytes())


if __name__ == "__main__":
    unittest.main()
