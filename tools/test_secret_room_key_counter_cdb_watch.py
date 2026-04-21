from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest


LIFE_TRACE_PATH = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_PATH))
MODULE_PATH = LIFE_TRACE_PATH / "secret_room_key_counter_cdb_watch.py"
SPEC = importlib.util.spec_from_file_location("secret_room_key_counter_cdb_watch", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
secret_room_key_counter_cdb_watch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = secret_room_key_counter_cdb_watch
SPEC.loader.exec_module(secret_room_key_counter_cdb_watch)


class SecretRoomKeyCounterCdbWatchTests(unittest.TestCase):
    def test_build_cdb_commands_uses_command_file_friendly_breakpoint(self) -> None:
        commands = secret_room_key_counter_cdb_watch.build_cdb_commands(0x0049A0A6, 1)

        self.assertIn(".effmach x86", commands)
        self.assertIn(
            'ba w1 0049a0a6 "r; ln @eip; u @eip L8; db 0049a0a6 L1; db @ebp L80; db @edi L90; kb 12; qd"',
            commands,
        )
        self.assertIn("CDB_KEY_WATCH_ARMED", commands)
        self.assertNotIn("CDB_AGENT_WATCH", commands)


if __name__ == "__main__":
    unittest.main()
