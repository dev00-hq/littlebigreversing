from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).resolve().parent / "life_trace" / "dialog_text_scan.py"
SPEC = importlib.util.spec_from_file_location("dialog_text_scan", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
dialog_text_scan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dialog_text_scan)


class DialogTextScanTests(unittest.TestCase):
    def test_extract_ascii_strings_keeps_long_runs(self) -> None:
        payload = b"\x00You just found Sendell's Ball.\x00abc\x00"
        strings = dialog_text_scan.extract_ascii_strings(payload, 10)
        self.assertEqual([(1, "You just found Sendell's Ball.")], strings)

    def test_extract_ascii_strings_splits_on_control_bytes(self) -> None:
        payload = b"Alpha Beta Gamma\x01Second readable line\x00"
        strings = dialog_text_scan.extract_ascii_strings(payload, 6)
        self.assertEqual(
            [
                (0, "Alpha Beta Gamma"),
                (17, "Second readable line"),
            ],
            strings,
        )


if __name__ == "__main__":
    unittest.main()
