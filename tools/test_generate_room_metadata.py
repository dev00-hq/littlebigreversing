from __future__ import annotations

import ast
import re
import sys
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import generate_room_metadata as grm


class GenerateRoomMetadataParityTest(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.repo_root = TOOLS_DIR.parent
        self.generated_path = self.repo_root / grm.GENERATED_RELATIVE_PATH

    def test_checked_in_generated_scene_entries_match_legacy_corpus(self) -> None:
        generated = self._parse_generated_entries("scene")
        legacy = grm.load_legacy_entries(self.repo_root, "scene")
        grm.validate_legacy_parity("scene", generated, legacy)

    def test_checked_in_generated_background_entries_match_legacy_corpus(self) -> None:
        generated = self._parse_generated_entries("background")
        legacy = grm.load_legacy_entries(self.repo_root, "background")
        grm.validate_legacy_parity("background", generated, legacy)

    def _parse_generated_entries(self, kind: str) -> list[grm.GeneratedEntry]:
        text = self.generated_path.read_text(encoding="utf-8")
        if kind == "scene":
            block = text.split("pub const scene_entries: []const RoomMetadataEntry = &.{", 1)[1].split(
                "pub const background_entries",
                1,
            )[0]
        else:
            block = text.split("pub const background_entries: []const RoomMetadataEntry = &.{", 1)[1]

        entries: list[grm.GeneratedEntry] = []
        current_index: int | None = None
        current_display_name: str | None = None
        current_normalized_name: str | None = None

        for raw_line in block.splitlines():
            line = raw_line.strip()
            if line.startswith(".entry_index = "):
                current_index = int(line.removeprefix(".entry_index = ").rstrip(","))
            elif line.startswith(".display_name = "):
                current_display_name = self._parse_zig_string(line.removeprefix(".display_name = ").rstrip(","))
            elif line.startswith(".normalized_name = "):
                current_normalized_name = self._parse_zig_string(line.removeprefix(".normalized_name = ").rstrip(","))
            elif line == "},":
                if current_index is None or current_display_name is None or current_normalized_name is None:
                    continue
                entries.append(
                    grm.GeneratedEntry(
                        entry_index=current_index,
                        display_name=current_display_name,
                        normalized_name=current_normalized_name,
                    )
                )
                current_index = None
                current_display_name = None
                current_normalized_name = None

        self.assertGreater(len(entries), 0)
        return entries

    @staticmethod
    def _parse_zig_string(value: str) -> str:
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', value)
        if match is None:
            raise AssertionError(f"expected a Zig string literal, got {value!r}")
        return ast.literal_eval(value)


if __name__ == "__main__":
    unittest.main()
