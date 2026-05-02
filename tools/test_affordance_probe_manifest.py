from __future__ import annotations

import json
import tempfile
from pathlib import Path
import unittest

from tools import affordance_probe_manifest


class AffordanceProbeManifestTests(unittest.TestCase):
    def test_checked_in_manifest_validates_existing_magic_ball_switch_proof(self) -> None:
        result = affordance_probe_manifest.validate_manifest(
            affordance_probe_manifest.DEFAULT_MANIFEST_ROOT
            / "magic_ball_switch_activation_emerald_moon.json"
        )

        self.assertEqual("magic_ball_switch_activation_emerald_moon", result["id"])
        self.assertEqual(
            "phase5_magic_ball_switch_activation_emerald_moon",
            result["promotion_packet_id"],
        )
        self.assertEqual([3, 4], result["validated_targets"])
        self.assertEqual([3, 4], [artifact["target_object_index"] for artifact in result["artifacts"]])

    def test_checked_in_manifest_validates_existing_magic_ball_lever_proof(self) -> None:
        result = affordance_probe_manifest.validate_manifest(
            affordance_probe_manifest.DEFAULT_MANIFEST_ROOT
            / "magic_ball_lever_activation_multi_family.json"
        )

        self.assertEqual("magic_ball_lever_activation_multi_family", result["id"])
        self.assertEqual(
            "phase5_magic_ball_lever_activation_multi_family",
            result["promotion_packet_id"],
        )
        self.assertEqual([19, 2], result["validated_targets"])
        self.assertEqual(
            [19, 19, 2],
            [artifact["target_object_index"] for artifact in result["artifacts"]],
        )

    def test_rejects_absolute_repo_paths(self) -> None:
        with self.assertRaisesRegex(
            affordance_probe_manifest.AffordanceProbeManifestError,
            "path must be repo-relative",
        ):
            affordance_probe_manifest.repo_path(str(Path.cwd().resolve()))

    def test_rejects_unpromoted_target_expectation(self) -> None:
        base = (
            affordance_probe_manifest.DEFAULT_MANIFEST_ROOT
            / "magic_ball_switch_activation_emerald_moon.json"
        )
        manifest = json.loads(base.read_text(encoding="utf-8"))
        manifest["expected"]["target_object_indices"] = [2, 3, 4]

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaisesRegex(
                affordance_probe_manifest.AffordanceProbeManifestError,
                "observed run target order mismatch",
            ):
                affordance_probe_manifest.validate_manifest(path)

    def test_rejects_unknown_observer(self) -> None:
        base = (
            affordance_probe_manifest.DEFAULT_MANIFEST_ROOT
            / "magic_ball_switch_activation_emerald_moon.json"
        )
        manifest = json.loads(base.read_text(encoding="utf-8"))
        manifest["observers"].append("raw_memory_guess")

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaisesRegex(
                affordance_probe_manifest.AffordanceProbeManifestError,
                "unsupported observers",
            ):
                affordance_probe_manifest.validate_manifest(path)

    def test_rejects_missing_artifact_paths(self) -> None:
        base = (
            affordance_probe_manifest.DEFAULT_MANIFEST_ROOT
            / "magic_ball_switch_activation_emerald_moon.json"
        )
        manifest = json.loads(base.read_text(encoding="utf-8"))
        fixture_path = affordance_probe_manifest.repo_path(
            manifest["source"]["promotion_fixture"]
        )
        promotion = json.loads(fixture_path.read_text(encoding="utf-8"))
        promotion["observed_runs"][0]["timeline"] = "work/live_proofs/missing/timeline.jsonl"

        with tempfile.TemporaryDirectory(dir=affordance_probe_manifest.REPO_ROOT / "work") as tmp:
            fixture = Path(tmp) / "fixture.json"
            fixture.write_text(json.dumps(promotion), encoding="utf-8")
            local_manifest = Path(tmp) / "manifest.json"
            manifest["source"]["promotion_fixture"] = str(
                fixture.relative_to(affordance_probe_manifest.REPO_ROOT)
            )
            local_manifest.write_text(json.dumps(manifest), encoding="utf-8")

            with self.assertRaisesRegex(
                affordance_probe_manifest.AffordanceProbeManifestError,
                "timeline does not exist",
            ):
                affordance_probe_manifest.validate_manifest(local_manifest)


if __name__ == "__main__":
    unittest.main()
