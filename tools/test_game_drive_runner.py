from __future__ import annotations

import json
import shutil
import unittest
from pathlib import Path

from PIL import Image

from tools import game_drive_runner


class GameDriveRunnerTests(unittest.TestCase):
    def test_known_action_specs_parse_to_key_and_hold(self) -> None:
        self.assertEqual((0xBE, 0.75), game_drive_runner.action_to_key_hold("hold_period_0_75_sec_release"))
        self.assertEqual((0x6E, 0.75), game_drive_runner.action_to_key_hold("hold_numpad_decimal_0_75_sec_release"))
        self.assertEqual((0x57, 0.18), game_drive_runner.action_to_key_hold("press_w_0_18_sec"))
        self.assertEqual((0x25, 0.50), game_drive_runner.action_to_key_hold("hold_left_0_50_sec_release"))
        self.assertEqual((0x26, 0.50), game_drive_runner.action_to_key_hold("hold_up_0_50_sec_release"))
        self.assertEqual((0x75, 0.08), game_drive_runner.action_to_key_hold("press_f6_0_08_sec"))
        self.assertEqual((0x75, 0.50), game_drive_runner.action_to_key_hold("hold_f6_0_50_sec_release"))

    def test_unknown_action_fails_fast(self) -> None:
        with self.assertRaisesRegex(game_drive_runner.GameDriveRunnerError, "unsupported action"):
            game_drive_runner.action_to_key_hold("walk_somewhere")

    def test_combo_action_is_not_a_single_key_spec(self) -> None:
        with self.assertRaisesRegex(game_drive_runner.GameDriveRunnerError, "unsupported action"):
            game_drive_runner.action_to_key_hold("ctrl_right_behavior_cycle")

    def test_visual_prompt_includes_scene_and_target(self) -> None:
        checkpoint = {
            "id": "sample",
            "save": "sample.LBA",
            "visual_expect": {
                "source": "save_embedded_preview",
                "scene_description": "A room.",
                "target_description": "A lever.",
                "expected": {
                    "twinsen_visible": True,
                    "target_visible": True,
                    "ui_state": "gameplay",
                    "unsafe_pose_signs": False,
                },
                "summary_must_mention": ["Twinsen", "lever", "gameplay"],
            },
        }

        prompt = game_drive_runner.build_visual_prompt(checkpoint)

        self.assertIn("A room.", prompt)
        self.assertIn("A lever.", prompt)
        self.assertIn("summary_must_mention", prompt)

    def test_archive_game_drive_run_compresses_screenshots_and_links_manifest(self) -> None:
        root = game_drive_runner.REPO_ROOT / "work" / "unit_game_drive_archive_test"
        shutil.rmtree(root, ignore_errors=True)
        self.addCleanup(lambda: shutil.rmtree(root, ignore_errors=True))
        root.mkdir(parents=True)
        try:
            run_dir = root / "run"
            archive_root = root / "archive"
            run_dir.mkdir()
            screenshot = run_dir / "checkpoint.png"
            Image.new("RGB", (800, 600), color=(12, 34, 56)).save(screenshot)
            summary = {
                "schema": "game-drive-run-summary-v1",
                "checkpoint_id": "sample_checkpoint",
                "run_dir": game_drive_runner.repo_relative(run_dir),
                "verdict": "passed",
                "checkpoint_screenshot": game_drive_runner.repo_relative(screenshot),
                "evidence_archive": {
                    "archive_id": "event-1",
                    "manifest": game_drive_runner.repo_relative(archive_root / "event-1" / "manifest.json"),
                    "reason": "explicit",
                },
            }
            game_drive_runner.write_json(run_dir / "summary.json", summary)
            game_drive_runner.write_json(run_dir / "visual_result.json", {"matches": True})

            manifest = game_drive_runner.archive_game_drive_run(
                summary,
                run_dir,
                archive_root,
                event_id="event-1",
                reason="explicit",
            )

            archived_image = archive_root / "event-1" / "checkpoint_screenshot.webp"
            manifest_path = archive_root / "event-1" / "manifest.json"
            self.assertTrue(archived_image.is_file())
            self.assertFalse((archive_root / "event-1" / "checkpoint.png").exists())
            self.assertEqual("game-drive-evidence-archive-v1", manifest["schema"])
            loaded_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("sample_checkpoint", loaded_manifest["checkpoint_id"])
            self.assertEqual("webp", loaded_manifest["images"][0]["compression"]["format"])
            self.assertTrue((archive_root / "event-1" / "summary.json").is_file())
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
