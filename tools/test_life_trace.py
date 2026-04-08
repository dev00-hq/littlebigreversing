from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import msgspec

sys.path.insert(0, str(Path(__file__).resolve().parent / "life_trace"))

import trace_life


STATUS_LINE = """{"event_id": "evt-0001", "frida_lib": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\frida\\\\x86_64", "frida_module": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages\\\\frida\\\\__init__.py", "frida_repo_root": "D:\\\\repos\\\\reverse\\\\frida", "frida_root": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida", "frida_site_packages": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages", "kind": "status", "launch_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\_innoextract_full\\\\Speedrun\\\\Windows\\\\LBA2_cdrom\\\\LBA2\\\\LBA2.EXE", "message": "attached", "mode": "tavern-trace", "output_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\life_trace\\\\life-trace-20260405-011732.jsonl", "phase": "attached", "pid": 25148, "process_name": "LBA2.EXE", "timestamp_utc": "2026-04-05T05:17:33Z"}"""
TARGET_VALIDATION_LINE = """{"event_id": "evt-0005", "fingerprint_hex_actual": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_hex_expected": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_start_offset": 40, "kind": "target_validation", "matches_fingerprint": true, "object_index": 0, "owner_kind": "hero", "ptr_life": "0x33a21fb", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
BRANCH_TRACE_LINE = """{"branch_kind": "break_jump", "computed_target_offset": 103, "event_id": "evt-0014", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "kind": "branch_trace", "object_index": 0, "operand_offset": 103, "ptr_prg_offset_before": 4805, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
WINDOW_TRACE_LINE = """{"current_object": "0x49a19c", "event_id": "evt-0015", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "working_type_answer": 4, "working_value": 0}"""
SCREENSHOT_LINE = """{"capture_status": "captured", "event_id": "evt-0015", "kind": "screenshot", "poi": "opcode_076_fetch", "screenshot_path": "work/life_trace/shots/life-trace-20260405-011732/evt-0015__opcode_076_fetch__obj0__off4883.png", "source_window_title": "LBA2", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
VERDICT_LINE = """{"break_target_offset": 103, "event_id": "evt-0018", "fingerprint_event_id": "evt-0005", "hidden_076_case_seen": false, "kind": "verdict", "matched_fingerprint": true, "opcode_076_fetch_event_id": "evt-0015", "phase": "completed", "post_076_outcome": "loop_reentry", "post_076_outcome_event_id": "evt-0017", "reason": "captured Tavern proof through loop_reentry", "required_screenshots_complete": true, "result": "tavern_trace_complete", "returned_after_076": false, "saw_076_fetch": true, "saw_post_076_loop": true, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
ERROR_LINE = """{"event_id": "evt-0099", "kind": "error", "description": "boom", "stack": null, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
SCREENSHOT_ERROR_LINE = """{"capture_status": "failed", "event_id": "evt-0005", "kind": "screenshot_error", "poi": "final_verdict", "reason": "window for pid 1 did not become capturable within 10 seconds", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
TRACE_LINE = """{"byte_at_ptr_prg": 118, "byte_at_ptr_prg_hex": "0x76", "current_object": "0x49a19c", "event_id": "evt-0040", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "trace_role": "primary", "working_type_answer": 4, "working_value": 0}"""
DO_LIFE_RETURN_LINE = """{"byte_at_ptr_prg": 116, "byte_at_ptr_prg_hex": "0x74", "current_object": "0x49b0f0", "entered_do_func_life": false, "entered_do_test": true, "event_id": "evt-0041", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "fetched_in_do_life_loop": true, "kind": "do_life_return", "next_opcode": 13, "next_opcode_hex": "0x0d", "object_index": 12, "offset_life": 38, "owner_kind": "object", "post_hit_outcome": "do_life_return", "ptr_life": "0x4120000", "ptr_prg_after": "0x41200f1", "ptr_prg_after_offset": 39, "ptr_prg_before": "0x41200f0", "ptr_prg_before_offset": 38, "ptr_window_after": {"bytes_hex": "74 17 01 0d 00 02", "cursor_index": 1, "start": "0x41200f0"}, "ptr_window_before": {"bytes_hex": "42 00 75 2d 00 74 17 01 0d", "cursor_index": 5, "start": "0x41200eb"}, "thread_id": 9876, "timestamp_utc": "2026-04-05T05:17:42Z", "trace_role": "primary", "working_type_answer_after": 4, "working_type_answer_before": 4, "working_value_after": 0, "working_value_before": 0}"""


class LifeTraceSchemaTest(unittest.TestCase):
    def test_persisted_event_samples_decode(self) -> None:
        samples = {
            trace_life.PersistedStatusEvent: STATUS_LINE,
            trace_life.PersistedTargetValidationEvent: TARGET_VALIDATION_LINE,
            trace_life.PersistedBranchTraceEvent: BRANCH_TRACE_LINE,
            trace_life.PersistedWindowTraceEvent: WINDOW_TRACE_LINE,
            trace_life.PersistedScreenshotEvent: SCREENSHOT_LINE,
            trace_life.PersistedVerdictEvent: VERDICT_LINE,
            trace_life.PersistedErrorEvent: ERROR_LINE,
            trace_life.PersistedScreenshotErrorEvent: SCREENSHOT_ERROR_LINE,
            trace_life.PersistedTraceEvent: TRACE_LINE,
            trace_life.PersistedDoLifeReturnEvent: DO_LIFE_RETURN_LINE,
        }

        for expected_type, line in samples.items():
            with self.subTest(expected_type=expected_type.__name__):
                event = trace_life.parse_persisted_event_line(line)
                self.assertIsInstance(event, expected_type)

    def test_agent_payload_samples_decode(self) -> None:
        payloads = {
            trace_life.AgentStatusEvent: {
                "kind": "status",
                "message": "life trace agent loaded",
                "module_name": "LBA2.EXE",
                "module_base": "0x400000",
                "config": {
                    "moduleName": "LBA2.EXE",
                    "mode": "tavern-trace",
                    "logAll": False,
                    "maxHits": 1,
                    "targetObject": 0,
                    "targetOpcode": 118,
                    "targetOffset": 4883,
                    "windowBefore": 8,
                    "windowAfter": 8,
                    "focusOffsetStart": 4780,
                    "focusOffsetEnd": 4890,
                    "fingerprintOffset": 40,
                    "fingerprintHex": "28 14 00 21 2F 00 23 0D 0E 00",
                    "fingerprintBytes": [40, 20, 0, 33, 47, 0, 35, 13, 14, 0],
                    "comparisonObject": None,
                    "comparisonOpcode": None,
                    "comparisonOffset": None,
                },
            },
            trace_life.AgentTargetValidationEvent: {
                "kind": "target_validation",
                "thread_id": 21624,
                "object_index": 0,
                "owner_kind": "hero",
                "ptr_life": "0x33a21fb",
                "fingerprint_start_offset": 40,
                "fingerprint_hex_actual": "28 14 00 21 2F 00 23 0D 0E 00",
                "fingerprint_hex_expected": "28 14 00 21 2F 00 23 0D 0E 00",
                "matches_fingerprint": True,
            },
            trace_life.AgentBranchTraceEvent: json.loads(BRANCH_TRACE_LINE.replace('"event_id": "evt-0014", ', "").replace(', "timestamp_utc": "2026-04-05T05:17:42Z"', "")),
            trace_life.AgentWindowTraceEvent: json.loads(WINDOW_TRACE_LINE.replace('"event_id": "evt-0015", ', "").replace(', "timestamp_utc": "2026-04-05T05:17:42Z"', "")),
            trace_life.AgentTraceEvent: json.loads(TRACE_LINE.replace('"event_id": "evt-0040", ', "").replace(', "timestamp_utc": "2026-04-05T05:17:42Z"', "")),
            trace_life.AgentDoLifeReturnEvent: json.loads(DO_LIFE_RETURN_LINE.replace('"event_id": "evt-0041", ', "").replace(', "timestamp_utc": "2026-04-05T05:17:42Z"', "")),
            trace_life.AgentErrorEvent: {
                "kind": "error",
                "description": "boom",
                "stack": None,
            },
        }

        for expected_type, payload in payloads.items():
            with self.subTest(expected_type=expected_type.__name__):
                event = trace_life.convert_agent_event(payload)
                self.assertIsInstance(event, expected_type)

    def test_round_trip_preserves_status_config_field_names(self) -> None:
        event = trace_life.PersistedStatusEvent(
            event_id="evt-0001",
            timestamp_utc="2026-04-05T05:17:33Z",
            message="life trace agent loaded",
            config=trace_life.TraceConfig(
                module_name="LBA2.EXE",
                mode="tavern-trace",
                log_all=False,
                max_hits=1,
                target_object=0,
                target_opcode=118,
                target_offset=4883,
                window_before=8,
                window_after=8,
                focus_offset_start=4780,
                focus_offset_end=4890,
                fingerprint_offset=40,
                fingerprint_hex="28 14 00 21 2F 00 23 0D 0E 00",
                fingerprint_bytes=[40, 20, 0, 33, 47, 0, 35, 13, 14, 0],
                comparison_object=None,
                comparison_opcode=None,
                comparison_offset=None,
            ),
            module_name="LBA2.EXE",
            module_base="0x400000",
        )
        line = trace_life.serialize_persisted_event(event)
        payload = json.loads(line)
        self.assertIn("moduleName", payload["config"])
        self.assertIn("logAll", payload["config"])
        self.assertNotIn("module_name", payload["config"])
        reparsed = trace_life.parse_persisted_event_line(line)
        self.assertIsInstance(reparsed, trace_life.PersistedStatusEvent)

    def test_round_trip_preserves_nested_wire_shapes(self) -> None:
        event = trace_life.PersistedWindowTraceEvent(
            event_id="evt-0015",
            timestamp_utc="2026-04-05T05:17:42Z",
            thread_id=21624,
            object_index=0,
            owner_kind="hero",
            current_object="0x49a19c",
            ptr_life="0x33a21fb",
            offset_life=47,
            matches_target=True,
            ptr_prg="0x33a350e",
            ptr_prg_offset=4883,
            opcode=118,
            opcode_hex="0x76",
            ptr_window=trace_life.PointerWindow(
                start="0x33a3506",
                cursor_index=8,
                bytes_hex="00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09",
            ),
            working_type_answer=4,
            working_value=0,
            exe_switch=trace_life.ExeSwitchState(func=0, type_answer=0, value=0),
        )
        payload = json.loads(trace_life.serialize_persisted_event(event))
        self.assertIn("cursor_index", payload["ptr_window"])
        self.assertIn("type_answer", payload["exe_switch"])
        self.assertNotIn("cursorIndex", payload["ptr_window"])

    def test_writer_allows_event_id_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir) / "trace.jsonl")
            try:
                writer.write_event(
                    trace_life.PersistedScreenshotEvent(
                        poi="final_verdict",
                        screenshot_path="work/life_trace/example.png",
                        source_window_title="LBA2",
                        capture_status="captured",
                    ),
                    event_id="evt-0042",
                )
                writer.write_event(
                    trace_life.PersistedVerdictEvent(
                        phase="completed",
                        matched_fingerprint=True,
                        required_screenshots_complete=True,
                        result="ok",
                        reason="all good",
                    ),
                    event_id="evt-0042",
                )
            finally:
                writer.close()

            lines = [
                json.loads(line)
                for line in (Path(temp_dir) / "trace.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertEqual(["evt-0042", "evt-0042"], [line["event_id"] for line in lines])

    def test_negative_unknown_field_is_rejected(self) -> None:
        payload = {
            "kind": "target_validation",
            "thread_id": 1,
            "object_index": 0,
            "owner_kind": "hero",
            "ptr_life": "0x1",
            "fingerprint_start_offset": 40,
            "fingerprint_hex_actual": "AA",
            "fingerprint_hex_expected": "AA",
            "matches_fingerprint": True,
            "unexpected": 1,
        }
        with self.assertRaises(msgspec.ValidationError):
            trace_life.convert_agent_event(payload)

    def test_negative_missing_required_field_is_rejected(self) -> None:
        payload = {
            "kind": "branch_trace",
            "branch_kind": "break_jump",
            "object_index": 0,
            "ptr_prg_offset_before": 4805,
            "operand_offset": 103,
            "computed_target_offset": 103,
            "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0},
            "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0},
        }
        with self.assertRaises(msgspec.ValidationError):
            trace_life.convert_agent_event(payload)

    def test_negative_wrong_field_type_is_rejected(self) -> None:
        payload = json.loads(SCREENSHOT_LINE)
        payload["capture_status"] = False
        with self.assertRaises(msgspec.ValidationError):
            trace_life.convert_persisted_event(payload)

    def test_trace_help_works(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]
        result = subprocess.run(
            [sys.executable, str(repo_root / "tools" / "life_trace" / "trace_life.py"), "--help"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Bounded Frida probe for the original Windows LBA2 life interpreter.", result.stdout)


if __name__ == "__main__":
    unittest.main()
