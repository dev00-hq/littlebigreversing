from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


LIFE_TRACE_PATH = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_PATH))
MODULE_PATH = LIFE_TRACE_PATH / "life_loss_cdb_watch.py"
SPEC = importlib.util.spec_from_file_location("life_loss_cdb_watch", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
life_loss_cdb_watch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = life_loss_cdb_watch
SPEC.loader.exec_module(life_loss_cdb_watch)


class LifeLossCdbWatchTests(unittest.TestCase):
    def test_clover_counter_address_uses_classic_flag_slot(self) -> None:
        self.assertEqual(0x00499E98, life_loss_cdb_watch.LIST_VAR_GAME_GLOBAL)
        self.assertEqual(251, life_loss_cdb_watch.FLAG_CLOVER)
        self.assertEqual(2, life_loss_cdb_watch.LIST_VAR_GAME_SLOT_SIZE)
        self.assertEqual(0x0049A08E, life_loss_cdb_watch.CLOVER_COUNTER)

    def test_build_cdb_commands_breaks_on_clover_write_and_dumps_stack(self) -> None:
        commands = life_loss_cdb_watch.build_cdb_commands()

        self.assertIn(".effmach x86", commands)
        self.assertIn("CDB_LIFE_LOSS_WATCH_ARMED address=0x0049a08e size=2 flag_clover=251", commands)
        self.assertIn('ba w2 0049a08e "r; ln @eip; u @eip L12; dw 0049a08e L1; kb 20; qd"', commands)
        self.assertNotIn("CDB_AGENT_WATCH", commands)


if __name__ == "__main__":
    unittest.main()
