from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools import lba2_save_loader


class Lba2SaveLoaderAutosaveTests(unittest.TestCase):
    def test_direct_launch_autosave_guard_deletes_active_autosave(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            save_dir = Path(tmp)
            selected = save_dir / "selected.LBA"
            selected.write_bytes(b"selected")
            autosave = save_dir / "autosave.lba"
            autosave.write_bytes(b"original")

            deleted = lba2_save_loader.delete_autosave_before_direct_launch(save_dir, selected)

            self.assertTrue(deleted)
            self.assertFalse(autosave.exists())


if __name__ == "__main__":
    unittest.main()
