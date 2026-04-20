from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


MODULE_PATH = Path(__file__).resolve().parent / "life_trace" / "dialog_text_dump.py"
SPEC = importlib.util.spec_from_file_location("dialog_text_dump", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
dialog_text_dump = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = dialog_text_dump
SPEC.loader.exec_module(dialog_text_dump)


class DialogTextDumpTests(unittest.TestCase):
    SENDHELL_TEXT = (
        "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. "
        "It will also enable Sendell to contact you in case of danger."
    )
    NEWGAME_TEXT = (
        "Twinsen, rush to the downtown pharmacy and find a cure for the Dino-Fly ! "
        "He has just crashed in the garden and looks injured."
    )

    def test_decode_dialog_bytes_respects_newline_and_terminator(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"Line 1\x01Line 2\x00Ignored")
        self.assertEqual("Line 1\nLine 2", decoded.text)
        self.assertEqual(13, decoded.record_byte_length)
        self.assertEqual((0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), decoded.source_offsets)

    def test_annotate_cursor_inside_record_marks_insertion_point(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"ABCD\x00")
        rendered = dialog_text_dump.annotate_cursor(decoded, 2)
        self.assertEqual("AB<<CURSOR>>CD", rendered)

    def test_annotate_cursor_at_terminator_marks_end(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"ABCD\x00")
        rendered = dialog_text_dump.annotate_cursor(decoded, decoded.record_byte_length)
        self.assertEqual("ABCD<<CURSOR>>", rendered)

    def test_annotate_cursor_after_record_marks_positive_overrun(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"ABCD\x00")
        rendered = dialog_text_dump.annotate_cursor(decoded, decoded.record_byte_length + 3)
        self.assertEqual("ABCD<<CURSOR>>+3", rendered)

    def test_cursor_state_classifies_offsets(self) -> None:
        self.assertEqual("inside_record", dialog_text_dump.cursor_state(2, 4))
        self.assertEqual("at_terminator", dialog_text_dump.cursor_state(4, 4))
        self.assertEqual("after_record", dialog_text_dump.cursor_state(5, 4))

    def test_split_text_at_cursor_inside_record(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"ABCD\x00")
        before, after = dialog_text_dump.split_text_at_cursor(decoded, 2)
        self.assertEqual("AB", before)
        self.assertEqual("CD", after)

    def test_split_text_at_cursor_at_terminator(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(b"ABCD\x00")
        before, after = dialog_text_dump.split_text_at_cursor(decoded, decoded.record_byte_length)
        self.assertEqual("ABCD", before)
        self.assertEqual("", after)

    def test_infer_next_page_split_starts_sendell_second_page_at_known_clause(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(self.SENDHELL_TEXT.encode("ascii") + b"\x00")
        cursor_offset = self.SENDHELL_TEXT.index(dialog_text_dump.ROOM36_PAGE2_PREFIX)
        page_slices = dialog_text_dump.infer_next_page_split(decoded, cursor_offset)
        self.assertEqual(
            "You just found Sendell's Ball. Now you have reached a new level of magic: Red Ball. "
            "It will also enable ",
            page_slices["text_before_cursor"],
        )
        self.assertEqual(dialog_text_dump.ROOM36_PAGE2_PREFIX, page_slices["text_from_cursor"])
        self.assertTrue(page_slices["cursor_is_next_page_boundary"])

    def test_infer_next_page_split_matches_newgame_page_boundary(self) -> None:
        decoded = dialog_text_dump.decode_dialog_bytes(self.NEWGAME_TEXT.encode("ascii") + b"\x00")
        cursor_offset = self.NEWGAME_TEXT.index("garden and looks injured.")
        page_slices = dialog_text_dump.infer_next_page_split(decoded, cursor_offset)
        self.assertEqual(
            "Twinsen, rush to the downtown pharmacy and find a cure for the Dino-Fly ! "
            "He has just crashed in the ",
            page_slices["text_before_cursor"],
        )
        self.assertEqual("garden and looks injured.", page_slices["text_from_cursor"])
        self.assertTrue(page_slices["cursor_is_next_page_boundary"])


if __name__ == "__main__":
    unittest.main()
