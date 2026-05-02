from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path
import unittest

from tools import game_drive_checkpoint


class GameDriveCheckpointTests(unittest.TestCase):
    def checkpoint_path(self) -> Path:
        return (
            game_drive_checkpoint.DEFAULT_CHECKPOINT_ROOT
            / "pose_ready_magic_ball_middle_switch.json"
        )

    def test_checked_in_checkpoint_uses_declared_save_preview_visual_source(self) -> None:
        result = game_drive_checkpoint.validate_checkpoint(self.checkpoint_path())

        self.assertEqual("pose_ready_magic_ball_middle_switch", result["id"])
        self.assertEqual("existing_pose", result["pose"]["method"])
        self.assertEqual([], result["action_gate"])
        self.assertEqual("save_embedded_preview", result["visual_expect"]["source"])
        self.assertEqual("codex_exec", result["visual_expect"]["classifier"])
        self.assertTrue(result["visual_expect"]["summary_required"])
        self.assertEqual(2, len(result["visual_expect"]["negative_controls"]))

    def make_scratch_dir(self) -> Path:
        path = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_rejects_direct_pose_without_screenshot(self) -> None:
        checkpoint = json.loads(self.checkpoint_path().read_text(encoding="utf-8"))
        checkpoint["setup"]["pose"]["method"] = "direct_pose"
        checkpoint["visual_expect"]["source"] = "live_window_capture"
        checkpoint["visual_expect"]["screenshot_required"] = False

        path = self.make_scratch_dir() / "checkpoint.json"
        path.write_text(json.dumps(checkpoint), encoding="utf-8")

        with self.assertRaisesRegex(
            game_drive_checkpoint.GameDriveCheckpointError,
            "direct pose requires screenshot_required=true",
        ):
            game_drive_checkpoint.validate_checkpoint(path)

    def test_rejects_direct_pose_without_negative_visual_control(self) -> None:
        checkpoint = json.loads(self.checkpoint_path().read_text(encoding="utf-8"))
        checkpoint["setup"]["pose"]["method"] = "direct_pose"
        checkpoint["visual_expect"]["source"] = "live_window_capture"
        checkpoint["visual_expect"]["negative_controls"] = []

        path = self.make_scratch_dir() / "checkpoint.json"
        path.write_text(json.dumps(checkpoint), encoding="utf-8")

        with self.assertRaisesRegex(
            game_drive_checkpoint.GameDriveCheckpointError,
            "direct pose requires negative visual controls",
        ):
            game_drive_checkpoint.validate_checkpoint(path)

    def test_rejects_direct_pose_with_save_preview_visual_source(self) -> None:
        checkpoint = json.loads(self.checkpoint_path().read_text(encoding="utf-8"))
        checkpoint["setup"]["pose"]["method"] = "direct_pose"
        checkpoint["visual_expect"]["source"] = "save_embedded_preview"

        path = self.make_scratch_dir() / "checkpoint.json"
        path.write_text(json.dumps(checkpoint), encoding="utf-8")

        with self.assertRaisesRegex(
            game_drive_checkpoint.GameDriveCheckpointError,
            "direct pose requires live_window_capture visual source",
        ):
            game_drive_checkpoint.validate_checkpoint(path)

    def test_rejects_visual_result_without_summary_grounding(self) -> None:
        result_path = (
            game_drive_checkpoint.REPO_ROOT
            / "tools"
            / "fixtures"
            / "game_drive_visual_results"
            / "pose_ready_magic_ball_middle_switch_match.json"
        )
        result = json.loads(result_path.read_text(encoding="utf-8"))
        result["summary"] = "Looks fine."

        path = self.make_scratch_dir() / "result.json"
        path.write_text(json.dumps(result), encoding="utf-8")

        with self.assertRaisesRegex(
            game_drive_checkpoint.GameDriveCheckpointError,
            "visual summary must mention Twinsen",
        ):
            game_drive_checkpoint.validate_visual_result(self.checkpoint_path(), path)

    def test_checked_in_visual_result_matches_checkpoint(self) -> None:
        result = game_drive_checkpoint.validate_visual_result(
            self.checkpoint_path(),
            game_drive_checkpoint.REPO_ROOT
            / "tools"
            / "fixtures"
            / "game_drive_visual_results"
            / "pose_ready_magic_ball_middle_switch_match.json",
        )

        self.assertEqual("visual_checkpoint_matches", result["verdict"])
        self.assertEqual([], result["derived_mismatches"])

    def test_rejects_visual_result_matches_when_observed_fields_disagree(self) -> None:
        result_path = (
            game_drive_checkpoint.REPO_ROOT
            / "tools"
            / "fixtures"
            / "game_drive_visual_results"
            / "pose_ready_magic_ball_middle_switch_match.json"
        )
        result = json.loads(result_path.read_text(encoding="utf-8"))
        result["observed"]["target_visible"] = False

        path = self.make_scratch_dir() / "result.json"
        path.write_text(json.dumps(result), encoding="utf-8")

        with self.assertRaisesRegex(
            game_drive_checkpoint.GameDriveCheckpointError,
            "matches disagrees with observed fields",
        ):
            game_drive_checkpoint.validate_visual_result(self.checkpoint_path(), path)

    def test_prompt_declares_codex_exec_response_shape(self) -> None:
        checkpoint = game_drive_checkpoint.validate_checkpoint(self.checkpoint_path())
        prompt = game_drive_checkpoint.build_visual_prompt(
            checkpoint,
            "work/live_proofs/example/after_pose_set_before_action.png",
        )

        self.assertEqual("game-drive-visual-prompt-v1", prompt["schema"])
        self.assertEqual("game-drive-visual-classification-v1", prompt["required_response_schema"])
        self.assertIn("summary", prompt["response_shape"])
        self.assertEqual("codex", prompt["codex_exec"]["argv"][0])
        self.assertEqual("exec", prompt["codex_exec"]["argv"][1])
        self.assertIn("--image", prompt["codex_exec"]["argv"])
        self.assertIn("--output-schema", prompt["codex_exec"]["argv"])
        self.assertIn("summary_must_mention", prompt["codex_exec"]["stdin"])


if __name__ == "__main__":
    unittest.main()
