from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parent / "life_trace" / "secret_room_key_frida_probe.py"
SPEC = importlib.util.spec_from_file_location("secret_room_key_frida_probe", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
secret_room_key_frida_probe = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = secret_room_key_frida_probe
SPEC.loader.exec_module(secret_room_key_frida_probe)


class SecretRoomKeyFridaProbeTests(unittest.TestCase):
    def test_summary_requires_found_object_and_key_extra_for_bridge_claim(self) -> None:
        events = [
            {
                "kind": "lm_found_object",
                "payload": {
                    "operand": 0,
                    "ptr_prg_offset": 84,
                },
            },
            {
                "kind": "key_extra_state",
                "payload": {
                    "key_extras": [
                        {
                            "sprite": 6,
                            "divers": 1,
                            "pos_x": 3826,
                            "pos_y": 2144,
                            "pos_z": 4366,
                            "org_x": 3072,
                            "org_y": 3072,
                            "org_z": 5120,
                        }
                    ]
                },
            },
        ]

        summary = secret_room_key_frida_probe.summarize_events(events)

        self.assertEqual(1, summary["lm_found_object_0_hits"])
        self.assertEqual(1, summary["key_extra_state_events"])
        self.assertTrue(summary["observed_found_to_key_extra"])
        self.assertFalse(summary["observed_key_counter_increment"])

    def test_summary_recognizes_key_counter_increment(self) -> None:
        events = [
            {
                "kind": "key_counter_change",
                "payload": {
                    "previous_nb_little_keys": 0,
                    "nb_little_keys": 1,
                },
            }
        ]

        summary = secret_room_key_frida_probe.summarize_events(events)

        self.assertEqual(1, summary["key_counter_changes"])
        self.assertTrue(summary["observed_key_counter_increment"])
        self.assertFalse(summary["observed_key_extra_to_counter_increment"])

    def test_summary_recognizes_key_extra_before_counter_increment(self) -> None:
        events = [
            {
                "t": 1.25,
                "kind": "key_extra_state",
                "payload": {
                    "key_extras": [
                        {
                            "sprite": 6,
                            "divers": 1,
                        }
                    ]
                },
            },
            {
                "t": 2.0,
                "kind": "key_counter_change",
                "payload": {
                    "previous_nb_little_keys": 0,
                    "nb_little_keys": 1,
                },
            },
        ]

        summary = secret_room_key_frida_probe.summarize_events(events)

        self.assertTrue(summary["observed_key_extra_to_counter_increment"])
        self.assertEqual(1.25, summary["first_key_extra_time"])
        self.assertEqual(2.0, summary["first_key_counter_increment_time"])

    def test_generated_script_uses_staged_constants(self) -> None:
        script = secret_room_key_frida_probe.build_script(poll_ms=25)

        self.assertIn("0x0049a0a6", script)
        self.assertIn("0x004a7428", script)
        self.assertIn("const SPRITE_CLE = 6", script)
        self.assertIn("}, 25);", script)
        self.assertIn("Interceptor.attach(ADDR.doLifeLoop", script)

    def test_poll_only_script_omits_life_interpreter_hooks(self) -> None:
        script = secret_room_key_frida_probe.build_script(poll_ms=25, hook_life=False)

        self.assertIn("0x0049a0a6", script)
        self.assertIn("0x004a7428", script)
        self.assertNotIn("Interceptor.attach", script)


if __name__ == "__main__":
    unittest.main()
