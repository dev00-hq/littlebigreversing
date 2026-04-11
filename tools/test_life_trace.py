from __future__ import annotations

import argparse
import contextlib
import io
import json
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import msgspec

sys.path.insert(0, str(Path(__file__).resolve().parent / "life_trace"))

import trace_life


RUN_ID = "life-trace-20260405-011732"

STATUS_LINE = """{"event_id": "evt-0001", "frida_lib": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\frida\\\\x86_64", "frida_module": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages\\\\frida\\\\__init__.py", "frida_repo_root": "D:\\\\repos\\\\reverse\\\\frida", "frida_root": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida", "frida_site_packages": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages", "kind": "status", "launch_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\_innoextract_full\\\\Speedrun\\\\Windows\\\\LBA2_cdrom\\\\LBA2\\\\LBA2.EXE", "message": "attached", "mode": "tavern-trace", "output_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\life_trace\\\\runs\\\\life-trace-20260405-011732", "phase": "attached", "pid": 25148, "process_name": "LBA2.EXE", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "timestamp_utc": "2026-04-05T05:17:33Z"}"""
TARGET_VALIDATION_LINE = """{"event_id": "evt-0005", "fingerprint_hex_actual": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_hex_expected": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_start_offset": 40, "kind": "target_validation", "matches_fingerprint": true, "object_index": 0, "owner_kind": "hero", "ptr_life": "0x33a21fb", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
BRANCH_TRACE_LINE = """{"branch_kind": "break_jump", "computed_target_offset": 103, "event_id": "evt-0014", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "kind": "branch_trace", "object_index": 0, "operand_offset": 103, "ptr_prg_offset_before": 4805, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
WINDOW_TRACE_LINE = """{"current_object": "0x49a19c", "event_id": "evt-0015", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "working_type_answer": 4, "working_value": 0}"""
MINIMAL_TAVERN_WINDOW_TRACE_LINE = """{"byte_at_ptr_prg": 118, "byte_at_ptr_prg_hex": "0x76", "current_object": "0x49a19c", "event_id": "evt-0015", "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
SCREENSHOT_LINE = """{"capture_status": "captured", "event_id": "evt-0015", "kind": "screenshot", "poi": "opcode_076_fetch", "run_id": "life-trace-20260405-011732", "screenshot_path": "work/life_trace/runs/life-trace-20260405-011732/screenshots/evt-0015__opcode_076_fetch__obj0__off4883.png", "source_stream": "enriched", "source_window_title": "LBA2", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
VERDICT_LINE = """{"break_target_offset": 103, "event_id": "evt-0018", "fingerprint_event_id": "evt-0005", "hidden_076_case_seen": false, "kind": "verdict", "matched_fingerprint": true, "opcode_076_fetch_event_id": "evt-0015", "phase": "completed", "post_076_outcome": "loop_reentry", "post_076_outcome_event_id": "evt-0017", "reason": "captured Tavern proof through loop_reentry", "required_screenshots_complete": true, "result": "tavern_trace_complete", "returned_after_076": false, "run_id": "life-trace-20260405-011732", "saw_076_fetch": true, "saw_post_076_loop": true, "source_stream": "enriched", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
ERROR_LINE = """{"description": "boom", "event_id": "evt-0099", "kind": "error", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "stack": null, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
SCREENSHOT_ERROR_LINE = """{"capture_status": "failed", "event_id": "evt-0005", "kind": "screenshot_error", "poi": "final_verdict", "reason": "window for pid 1 did not become capturable within 10 seconds", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
TRACE_LINE = """{"byte_at_ptr_prg": 118, "byte_at_ptr_prg_hex": "0x76", "current_object": "0x49a19c", "event_id": "evt-0040", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "trace_role": "primary", "working_type_answer": 4, "working_value": 0}"""
DO_LIFE_RETURN_LINE = """{"byte_at_ptr_prg": 116, "byte_at_ptr_prg_hex": "0x74", "current_object": "0x49b0f0", "entered_do_func_life": false, "entered_do_test": true, "event_id": "evt-0041", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "fetched_in_do_life_loop": true, "kind": "do_life_return", "next_opcode": 13, "next_opcode_hex": "0x0d", "object_index": 12, "offset_life": 38, "owner_kind": "object", "post_hit_outcome": "do_life_return", "ptr_life": "0x4120000", "ptr_prg_after": "0x41200f1", "ptr_prg_after_offset": 39, "ptr_prg_before": "0x41200f0", "ptr_prg_before_offset": 38, "ptr_window_after": {"bytes_hex": "74 17 01 0d 00 02", "cursor_index": 1, "start": "0x41200f0"}, "ptr_window_before": {"bytes_hex": "42 00 75 2d 00 74 17 01 0d", "cursor_index": 5, "start": "0x41200eb"}, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 9876, "timestamp_utc": "2026-04-05T05:17:42Z", "trace_role": "primary", "working_type_answer_after": 4, "working_type_answer_before": 4, "working_value_after": 0, "working_value_before": 0}"""
HELPER_CALLSITE_LINE = """{"call_index": 0, "call_instruction": "ram:00420f4b", "callsite_status": "mapped", "callee_name": "DoTest", "caller_static_live": "0x420f50", "caller_static_rel": "0x00020F50", "event_id": "evt-0042", "kind": "helper_callsite", "object_index": 12, "opcode": 116, "opcode_hex": "0x74", "owner_kind": "object", "ptr_life": "0x4120000", "ptr_prg": "0x41200f0", "ptr_prg_offset": 38, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 9876, "timestamp_utc": "2026-04-05T05:17:42Z", "trace_role": "primary", "within_entry": "ram:00420574", "within_function": "FUN_00420574"}"""


def read_jsonl_lines(path: Path) -> list[dict[str, object]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def persisted_to_agent_payload(line: str) -> dict[str, object]:
    payload = json.loads(line)
    payload.pop("event_id", None)
    payload.pop("run_id", None)
    payload.pop("source_stream", None)
    payload.pop("timestamp_utc", None)
    return payload


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
            trace_life.PersistedHelperCallsiteEvent: HELPER_CALLSITE_LINE,
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
            trace_life.AgentBranchTraceEvent: persisted_to_agent_payload(BRANCH_TRACE_LINE),
            trace_life.AgentWindowTraceEvent: persisted_to_agent_payload(WINDOW_TRACE_LINE),
            trace_life.AgentTraceEvent: persisted_to_agent_payload(TRACE_LINE),
            trace_life.AgentDoLifeReturnEvent: persisted_to_agent_payload(DO_LIFE_RETURN_LINE),
            trace_life.AgentHelperCallsiteEvent: persisted_to_agent_payload(HELPER_CALLSITE_LINE),
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

    def test_minimal_tavern_window_trace_samples_decode(self) -> None:
        persisted = trace_life.parse_persisted_event_line(MINIMAL_TAVERN_WINDOW_TRACE_LINE)
        self.assertIsInstance(persisted, trace_life.PersistedWindowTraceEvent)

        payload = persisted_to_agent_payload(MINIMAL_TAVERN_WINDOW_TRACE_LINE)
        event = trace_life.convert_agent_event(payload)
        self.assertIsInstance(event, trace_life.AgentWindowTraceEvent)

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
            writer = trace_life.JsonlWriter(Path(temp_dir))
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

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual(["evt-0042", "evt-0042"], [line["event_id"] for line in lines])
            self.assertEqual(["enriched", "enriched"], [line["source_stream"] for line in lines])

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

    def test_load_agent_source_assembles_scene_fragments(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-pair"])
        script = trace_life.runtime.load_agent_source(args)

        self.assertNotIn("__TRACE_", script)
        self.assertIn('registerScene("basic"', script)
        self.assertIn('registerScene("tavern-trace"', script)
        self.assertIn('registerScene("scene11-pair"', script)
        self.assertIn('sendEvent("helper_callsite"', script)
        self.assertIn("const scene = createScene(config.mode);", script)
        self.assertIn('"mode":"scene11-pair"', script)
        self.assertIn('"helperCaptureEnabled":true', script)
        self.assertIn("maybeInstallScene11HelperHooks()", script)
        self.assertIn("helperHooksInstalled", script)

    def test_load_agent_source_fails_when_a_required_fragment_is_missing(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-pair"])
        missing_path = (Path(trace_life.runtime.__file__).with_name("agent") / "scene_scene11.js").resolve()
        original_exists = trace_life.runtime.Path.exists

        def fake_exists(path_obj) -> bool:
            if path_obj.resolve() == missing_path:
                return False
            return original_exists(path_obj)

        with mock.patch.object(trace_life.runtime.Path, "exists", autospec=True, side_effect=fake_exists):
            with self.assertRaises(RuntimeError) as raised:
                trace_life.runtime.load_agent_source(args)

        self.assertIn("life_trace agent fragment is missing", str(raised.exception))

    def test_parse_args_defaults_run_root_and_launch_path(self) -> None:
        args = trace_life.parse_args(["--mode", "tavern-trace", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_offset, args.target_offset)
        self.assertEqual(str(trace_life.DEFAULT_SAVE_SOURCE_ROOT / "inside-tavern.LBA"), args.launch_save)
        self.assertEqual(str(trace_life.DEFAULT_FRA_REPO_ROOT), args.fra_repo_root)
        self.assertIsNone(args.frida_repo_root)
        self.assertEqual(str(trace_life.DEFAULT_CALLSITES_JSONL), args.callsites_jsonl)
        self.assertEqual(str(trace_life.DEFAULT_RUN_ROOT), args.run_root)
        self.assertTrue(args.requires_callsite_map is False)
        self.assertTrue(args.helper_capture_enabled is False)

    def test_parse_args_defaults_scene11_to_fra_lane(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-pair", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_offset, args.target_offset)
        self.assertEqual(str(trace_life.DEFAULT_SAVE_SOURCE_ROOT / "S8741.LBA"), args.launch_save)
        self.assertEqual(str(trace_life.DEFAULT_FRA_REPO_ROOT), args.fra_repo_root)
        self.assertIsNone(args.frida_repo_root)
        self.assertEqual(str(trace_life.DEFAULT_CALLSITES_JSONL), args.callsites_jsonl)
        self.assertTrue(args.requires_callsite_map)
        self.assertTrue(args.helper_capture_enabled)

    def test_parse_args_rejects_explicit_targets_in_structured_modes(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(["--mode", "scene11-pair", "--target-object", "12"])
        self.assertIn(
            "--mode scene11-pair rejects --target-object, --target-opcode, and --target-offset",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_frida_root_for_tavern(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(
                    ["--mode", "tavern-trace", "--frida-repo-root", r"D:\repos\reverse\frida"]
                )
        self.assertIn(
            "--mode tavern-trace rejects --frida-repo-root; use --fra-repo-root",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_frida_root_for_scene11(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(
                    ["--mode", "scene11-pair", "--frida-repo-root", r"D:\repos\reverse\frida"]
                )
        self.assertIn(
            "--mode scene11-pair rejects --frida-repo-root; use --fra-repo-root",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_fra_root_for_basic(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(["--fra-repo-root", r"D:\repos\frida-agent-cli"])
        self.assertIn("--fra-repo-root requires --mode tavern-trace or --mode scene11-pair", stderr.getvalue())

    def test_fra_status_fields_extracts_doctor_paths(self) -> None:
        doctor_report = {
            "ok": True,
            "bootstrap": {
                "paths": {
                    "repo_root": r"D:\repos\reverse\frida",
                    "staged_root": r"D:\repos\reverse\frida\build\install-root\Program Files\Frida",
                    "site_packages": r"D:\repos\reverse\frida\build\install-root\Program Files\Frida\lib\site-packages",
                    "dll_dir": r"D:\repos\reverse\frida\build\install-root\Program Files\Frida\lib\frida\x86_64",
                }
            },
            "frida": {"module_path": r"D:\repos\reverse\frida\build\install-root\Program Files\Frida\lib\site-packages\frida\__init__.py"},
            "checks": [],
        }

        fields = trace_life.fra_status_fields(doctor_report)

        self.assertEqual(r"D:\repos\reverse\frida", fields["frida_repo_root"])
        self.assertEqual(
            r"D:\repos\reverse\frida\build\install-root\Program Files\Frida\lib\frida\x86_64",
            fields["frida_lib"],
        )

    def test_read_fra_probe_records_and_queue_messages_use_probe_tail(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_path = Path(temp_dir) / "probe.ndjson"
            runtime = trace_life.FraProbeRuntime(
                target_id="target-1",
                probe_id="probe-1",
                artifact_path=artifact_path,
            )
            message_queue: trace_life.queue.Queue[trace_life.AgentWireEventType] = trace_life.queue.Queue()

            with mock.patch.object(
                trace_life.runtime,
                "run_fra_json",
                return_value=[
                    {
                        "kind": "probe_message",
                        "message": {
                            "type": "send",
                            "payload": {
                                "kind": "status",
                                "message": "life trace agent loaded",
                            },
                        },
                    },
                    {"kind": "probe_lifecycle", "event": "loaded"},
                ],
            ) as mocked:
                records = trace_life.read_fra_probe_records(["fra"], runtime)
                trace_life.queue_fra_probe_messages(runtime, records, message_queue)

            mocked.assert_called_once_with(
                ["fra"],
                "probe",
                "tail",
                "--artifact",
                str(artifact_path),
                "--format",
                "json",
            )
            self.assertEqual(2, runtime.consumed_records)

            event = message_queue.get_nowait()
            self.assertIsInstance(event, trace_life.AgentStatusEvent)
            self.assertEqual("life trace agent loaded", event.message)

    def test_read_fra_probe_records_accepts_spilled_json_artifact_envelope(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_path = Path(temp_dir) / "probe.ndjson"
            spilled_path = Path(temp_dir) / "probe-tail.json"
            spilled_path.write_text(
                json.dumps(
                    [
                        {
                            "kind": "probe_message",
                            "message": {
                                "type": "send",
                                "payload": {
                                    "kind": "status",
                                    "message": "life trace agent loaded",
                                },
                            },
                        }
                    ]
                ),
                encoding="utf-8",
            )
            runtime = trace_life.FraProbeRuntime(
                target_id="target-1",
                probe_id="probe-1",
                artifact_path=artifact_path,
            )

            with mock.patch.object(
                trace_life.runtime,
                "run_fra_json",
                return_value={
                    "ok": True,
                    "artifact_path": str(spilled_path),
                    "format": "json",
                },
            ):
                records = trace_life.read_fra_probe_records(["fra"], runtime)

            self.assertEqual(1, len(records))
            self.assertEqual("probe_message", records[0]["kind"])

    def test_refresh_fra_probe_terminal_state_uses_probe_wait(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_path = Path(temp_dir) / "probe.ndjson"
            runtime = trace_life.FraProbeRuntime(
                target_id="target-1",
                probe_id="probe-1",
                artifact_path=artifact_path,
            )

            timeout = subprocess.CompletedProcess(
                args=["fra"],
                returncode=1,
                stdout="",
                stderr="timed out waiting for a matching probe artifact record",
            )
            detached = subprocess.CompletedProcess(
                args=["fra"],
                returncode=0,
                stdout=json.dumps(
                    {
                        "kind": "probe_lifecycle",
                        "event": "detached",
                        "reason": "target_detach",
                    }
                ),
                stderr="",
            )

            with mock.patch.object(trace_life.subprocess, "run", side_effect=[timeout, detached]) as mocked:
                trace_life.refresh_fra_probe_terminal_state(["fra"], runtime)

            self.assertEqual("detached", runtime.terminal_event)
            self.assertEqual("target_detach", runtime.terminal_reason)
            first_call = mocked.call_args_list[0]
            second_call = mocked.call_args_list[1]
            self.assertIn("--lifecycle-event", first_call.args[0])
            self.assertIn("terminated", first_call.args[0])
            self.assertIn("detached", second_call.args[0])

    def test_refresh_fra_probe_terminal_state_accepts_spilled_probe_wait_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_path = Path(temp_dir) / "probe.ndjson"
            spilled_path = Path(temp_dir) / "probe-wait.json"
            spilled_path.write_text(
                json.dumps(
                    {
                        "kind": "probe_lifecycle",
                        "event": "terminated",
                        "reason": "target_exit",
                    }
                ),
                encoding="utf-8",
            )
            runtime = trace_life.FraProbeRuntime(
                target_id="target-1",
                probe_id="probe-1",
                artifact_path=artifact_path,
            )

            completed = subprocess.CompletedProcess(
                args=["fra"],
                returncode=0,
                stdout=json.dumps(
                    {
                        "ok": True,
                        "artifact_path": str(spilled_path),
                        "format": "json",
                    }
                ),
                stderr="",
            )

            with mock.patch.object(trace_life.subprocess, "run", return_value=completed):
                trace_life.refresh_fra_probe_terminal_state(["fra"], runtime)

            self.assertEqual("terminated", runtime.terminal_event)
            self.assertEqual("target_exit", runtime.terminal_reason)


class TavernStartupAutomationTest(unittest.TestCase):
    def test_stage_tavern_load_game_save_keeps_current_and_stages_one_slot(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            launch_dir = Path(temp_dir) / "LBA2"
            save_dir = launch_dir / "SAVE"
            save_dir.mkdir(parents=True)
            launch_path = launch_dir / "LBA2.EXE"
            launch_path.write_bytes(b"exe")
            source_path = Path(temp_dir) / "inside-tavern.LBA"
            source_path.write_bytes(b"inside-tavern-save")
            current_path = save_dir / "current.lba"
            current_path.write_bytes(b"current-save")
            stray_path = save_dir / "autosave.lba"
            stray_path.write_bytes(b"stray")
            args = argparse.Namespace(launch_save=str(source_path))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                staged_source, staged_destination = trace_life.stage_tavern_load_game_save(args, writer, launch_path)
            finally:
                writer.close()

            self.assertEqual(source_path, staged_source)
            self.assertEqual(save_dir / "inside-tavern.LBA", staged_destination)
            self.assertEqual(b"inside-tavern-save", staged_destination.read_bytes())
            self.assertEqual(b"current-save", current_path.read_bytes())
            self.assertFalse(stray_path.exists())

            lines = read_jsonl_lines(writer.enriched_output_path)
            messages = [line["message"] for line in lines]
            self.assertIn(
                "restored canonical SAVE contents before staging the run fixture; removed autosave.lba",
                messages,
            )
            self.assertIn("staged inside-tavern.LBA into SAVE as the sole Load Game slot", messages)

    def test_stage_tavern_load_game_save_missing_fixture_is_an_explicit_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            launch_dir = Path(temp_dir) / "LBA2"
            save_dir = launch_dir / "SAVE"
            save_dir.mkdir(parents=True)
            launch_path = launch_dir / "LBA2.EXE"
            launch_path.write_bytes(b"exe")
            args = argparse.Namespace(launch_save=str(Path(temp_dir) / "missing-tavern-save.LBA"))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with self.assertRaises(RuntimeError) as raised:
                    trace_life.stage_tavern_load_game_save(args, writer, launch_path)
            finally:
                writer.close()

            self.assertIn("tavern-trace source save is missing", str(raised.exception))
            self.assertIn("ask the user to generate the savegame", str(raised.exception))

    def test_drive_tavern_launch_startup_drives_adeline_and_load_game(self) -> None:
        class FakeWindowCapture:
            def __init__(self) -> None:
                self.wait_calls: list[tuple[int, float]] = []

            def wait_for_window(self, pid: int, timeout_sec: float = 10.0) -> trace_life.WindowInfo:
                self.wait_calls.append((pid, timeout_sec))
                return trace_life.WindowInfo(
                    hwnd=0x1234,
                    title="LBA2",
                    left=0,
                    top=0,
                    right=800,
                    bottom=600,
                )

        class FakeWindowInput:
            def __init__(self) -> None:
                self.actions: list[tuple[str, int]] = []

            def send_enter(self, hwnd: int) -> None:
                self.actions.append(("enter", hwnd))

            def send_down(self, hwnd: int) -> None:
                self.actions.append(("down", hwnd))

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            capture = FakeWindowCapture()
            window_input = FakeWindowInput()
            try:
                with mock.patch.object(trace_life.time, "sleep") as mocked_sleep:
                    trace_life.drive_tavern_launch_startup(
                        writer,
                        4321,
                        capture=capture,
                        window_input=window_input,
                    )
            finally:
                writer.close()

            self.assertEqual(
                [
                    ("enter", 0x1234),
                    ("down", 0x1234),
                    ("down", 0x1234),
                    ("enter", 0x1234),
                    ("enter", 0x1234),
                ],
                window_input.actions,
            )
            self.assertEqual(
                [(4321, trace_life.TAVERN_STARTUP_WINDOW_TIMEOUT_SEC)] * 5,
                capture.wait_calls,
            )
            self.assertEqual(
                [
                    mock.call(trace_life.TAVERN_ADELINE_ENTER_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_POST_ADELINE_MENU_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MENU_SETTLE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC),
                ],
                mocked_sleep.call_args_list,
            )

            lines = read_jsonl_lines(writer.enriched_output_path)
            messages = [line["message"] for line in lines if line.get("kind") == "status" and "message" in line]
            self.assertIn("driving Tavern startup through Adeline and Load Game", messages)
            self.assertIn("sent Enter to continue past the Adeline splash", messages)
            self.assertIn("moved selection from Resume Game to New Game", messages)
            self.assertIn("moved selection from New Game to Load Game", messages)
            self.assertIn("sent Enter to open Load Game", messages)
            self.assertIn("sent Enter to load the sole staged save", messages)
            self.assertIn("waited for the sole staged save to settle before attaching fra probe", messages)

    def test_cleanup_tavern_launch_restores_canonical_save_folder(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            launch_dir = Path(temp_dir) / "LBA2"
            save_dir = launch_dir / "SAVE"
            save_dir.mkdir(parents=True)
            launch_path = launch_dir / "LBA2.EXE"
            launch_path.write_bytes(b"exe")
            (save_dir / "current.lba").write_bytes(b"current")
            staged_path = save_dir / "inside-tavern.LBA"
            staged_path.write_bytes(b"fixture")
            (save_dir / "autosave.lba").write_bytes(b"autosave")
            args = argparse.Namespace(staged_load_game_save_path=str(staged_path))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                trace_life.cleanup_tavern_launch(args, writer, launch_path)
            finally:
                writer.close()

            self.assertTrue((save_dir / "current.lba").exists())
            self.assertFalse(staged_path.exists())
            self.assertFalse((save_dir / "autosave.lba").exists())


class Scene11StartupAutomationTest(unittest.TestCase):
    def test_stage_scene11_load_game_save_uses_launch_save_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            launch_dir = Path(temp_dir) / "LBA2"
            save_dir = launch_dir / "SAVE"
            save_dir.mkdir(parents=True)
            launch_path = launch_dir / "LBA2.EXE"
            launch_path.write_bytes(b"exe")
            source_path = Path(temp_dir) / "explicit-scene11-save.LBA"
            source_path.write_bytes(b"scene11-save")
            destination_path = save_dir / "explicit-scene11-save.LBA"
            (save_dir / "current.lba").write_bytes(b"old-current-save")
            args = argparse.Namespace(launch_save=str(source_path))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                staged_source, staged_destination = trace_life.stage_scene11_load_game_save(args, writer, launch_path)
            finally:
                writer.close()

            self.assertEqual(source_path, staged_source)
            self.assertEqual(destination_path, staged_destination)
            self.assertEqual(b"scene11-save", destination_path.read_bytes())

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual("staged explicit-scene11-save.LBA into SAVE as the sole Load Game slot", lines[0]["message"])

    def test_drive_scene11_launch_startup_drives_load_game_single_slot_sequence(self) -> None:
        class FakeWindowCapture:
            def __init__(self) -> None:
                self.wait_calls: list[tuple[int, float]] = []

            def wait_for_window(self, pid: int, timeout_sec: float = 10.0) -> trace_life.WindowInfo:
                self.wait_calls.append((pid, timeout_sec))
                return trace_life.WindowInfo(
                    hwnd=0x1234,
                    title="LBA2",
                    left=0,
                    top=0,
                    right=800,
                    bottom=600,
                )

        class FakeWindowInput:
            def __init__(self) -> None:
                self.actions: list[tuple[str, int]] = []

            def send_enter(self, hwnd: int) -> None:
                self.actions.append(("enter", hwnd))

            def send_down(self, hwnd: int) -> None:
                self.actions.append(("down", hwnd))

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            capture = FakeWindowCapture()
            window_input = FakeWindowInput()
            try:
                with mock.patch.object(trace_life.time, "sleep") as mocked_sleep:
                    trace_life.drive_scene11_launch_startup(
                        writer,
                        4321,
                        capture=capture,
                        window_input=window_input,
                    )
            finally:
                writer.close()

            self.assertEqual(
                [
                    ("enter", 0x1234),
                    ("down", 0x1234),
                    ("down", 0x1234),
                    ("enter", 0x1234),
                    ("enter", 0x1234),
                ],
                window_input.actions,
            )
            self.assertEqual(
                [(4321, trace_life.SCENE11_STARTUP_WINDOW_TIMEOUT_SEC)] * 5,
                capture.wait_calls,
            )
            self.assertEqual(
                [
                    mock.call(trace_life.SCENE11_ADELINE_ENTER_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_POST_ADELINE_MENU_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MENU_SETTLE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_MAIN_MENU_MOVE_DELAY_SEC),
                    mock.call(trace_life.LOAD_GAME_SOLE_SAVE_SETTLE_DELAY_SEC),
                ],
                mocked_sleep.call_args_list,
            )

            lines = read_jsonl_lines(writer.enriched_output_path)
            messages = [line["message"] for line in lines if line.get("kind") == "status" and "message" in line]
            self.assertIn("driving Scene11 startup through Adeline and Load Game", messages)
            self.assertIn("sent Enter to continue past the Adeline splash", messages)
            self.assertIn("moved selection from Resume Game to New Game", messages)
            self.assertIn("moved selection from New Game to Load Game", messages)
            self.assertIn("sent Enter to open Load Game", messages)
            self.assertIn("waited for the Load Game menu to settle", messages)
            self.assertIn("sent Enter to load the sole staged save", messages)
            self.assertIn("waited for the sole staged save to settle before attaching fra probe", messages)


class TavernFinalizeStatusTest(unittest.TestCase):
    def test_tavern_finalize_writes_explicit_completed_status_after_verdict(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            args = argparse.Namespace(
                target_object=0,
                target_offset=4883,
            )
            controller = trace_life.TavernTraceController(args, writer, pid=30140)
            controller.matched_fingerprint = True
            controller.saw_076_fetch = True
            controller.saw_post_076_loop = True
            controller.post_076_outcome = "loop_reentry"
            controller.required_screenshots["fingerprint_match"] = "work/life_trace/fingerprint.png"
            controller.required_screenshots["opcode_076_fetch"] = "work/life_trace/opcode_076_fetch.png"

            fake_window = trace_life.WindowInfo(
                hwnd=0x1234,
                title="LBA2",
                left=0,
                top=0,
                right=800,
                bottom=600,
            )

            try:
                with mock.patch.object(
                    controller,
                    "_capture_window_file",
                    return_value=("work/life_trace/final_verdict.png", fake_window),
                ):
                    controller._finalize(
                        "tavern_trace_complete",
                        "captured Tavern proof through loop_reentry",
                        take_final_screenshot=True,
                    )
            finally:
                writer.close()

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual("verdict", lines[-2]["kind"])
            self.assertEqual("status", lines[-1]["kind"])
            self.assertEqual("completed", lines[-1]["phase"])
            self.assertEqual(trace_life.TRACE_COMPLETE_STATUS_MESSAGE, lines[-1]["message"])
            self.assertEqual(30140, lines[-1]["pid"])
            screenshot_lines = [line for line in lines if line["kind"] == "screenshot"]
            self.assertEqual(1, len(screenshot_lines))
            self.assertTrue(screenshot_lines[0]["screenshot_path"].endswith("final_verdict.png"))


class HelperCallsiteEnrichmentTest(unittest.TestCase):
    def test_writer_enriches_helper_callsite_events_from_callsite_map(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            callsite_path = Path(temp_dir) / "callsites.jsonl"
            callsite_path.write_text(
                '{"callee_name":"DoTest","caller_static_rel":"0x00020F50","within_function":"FUN_00420574","within_entry":"ram:00420574","call_instruction":"ram:00420f4b","call_index":0}\n',
                encoding="utf-8",
            )
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                callsite_artifact_path=callsite_path,
                callsite_index=trace_life.load_callsite_index(callsite_path),
            )
            try:
                writer.write_event(
                    trace_life.AgentHelperCallsiteEvent(
                        callee_name="DoTest",
                        caller_static_live="0x420f50",
                        caller_static_rel="0x20f50",
                        thread_id=9876,
                        object_index=12,
                        owner_kind="object",
                        ptr_life="0x4120000",
                        ptr_prg="0x41200f0",
                        ptr_prg_offset=38,
                        opcode=116,
                        opcode_hex="0x74",
                        trace_role="primary",
                    )
                )
            finally:
                writer.close()

            raw_line = read_jsonl_lines(writer.raw_output_path)[0]
            enriched_line = read_jsonl_lines(writer.enriched_output_path)[0]
            self.assertEqual("helper_callsite", raw_line["kind"])
            self.assertEqual("raw", raw_line["source_stream"])
            self.assertEqual("0x00020F50", raw_line["caller_static_rel"])
            self.assertNotIn("within_function", raw_line)
            self.assertEqual("helper_callsite", enriched_line["kind"])
            self.assertEqual("mapped", enriched_line["callsite_status"])
            self.assertEqual("FUN_00420574", enriched_line["within_function"])
            self.assertEqual("ram:00420574", enriched_line["within_entry"])
            self.assertEqual("ram:00420f4b", enriched_line["call_instruction"])
            self.assertEqual(0, enriched_line["call_index"])
            self.assertEqual("0x00020F50", enriched_line["caller_static_rel"])
            self.assertEqual(raw_line["event_id"], enriched_line["event_id"])
            self.assertEqual(raw_line["run_id"], enriched_line["run_id"])

    def test_writer_marks_unmapped_helper_callsite_events(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir), callsite_index={})
            try:
                writer.write_event(
                    trace_life.AgentHelperCallsiteEvent(
                        callee_name="DoFuncLife",
                        caller_static_live="0x421139",
                        caller_static_rel="0x00021139",
                        thread_id=9876,
                        object_index=12,
                        owner_kind="object",
                        ptr_life="0x4120000",
                        ptr_prg="0x41200f0",
                        ptr_prg_offset=38,
                        opcode=116,
                        opcode_hex="0x74",
                        trace_role="primary",
                    )
                )
            finally:
                writer.close()

            line = read_jsonl_lines(writer.enriched_output_path)[0]
            self.assertEqual("helper_callsite", line["kind"])
            self.assertEqual("unmapped", line["callsite_status"])
            self.assertEqual("0x00021139", line["caller_static_rel"])
            self.assertNotIn("within_function", line)

    def test_writer_creates_manifest_and_bundle_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                mode="scene11-pair",
                process_name="LBA2.EXE",
                launch_path=r"D:\games\LBA2.EXE",
                launch_save=r"D:\games\SAVE\scene11-pair.LBA",
                callsite_artifact_path=trace_life.DEFAULT_CALLSITES_JSONL,
                callsite_index={},
                requires_callsite_map=True,
                run_id="bundle-test",
            )
            try:
                event_id = writer.write_event(
                    trace_life.PersistedStatusEvent(
                        message="attached",
                        mode="scene11-pair",
                        pid=1234,
                        process_name="LBA2.EXE",
                    )
                )
            finally:
                writer.close()

            manifest = json.loads(writer.manifest_path.read_text(encoding="utf-8"))
            raw_line = read_jsonl_lines(writer.raw_output_path)[0]
            enriched_line = read_jsonl_lines(writer.enriched_output_path)[0]
            self.assertEqual("bundle-test", manifest["run_id"])
            self.assertEqual("raw.jsonl", manifest["artifacts"]["raw_jsonl"])
            self.assertEqual("enriched.jsonl", manifest["artifacts"]["enriched_jsonl"])
            self.assertEqual("screenshots", manifest["artifacts"]["screenshots_dir"])
            self.assertEqual("scene11-pair", manifest["mode"])
            self.assertEqual(1234, manifest["pid"])
            self.assertIsNotNone(manifest["finished_at_utc"])
            self.assertEqual(event_id, raw_line["event_id"])
            self.assertEqual(event_id, enriched_line["event_id"])
            self.assertEqual("raw", raw_line["source_stream"])
            self.assertEqual("enriched", enriched_line["source_stream"])

    def test_scene11_controller_fails_fast_on_unmapped_helper_callsite(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                callsite_index={},
                requires_callsite_map=True,
            )
            args = argparse.Namespace(
                target_object=12,
                target_opcode=0x74,
                target_offset=38,
                comparison_object=18,
                comparison_opcode=0x76,
                comparison_offset=84,
                timeout_sec=60.0,
            )
            controller = trace_life.Scene11PairController(args, writer, pid=1234)
            fake_window = trace_life.WindowInfo(
                hwnd=0x1234,
                title="LBA2",
                left=0,
                top=0,
                right=800,
                bottom=600,
            )

            try:
                with mock.patch.object(
                    controller,
                    "_capture_window_file",
                    return_value=("work/life_trace/runs/test/screenshots/final_verdict.png", fake_window),
                ):
                    controller.handle_event(
                        trace_life.AgentHelperCallsiteEvent(
                            callee_name="DoTest",
                            caller_static_live="0x420f50",
                            caller_static_rel="0x20f50",
                            thread_id=9876,
                            object_index=12,
                            owner_kind="object",
                            ptr_life="0x4120000",
                            ptr_prg="0x41200f0",
                            ptr_prg_offset=38,
                            opcode=116,
                            opcode_hex="0x74",
                            trace_role="primary",
                        )
                    )
            finally:
                writer.close()

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual("helper_callsite", lines[0]["kind"])
            self.assertEqual("unmapped", lines[0]["callsite_status"])
            self.assertEqual("verdict", lines[-2]["kind"])
            self.assertEqual("unmapped_callsite", lines[-2]["result"])
            self.assertIn("was not present in the configured static map", lines[-2]["reason"])
            self.assertEqual("status", lines[-1]["kind"])
            self.assertTrue(controller.terminal)
            self.assertEqual(1, controller.exit_code)


class SpawnedProcessTerminationTest(unittest.TestCase):
    def test_terminate_spawned_process_accepts_fra_terminate_when_process_exits(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with (
                    mock.patch.object(trace_life.runtime, "run_fra_json", return_value={"ok": True}) as mocked_run,
                    mock.patch.object(trace_life.runtime, "wait_for_process_exit", return_value=True) as mocked_wait,
                    mock.patch.object(trace_life.os, "kill") as mocked_kill,
                ):
                    trace_life.terminate_spawned_process(
                        writer,
                        ["fra"],
                        "target-1",
                        1234,
                    )
            finally:
                writer.close()

            mocked_run.assert_called_once()
            mocked_wait.assert_called_once_with(1234, trace_life.SPAWNED_PROCESS_TERMINATE_GRACE_SEC)
            mocked_kill.assert_not_called()

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual(["killed spawned process"], [line["message"] for line in lines])

    def test_terminate_spawned_process_falls_back_to_direct_kill_when_process_lingers(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with (
                    mock.patch.object(trace_life.runtime, "run_fra_json", return_value={"ok": True}),
                    mock.patch.object(trace_life.runtime, "wait_for_process_exit", side_effect=[False, True]) as mocked_wait,
                    mock.patch.object(trace_life.os, "kill") as mocked_kill,
                ):
                    trace_life.terminate_spawned_process(
                        writer,
                        ["fra"],
                        "target-1",
                        1234,
                    )
            finally:
                writer.close()

            mocked_wait.assert_has_calls(
                [
                    mock.call(1234, trace_life.SPAWNED_PROCESS_TERMINATE_GRACE_SEC),
                    mock.call(1234, trace_life.SPAWNED_PROCESS_TERMINATE_GRACE_SEC),
                ]
            )
            mocked_kill.assert_called_once_with(1234, signal.SIGTERM)

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual(
                [
                    "spawned process still alive after fra target terminate; forcing direct kill",
                    "force-killed spawned process",
                ],
                [line["message"] for line in lines],
            )


class ProcessExistsPidTest(unittest.TestCase):
    def test_process_exists_pid_returns_false_when_exit_code_is_not_still_active(self) -> None:
        fake_kernel32 = mock.Mock()
        fake_kernel32.OpenProcess.return_value = 123
        fake_kernel32.CloseHandle.return_value = True

        def fake_get_exit_code(handle, pointer) -> bool:
            pointer._obj.value = 0
            return True

        fake_kernel32.GetExitCodeProcess.side_effect = fake_get_exit_code

        with mock.patch.object(trace_life.ctypes, "windll", mock.Mock(kernel32=fake_kernel32)):
            self.assertFalse(trace_life.process_exists_pid(1234))

    def test_process_exists_pid_returns_true_when_exit_code_is_still_active(self) -> None:
        fake_kernel32 = mock.Mock()
        fake_kernel32.OpenProcess.return_value = 123
        fake_kernel32.CloseHandle.return_value = True

        def fake_get_exit_code(handle, pointer) -> bool:
            pointer._obj.value = 259
            return True

        fake_kernel32.GetExitCodeProcess.side_effect = fake_get_exit_code

        with mock.patch.object(trace_life.ctypes, "windll", mock.Mock(kernel32=fake_kernel32)):
            self.assertTrue(trace_life.process_exists_pid(1234))


if __name__ == "__main__":
    unittest.main()
