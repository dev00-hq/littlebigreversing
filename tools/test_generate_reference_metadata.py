from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import generate_reference_metadata as grm


def write_fixture_tree(root: Path) -> None:
    (root / "LBA2" / "HQR" / "VOX").mkdir(parents=True, exist_ok=True)
    (root / "LBA2" / "GAME_STATE_FLAGS").mkdir(parents=True, exist_ok=True)
    (root / "LBA2" / "HQR" / "BODY.HQR.json").write_text(
        '{"entries":[{"type":"mesh","description":"Twinsen"},{"type":"","description":""}]}',
        encoding="utf-8",
    )
    (root / "LBA2" / "HQR" / "VOX" / "XX_GAM.VOX.json").write_text(
        '{"entries":[{"type":"wave_audio","description":"Holomap"}]}',
        encoding="utf-8",
    )
    (root / "LBA2" / "GAME_STATE_FLAGS" / "STATE_FLAGS.md").write_text(
        "\n".join(
            (
                "3: Sendell Ball",
                "19: Lightning Spell",
                "      19: nested detail that should be ignored",
            )
        ),
        encoding="utf-8",
        newline="\n",
    )


class GenerateReferenceMetadataTest(unittest.TestCase):
    maxDiff = None

    def test_build_rendered_module_includes_expected_entries_and_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            metadata_root = Path(tempdir)
            write_fixture_tree(metadata_root)

            rendered = grm.build_rendered_module(metadata_root)

            self.assertIn('pub const generated_relative_path = "port/src/generated/reference_metadata.zig";', rendered)
            self.assertIn('.entry_index = 1,', rendered)
            self.assertIn('.entry_type = "mesh",', rendered)
            self.assertIn('.entry_description = "Twinsen",', rendered)
            self.assertIn('pub const sendell_ball_flag = GameStateFlag{', rendered)
            self.assertIn('.display_name = "Sendell Ball",', rendered)
            self.assertIn('pub const lightning_spell_flag = GameStateFlag{', rendered)
            self.assertIn('.display_name = "Lightning Spell",', rendered)

    def test_check_mode_detects_drift_and_accepts_matching_output(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            output_path = Path(tempdir) / "reference_metadata.zig"
            rendered = "// generated output\n"

            self.assertEqual(1, grm.write_or_check_output(rendered, output_path, check=True))

            output_path.write_text(rendered, encoding="utf-8", newline="\n")
            self.assertEqual(0, grm.write_or_check_output(rendered, output_path, check=True))

            output_path.write_text("// stale output\n", encoding="utf-8", newline="\n")
            self.assertEqual(1, grm.write_or_check_output(rendered, output_path, check=True))


if __name__ == "__main__":
    unittest.main()
