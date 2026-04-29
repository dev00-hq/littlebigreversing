from __future__ import annotations

import argparse
import contextlib
import io
import json
import re
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import msgspec

sys.path.insert(0, str(Path(__file__).resolve().parent / "life_trace"))

import capture_sendell_ball
import life_trace_debugger
import life_trace_runtime as runtime
import scene11_compare
import save_profiles
import trace_life


RUN_ID = "life-trace-20260405-011732"

STATUS_LINE = """{"event_id": "evt-0001", "frida_lib": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\frida\\\\x86_64", "frida_module": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages\\\\frida\\\\__init__.py", "frida_repo_root": "D:\\\\repos\\\\reverse\\\\frida", "frida_root": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida", "frida_site_packages": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages", "kind": "status", "launch_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\_innoextract_full\\\\Speedrun\\\\Windows\\\\LBA2_cdrom\\\\LBA2\\\\LBA2.EXE", "message": "attached", "mode": "tavern-trace", "output_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\life_trace\\\\runs\\\\life-trace-20260405-011732", "phase": "attached", "pid": 25148, "process_name": "LBA2.EXE", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "timestamp_utc": "2026-04-05T05:17:33Z"}"""
TARGET_VALIDATION_LINE = """{"event_id": "evt-0005", "fingerprint_hex_actual": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_hex_expected": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_start_offset": 40, "kind": "target_validation", "matches_fingerprint": true, "object_index": 0, "owner_kind": "hero", "ptr_life": "0x33a21fb", "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
BRANCH_TRACE_LINE = """{"branch_kind": "break_jump", "computed_target_offset": 103, "event_id": "evt-0014", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "kind": "branch_trace", "object_index": 0, "operand_offset": 103, "ptr_prg_offset_before": 4805, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
WINDOW_TRACE_LINE = """{"current_object": "0x49a19c", "event_id": "evt-0015", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "working_type_answer": 4, "working_value": 0}"""
MINIMAL_TAVERN_WINDOW_TRACE_LINE = """{"byte_at_ptr_prg": 118, "byte_at_ptr_prg_hex": "0x76", "current_object": "0x49a19c", "event_id": "evt-0015", "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "run_id": "life-trace-20260405-011732", "source_stream": "enriched", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
SCREENSHOT_LINE = """{"capture_status": "captured", "event_id": "evt-0015", "kind": "screenshot", "poi": "opcode_076_fetch", "run_id": "life-trace-20260405-011732", "screenshot_path": "work/life_trace/runs/life-trace-20260405-011732/screenshots/evt-0015__opcode_076_fetch__obj0__off4883.png", "source_stream": "enriched", "source_window_title": "LBA2", "timestamp_utc": "2026-04-05T05:17:42Z"}"""
MEMORY_SNAPSHOT_LINE = """{"address": "0x0049BCCE", "current_object": "0x0049BAE0", "debugger": "cdb-agent", "event_id": "evt-0020", "kind": "memory_snapshot", "object_index": 12, "relative_offset": 38, "relative_to": "ptr_life", "run_id": "life-trace-20260405-011732", "snapshot_name": "primary_target_window", "source_stream": "enriched", "timestamp_utc": "2026-04-05T05:17:42Z", "window": {"bytes_hex": "00 01 17 42 00 75 2D 00 74 17", "cursor_index": 8, "start": "0x0049BCC6"}}"""
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
            trace_life.PersistedMemorySnapshotEvent: MEMORY_SNAPSHOT_LINE,
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


class LifeTraceFridaHookShapeTest(unittest.TestCase):
    def test_internal_dolife_loop_hooks_use_function_probe_form(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]
        search_roots = [repo_root / "tools" / "life_trace"]
        banned_patterns = [
            re.compile(r"Interceptor\.attach\(\s*absolute\(offsets\.doLifeLoop\)\s*,\s*\{", re.MULTILINE),
            re.compile(r"Interceptor\.attach\(\s*ADDR\.doLifeLoop\s*,\s*\{", re.MULTILINE),
        ]
        violations: list[str] = []

        for search_root in search_roots:
            for path in search_root.rglob("*"):
                if path.suffix not in {".js", ".py"}:
                    continue
                text = path.read_text(encoding="utf-8")
                if any(pattern.search(text) for pattern in banned_patterns):
                    violations.append(str(path.relative_to(repo_root)))

        self.assertEqual(
            [],
            violations,
            "internal DoLifeLoop instruction hooks must use Interceptor.attach(addr, function () { ... })",
        )


class LifeTraceRuntimeLaunchTest(unittest.TestCase):
    def test_build_owned_launch_argv_uses_direct_save_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            launch_path = temp_root / "LBA2.EXE"
            save_path = temp_root / "0008-sendell-ball.LBA"
            launch_path.write_bytes(b"")
            save_path.write_bytes(b"")

            argv = runtime.build_owned_launch_argv(launch_path, str(save_path))

        self.assertEqual([str(launch_path), str(save_path)], argv)

    def test_build_owned_launch_argv_without_save_keeps_bare_exe(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            launch_path = temp_root / "LBA2.EXE"
            launch_path.write_bytes(b"")

            argv = runtime.build_owned_launch_argv(launch_path, None)

        self.assertEqual([str(launch_path)], argv)

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
        self.assertIn("Bounded runtime evidence probe for the original Windows LBA2 life interpreter.", result.stdout)

    def test_load_agent_source_assembles_scene_fragments(self) -> None:
        args = trace_life.parse_args(["--mode", "tavern-trace"])
        script = trace_life.runtime.load_agent_source(args)

        self.assertNotIn("__TRACE_", script)
        self.assertIn('registerScene("basic"', script)
        self.assertIn('registerScene("tavern-trace"', script)
        self.assertIn('registerScene("scene11-live-pair"', script)
        self.assertNotIn('registerScene("scene11-pair"', script)
        self.assertIn("const scene = createScene(config.mode);", script)
        self.assertIn('"mode":"tavern-trace"', script)
        self.assertIn('"helperCaptureEnabled":false', script)

    def test_load_agent_source_fails_when_a_required_fragment_is_missing(self) -> None:
        args = trace_life.parse_args(["--mode", "tavern-trace"])
        missing_path = (Path(trace_life.runtime.__file__).with_name("agent") / "scene_tavern.js").resolve()
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

    def test_parse_args_defaults_scene11_to_debugger_snapshot_lane(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-pair", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_offset, args.target_offset)
        self.assertEqual(str(trace_life.DEFAULT_SAVE_SOURCE_ROOT / "02-voisin.LBA"), args.launch_save)
        self.assertIsNone(args.fra_repo_root)
        self.assertIsNone(args.frida_repo_root)
        self.assertEqual(str(trace_life.DEFAULT_CALLSITES_JSONL), args.callsites_jsonl)
        self.assertTrue(args.requires_callsite_map is False)
        self.assertTrue(args.helper_capture_enabled is False)

    def test_parse_args_defaults_scene11_live_pair_to_frida_lane(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-live-pair", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.target_offset, args.target_offset)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.comparison_object, args.comparison_object)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.comparison_opcode, args.comparison_opcode)
        self.assertEqual(trace_life.SCENE11_LIVE_PAIR_PRESET.comparison_offset, args.comparison_offset)
        self.assertEqual(str(trace_life.DEFAULT_SAVE_SOURCE_ROOT / "02-voisin.LBA"), args.launch_save)
        self.assertEqual(str(trace_life.DEFAULT_FRIDA_REPO_ROOT), args.frida_repo_root)
        self.assertIsNone(args.fra_repo_root)
        self.assertTrue(args.requires_callsite_map is False)
        self.assertTrue(args.helper_capture_enabled is False)

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
            "--mode scene11-pair rejects --frida-repo-root; its canonical backend is debugger-owned",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_fra_root_for_scene11(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(
                    ["--mode", "scene11-pair", "--fra-repo-root", r"D:\repos\frida-agent-cli"]
                )
        self.assertIn(
            "--mode scene11-pair rejects --fra-repo-root; its canonical backend is debugger-owned",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_fra_root_for_scene11_live_pair(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(
                    ["--mode", "scene11-live-pair", "--fra-repo-root", r"D:\repos\frida-agent-cli"]
                )
        self.assertIn(
            "--mode scene11-live-pair rejects --fra-repo-root; use --frida-repo-root",
            stderr.getvalue(),
        )

    def test_parse_args_rejects_fra_root_for_basic(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit):
            with contextlib.redirect_stderr(stderr):
                trace_life.parse_args(["--fra-repo-root", r"D:\repos\frida-agent-cli"])
        self.assertIn("--fra-repo-root requires --mode tavern-trace", stderr.getvalue())

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
    def test_resolve_direct_launch_save_uses_explicit_launch_save(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = Path(temp_dir) / "inside-tavern.LBA"
            source_path.write_bytes(b"inside-tavern-save")
            args = argparse.Namespace(launch_save=str(source_path))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                resolved = trace_life.resolve_direct_launch_save(
                    args,
                    writer,
                    lane_name="tavern-trace",
                    default_source=source_path,
                )
            finally:
                writer.close()

            self.assertEqual(source_path.resolve(), resolved)
            self.assertEqual(str(source_path.resolve()), args.launch_save)

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual("resolved direct launch save inside-tavern.LBA", lines[0]["message"])

    def test_resolve_direct_launch_save_missing_fixture_is_an_explicit_blocker(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            args = argparse.Namespace(launch_save=str(Path(temp_dir) / "missing-tavern-save.LBA"))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with self.assertRaises(RuntimeError) as raised:
                    trace_life.resolve_direct_launch_save(
                        args,
                        writer,
                        lane_name="tavern-trace",
                        default_source=Path(temp_dir) / "inside-tavern.LBA",
                    )
            finally:
                writer.close()

            self.assertIn("tavern-trace direct launch save is missing", str(raised.exception))
            self.assertIn("canonical launch path", str(raised.exception))

    def test_drive_tavern_launch_startup_uses_direct_save_launch(self) -> None:
        class FakeWindowCapture:
            def __init__(self) -> None:
                self.wait_calls: list[tuple[int, float]] = []
                self.signature_calls: list[tuple[int, float]] = []
                self.signature_index = 0

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

            def capture_frame_signature(self, pid: int, *, timeout_sec: float = 10.0, pixel_stride: int = 32, luma_threshold: int = 12):
                del pixel_stride, luma_threshold
                self.signature_calls.append((pid, timeout_sec))
                signatures = [
                    trace_life.WindowFrameSignature(checksum=111, mean_luma=0, lit_samples=0, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=333, mean_luma=220, lit_samples=240, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=333, mean_luma=220, lit_samples=240, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=444, mean_luma=80, lit_samples=192, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=444, mean_luma=80, lit_samples=192, sample_count=256),
                ]
                signature = signatures[min(self.signature_index, len(signatures) - 1)]
                self.signature_index += 1
                return trace_life.WindowInfo(
                    hwnd=0x1234,
                    title="LBA2",
                    left=0,
                    top=0,
                    right=800,
                    bottom=600,
                ), signature

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
                monotonic_values = iter(value * 0.1 for value in range(256))
                with (
                    mock.patch.object(trace_life.time, "sleep") as mocked_sleep,
                    mock.patch.object(trace_life.time, "monotonic", side_effect=lambda: next(monotonic_values)),
                ):
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
                ],
                window_input.actions,
            )
            self.assertEqual([(4321, trace_life.TAVERN_STARTUP_WINDOW_TIMEOUT_SEC)] * 2, capture.wait_calls)
            self.assertEqual(
                [
                    mock.call(trace_life.DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC),
                ],
                mocked_sleep.call_args_list[-1:],
            )
            splash_polls = mocked_sleep.call_args_list[:-1]
            self.assertGreaterEqual(len(splash_polls), 2)
            self.assertTrue(all(call == mock.call(0.1) for call in splash_polls))

            lines = read_jsonl_lines(writer.enriched_output_path)
            messages = [line["message"] for line in lines if line.get("kind") == "status" and "message" in line]
            self.assertIn("driving Tavern startup through direct save launch", messages)
            self.assertIn("sent Enter to continue past the Adeline splash", messages)
            self.assertIn("waited for the direct-launch save to settle before attaching fra probe", messages)


class Scene11StartupAutomationTest(unittest.TestCase):
    def test_resolve_direct_launch_save_uses_scene11_launch_override(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source_path = Path(temp_dir) / "explicit-scene11-save.LBA"
            source_path.write_bytes(b"scene11-save")
            args = argparse.Namespace(launch_save=str(source_path))

            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                resolved = trace_life.resolve_direct_launch_save(
                    args,
                    writer,
                    lane_name="scene11-pair",
                    default_source=source_path,
                )
            finally:
                writer.close()

            self.assertEqual(source_path.resolve(), resolved)
            self.assertEqual(str(source_path.resolve()), args.launch_save)

            lines = read_jsonl_lines(writer.enriched_output_path)
            self.assertEqual("resolved direct launch save explicit-scene11-save.LBA", lines[0]["message"])

    def test_drive_scene11_launch_startup_uses_direct_save_launch(self) -> None:
        class FakeWindowCapture:
            def __init__(self) -> None:
                self.wait_calls: list[tuple[int, float]] = []
                self.signature_calls: list[tuple[int, float]] = []
                self.signature_index = 0

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

            def capture_frame_signature(self, pid: int, *, timeout_sec: float = 10.0, pixel_stride: int = 32, luma_threshold: int = 12):
                del pixel_stride, luma_threshold
                self.signature_calls.append((pid, timeout_sec))
                signatures = [
                    trace_life.WindowFrameSignature(checksum=111, mean_luma=0, lit_samples=0, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=222, mean_luma=32, lit_samples=128, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=333, mean_luma=220, lit_samples=240, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=333, mean_luma=220, lit_samples=240, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=444, mean_luma=80, lit_samples=192, sample_count=256),
                    trace_life.WindowFrameSignature(checksum=444, mean_luma=80, lit_samples=192, sample_count=256),
                ]
                signature = signatures[min(self.signature_index, len(signatures) - 1)]
                self.signature_index += 1
                return trace_life.WindowInfo(
                    hwnd=0x1234,
                    title="LBA2",
                    left=0,
                    top=0,
                    right=800,
                    bottom=600,
                ), signature

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
                monotonic_values = iter(value * 0.1 for value in range(256))
                with (
                    mock.patch.object(trace_life.time, "sleep") as mocked_sleep,
                    mock.patch.object(trace_life.time, "monotonic", side_effect=lambda: next(monotonic_values)),
                ):
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
                ],
                window_input.actions,
            )
            self.assertEqual(
                [(4321, trace_life.SCENE11_STARTUP_WINDOW_TIMEOUT_SEC)] * 2,
                capture.wait_calls,
            )
            self.assertEqual(
                [
                    mock.call(trace_life.DIRECT_SAVE_POST_SPLASH_SETTLE_DELAY_SEC),
                ],
                mocked_sleep.call_args_list[-1:],
            )
            splash_polls = mocked_sleep.call_args_list[:-1]
            self.assertGreaterEqual(len(splash_polls), 2)
            self.assertTrue(all(call == mock.call(0.1) for call in splash_polls))

            lines = read_jsonl_lines(writer.enriched_output_path)
            messages = [line["message"] for line in lines if line.get("kind") == "status" and "message" in line]
            self.assertIn("driving Scene11 startup through direct save launch", messages)
            self.assertIn("sent Enter to continue past the Adeline splash", messages)
            self.assertIn("waited for the direct-launch save to settle before capturing the debugger snapshot lane", messages)


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

    def test_writer_register_artifact_updates_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir), run_id="bundle-test")
            try:
                writer.register_artifact("scene11_summary", "scene11_summary.json")
            finally:
                writer.close()

            manifest = json.loads(writer.manifest_path.read_text(encoding="utf-8"))
            self.assertEqual("scene11_summary.json", manifest["artifacts"]["scene11_summary"])

    def test_collect_scene11_debugger_snapshot_records_expected_target_bytes(self) -> None:
        object_base = 0x0049A19C
        object_stride = 0x21B
        ptr_life_offset = 0x1EE
        offset_life_offset = 0x1F2
        primary_object = 12
        comparison_object = 18
        primary_ptr_life = 0x00412000
        comparison_ptr_life = 0x00413000

        class FakeSnapshotReader:
            def read_scalars(self, *, dword_addresses: tuple[int, ...], word_addresses: tuple[int, ...]):
                del dword_addresses, word_addresses
                return (
                    {
                        0x004976D0: 0x00420000,
                        object_base + (primary_object * object_stride) + ptr_life_offset: primary_ptr_life,
                        object_base + (comparison_object * object_stride) + ptr_life_offset: comparison_ptr_life,
                    },
                    {
                        object_base + (primary_object * object_stride) + offset_life_offset: 7,
                        object_base + (comparison_object * object_stride) + offset_life_offset: 11,
                    },
                )

            def read_bytes(self, address: int, count: int) -> bytes:
                assert count == 17
                if address == primary_ptr_life + 30:
                    return bytes([0x00, 0x01, 0x17, 0x42, 0x00, 0x75, 0x2D, 0x00, 0x74, 0x17, 0x01, 0x0D, 0x00, 0x02, 0x03, 0x04, 0x05])
                if address == comparison_ptr_life + 76:
                    return bytes([0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x76, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
                raise AssertionError(f"unexpected address: 0x{address:08X}")

        snapshot = trace_life.collect_scene11_debugger_snapshot(FakeSnapshotReader())

        self.assertEqual(0x00420000, snapshot.ptr_prg)
        self.assertEqual(0x74, snapshot.primary.target_byte)
        self.assertEqual(0x76, snapshot.comparison.target_byte)
        self.assertEqual("0x0041201E", snapshot.primary.target_window.start)
        self.assertEqual("0x0041304C", snapshot.comparison.target_window.start)
        self.assertEqual("00 01 17 42 00 75 2D 00 74 17 01 0D 00 02 03 04 05", snapshot.primary.target_window.bytes_hex)
        self.assertEqual(
            (
                "scene11_snapshot_complete",
                "captured debugger-owned Scene11 snapshot evidence for object 12 LM_DEFAULT and object 18 LM_END_SWITCH",
            ),
            trace_life.determine_scene11_snapshot_verdict(snapshot),
        )

    def test_scene11_snapshot_verdict_fails_when_ptr_life_is_missing(self) -> None:
        object_base = 0x0049A19C
        object_stride = 0x21B
        ptr_life_offset = 0x1EE
        offset_life_offset = 0x1F2

        class FakeSnapshotReader:
            def read_scalars(self, *, dword_addresses: tuple[int, ...], word_addresses: tuple[int, ...]):
                del dword_addresses, word_addresses
                return (
                    {
                        0x004976D0: 0x00000000,
                        object_base + (12 * object_stride) + ptr_life_offset: 0x00000000,
                        object_base + (18 * object_stride) + ptr_life_offset: 0x00413000,
                    },
                    {
                        object_base + (12 * object_stride) + offset_life_offset: 0,
                        object_base + (18 * object_stride) + offset_life_offset: 0,
                    },
                )

            def read_bytes(self, address: int, count: int) -> bytes:
                del count
                if address == 0x0041304C:
                    return bytes([0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x76, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])
                raise AssertionError(f"unexpected address: 0x{address:08X}")

        snapshot = trace_life.collect_scene11_debugger_snapshot(FakeSnapshotReader())
        self.assertEqual(
            (
                "scene11_primary_ptr_life_missing",
                "object 12 PtrLife was null after the Scene11 load snapshot",
            ),
            trace_life.determine_scene11_snapshot_verdict(snapshot),
        )

    def test_discover_scene11_runtime_candidates_finds_live_opcode_mismatch(self) -> None:
        object_base = 0x0049A19C
        object_stride = 0x21B
        ptr_life_offset = 0x1EE
        offset_life_offset = 0x1F2
        object_two_ptr_life = 0x00E823A1

        class FakeSnapshotReader:
            def read_scalars(self, *, dword_addresses: tuple[int, ...], word_addresses: tuple[int, ...]):
                dwords = {address: 0 for address in dword_addresses}
                words = {address: 0 for address in word_addresses}
                dwords[object_base + (2 * object_stride) + ptr_life_offset] = object_two_ptr_life
                words[object_base + (2 * object_stride) + offset_life_offset] = 33

                blob_start = object_two_ptr_life
                blob = bytearray(160)
                blob[96] = 0x74
                blob[97:104] = bytes([0x17, 0x43, 0x00, 0x75, 0x67, 0x00, 0x76])
                blob[103] = 0x76
                for address in dword_addresses:
                    if blob_start <= address < blob_start + len(blob):
                        offset = address - blob_start
                        chunk = blob[offset : offset + 4]
                        dwords[address] = int.from_bytes(chunk.ljust(4, b"\x00"), "little")
                return dwords, words

            def read_bytes(self, address: int, count: int) -> bytes:
                raise AssertionError(f"unexpected byte read: 0x{address:08X} count={count}")

        candidates = trace_life.discover_scene11_runtime_candidates(FakeSnapshotReader())
        self.assertEqual([(2, 0x74, 96), (2, 0x76, 103)], [(c.object_index, c.opcode, c.opcode_offset) for c in candidates])
        mismatch = trace_life.summarize_scene11_runtime_mismatch(
            trace_life.Scene11DebuggerSnapshot(
                ptr_prg=0,
                primary=trace_life.Scene11ObjectSnapshot(
                    spec=trace_life.PRIMARY_SNAPSHOT,
                    current_object=object_base + (12 * object_stride),
                    ptr_life_field=object_base + (12 * object_stride) + ptr_life_offset,
                    ptr_life=0,
                    offset_life_field=object_base + (12 * object_stride) + offset_life_offset,
                    offset_life=0,
                    target_address=None,
                    target_window=trace_life.PointerWindow(
                        start="0x00000000",
                        cursor_index=8,
                        bytes_hex=None,
                        error="PtrLife for object 12 was null",
                    ),
                    target_byte=None,
                ),
                comparison=trace_life.Scene11ObjectSnapshot(
                    spec=trace_life.COMPARISON_SNAPSHOT,
                    current_object=object_base + (18 * object_stride),
                    ptr_life_field=object_base + (18 * object_stride) + ptr_life_offset,
                    ptr_life=0,
                    offset_life_field=object_base + (18 * object_stride) + offset_life_offset,
                    offset_life=0,
                    target_address=None,
                    target_window=trace_life.PointerWindow(
                        start="0x00000000",
                        cursor_index=8,
                        bytes_hex=None,
                        error="PtrLife for object 18 was null",
                    ),
                    target_byte=None,
                ),
            ),
            candidates,
        )
        self.assertEqual(
            (
                "scene11_static_runtime_mismatch",
                "canonical object 12 PtrLife was null; canonical object 18 PtrLife was null; live object 2 exposed LM_DEFAULT at offset 96; live object 2 exposed LM_END_SWITCH at offset 103",
            ),
            mismatch,
        )

    def test_build_scene11_run_summary_records_runtime_pair_owner(self) -> None:
        snapshot = trace_life.Scene11DebuggerSnapshot(
            ptr_prg=0x00420000,
            primary=trace_life.Scene11ObjectSnapshot(
                spec=trace_life.PRIMARY_SNAPSHOT,
                current_object=0x0049BAE0,
                ptr_life_field=0x0049BCCE,
                ptr_life=0,
                offset_life_field=0x0049BCD2,
                offset_life=0,
                target_address=None,
                target_window=trace_life.PointerWindow(
                    start="0x00000000",
                    cursor_index=8,
                    bytes_hex=None,
                    error="PtrLife for object 12 was null",
                ),
                target_byte=None,
            ),
            comparison=trace_life.Scene11ObjectSnapshot(
                spec=trace_life.COMPARISON_SNAPSHOT,
                current_object=0x0049C784,
                ptr_life_field=0x0049C972,
                ptr_life=0,
                offset_life_field=0x0049C976,
                offset_life=0,
                target_address=None,
                target_window=trace_life.PointerWindow(
                    start="0x00000000",
                    cursor_index=8,
                    bytes_hex=None,
                    error="PtrLife for object 18 was null",
                ),
                target_byte=None,
            ),
        )
        candidates = (
            trace_life.Scene11RuntimeCandidate(
                object_index=2,
                ptr_life=0x00E823A1,
                offset_life=33,
                opcode=0x74,
                opcode_offset=96,
                target_window=trace_life.PointerWindow(
                    start="0x00E823F9",
                    cursor_index=8,
                    bytes_hex="00 00 00 00 00 00 00 00 74 17",
                ),
            ),
            trace_life.Scene11RuntimeCandidate(
                object_index=2,
                ptr_life=0x00E823A1,
                offset_life=33,
                opcode=0x76,
                opcode_offset=103,
                target_window=trace_life.PointerWindow(
                    start="0x00E82400",
                    cursor_index=8,
                    bytes_hex="00 00 00 00 00 00 00 00 76 37",
                ),
            ),
        )
        summary = trace_life.build_scene11_run_summary(
            run_id="life-trace-test",
            mode="scene11-pair",
            launch_save=r"D:\repos\reverse\littlebigreversing\work\saves\02-voisin.LBA",
            bundle_root=Path(r"D:\repos\reverse\littlebigreversing\work\life_trace\runs\life-trace-test"),
            snapshot=snapshot,
            candidates=candidates,
            verdict_result="scene11_static_runtime_mismatch",
            verdict_reason="canonical object 12 PtrLife was null",
        )

        self.assertEqual("scene11-run-summary-v1", summary.payload["schema_version"])
        self.assertEqual(2, summary.payload["runtime_pair_owner"])
        self.assertTrue(summary.payload["global_ptr_prg_nonzero"])
        self.assertEqual("ptr_life_missing", summary.payload["canonical_objects"]["primary"]["status"])

    def test_scene11_comparison_report_redefines_runtime_contract_for_two_distinct_object_2_saves(self) -> None:
        summary_one = trace_life.Scene11RunSummary(
            payload={
                "schema_version": "scene11-run-summary-v1",
                "run_id": "run-1",
                "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\02-voisin.LBA",
                "global_ptr_prg": "0x00420000",
                "global_ptr_prg_nonzero": True,
                "canonical_objects": {
                    "primary": {"status": "ptr_life_missing"},
                    "comparison": {"status": "ptr_life_missing"},
                },
                "runtime_pair_owner": 2,
                "verdict": {"result": "scene11_static_runtime_mismatch", "reason": "mismatch"},
            }
        )
        summary_two = trace_life.Scene11RunSummary(
            payload={
                "schema_version": "scene11-run-summary-v1",
                "run_id": "run-2",
                "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\neighbor-house.LBA",
                "global_ptr_prg": "0x00421000",
                "global_ptr_prg_nonzero": True,
                "canonical_objects": {
                    "primary": {"status": "ptr_life_missing"},
                    "comparison": {"status": "ptr_life_missing"},
                },
                "runtime_pair_owner": 2,
                "verdict": {"result": "scene11_static_runtime_mismatch", "reason": "mismatch"},
            }
        )

        report = trace_life.build_scene11_comparison_report((summary_one, summary_two))
        self.assertEqual("redefine_runtime_contract", report.payload["decision"])

    def test_scene11_comparison_report_preserves_static_contract_when_canonical_pair_exists(self) -> None:
        summary_one = trace_life.Scene11RunSummary(
            payload={
                "schema_version": "scene11-run-summary-v1",
                "run_id": "run-1",
                "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\02-voisin.LBA",
                "global_ptr_prg": "0x00420000",
                "global_ptr_prg_nonzero": True,
                "canonical_objects": {
                    "primary": {"status": "opcode_match"},
                    "comparison": {"status": "opcode_match"},
                },
                "runtime_pair_owner": None,
                "verdict": {"result": "scene11_snapshot_complete", "reason": "complete"},
            }
        )
        summary_two = trace_life.Scene11RunSummary(
            payload={
                "schema_version": "scene11-run-summary-v1",
                "run_id": "run-2",
                "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\neighbor-house.LBA",
                "global_ptr_prg": "0x00421000",
                "global_ptr_prg_nonzero": True,
                "canonical_objects": {
                    "primary": {"status": "ptr_life_missing"},
                    "comparison": {"status": "ptr_life_missing"},
                },
                "runtime_pair_owner": 2,
                "verdict": {"result": "scene11_static_runtime_mismatch", "reason": "mismatch"},
            }
        )

        report = trace_life.build_scene11_comparison_report((summary_one, summary_two))
        self.assertEqual("preserve_static_contract", report.payload["decision"])

    def test_scene11_compare_cli_writes_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            first_bundle = temp_root / "run-1"
            second_bundle = temp_root / "run-2"
            first_bundle.mkdir()
            second_bundle.mkdir()
            (first_bundle / "scene11_summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": "scene11-run-summary-v1",
                        "run_id": "run-1",
                        "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\02-voisin.LBA",
                        "global_ptr_prg": "0x00420000",
                        "global_ptr_prg_nonzero": True,
                        "canonical_objects": {
                            "primary": {"status": "ptr_life_missing"},
                            "comparison": {"status": "ptr_life_missing"},
                        },
                        "runtime_pair_owner": 2,
                        "verdict": {"result": "scene11_static_runtime_mismatch", "reason": "mismatch"},
                    }
                ),
                encoding="utf-8",
            )
            (second_bundle / "scene11_summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": "scene11-run-summary-v1",
                        "run_id": "run-2",
                        "launch_save": r"D:\repos\reverse\littlebigreversing\work\saves\neighbor-house.LBA",
                        "global_ptr_prg": "0x00421000",
                        "global_ptr_prg_nonzero": True,
                        "canonical_objects": {
                            "primary": {"status": "ptr_life_missing"},
                            "comparison": {"status": "ptr_life_missing"},
                        },
                        "runtime_pair_owner": 2,
                        "verdict": {"result": "scene11_static_runtime_mismatch", "reason": "mismatch"},
                    }
                ),
                encoding="utf-8",
            )
            output_path = temp_root / "comparison.json"

            exit_code = scene11_compare.main(
                [str(first_bundle), str(second_bundle), "--output", str(output_path)]
            )

            report = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(0, exit_code)
            self.assertEqual("scene11-comparison-report-v1", report["schema_version"])
            self.assertEqual("redefine_runtime_contract", report["decision"])

    @staticmethod
    def _sendell_checkpoint(
        checkpoint_name: str,
        *,
        screenshot_path: str,
        ptr_prg_value_u32: int,
        type_answer_u32: int,
        value_u32: int,
        ptr_prg_window_bytes_hex: str | None,
        magic_level_u8: int = 0,
        magic_point_u8: int = 0,
        sendell_inventory_value_s16: int = 0,
        inventory_model_id_s16: int = -1,
        current_dial_s32: int = 0,
        source_window_title: str = "LBA2",
    ) -> dict[str, object]:
        return {
            "checkpoint_name": checkpoint_name,
            "screenshot_path": screenshot_path,
            "source_window_title": source_window_title,
            "ptr_prg_value_hex": f"0x{ptr_prg_value_u32:08X}",
            "ptr_prg_value_u32": ptr_prg_value_u32,
            "type_answer_u32": type_answer_u32,
            "value_u32": value_u32,
            "ptr_prg_window": {
                "start": f"0x{ptr_prg_value_u32:08X}",
                "cursor_index": 0,
                "bytes_hex": ptr_prg_window_bytes_hex,
                "error": None,
            },
            "direct_state": {
                "magic_level_u8": magic_level_u8,
                "magic_point_u8": magic_point_u8,
                "sendell_inventory_value_s16": sendell_inventory_value_s16,
                "inventory_model_id_s16": inventory_model_id_s16,
            },
            "transient_dialog_state": {
                "current_dial_s32": current_dial_s32,
            },
            "event_ids": {
                "screenshot": "evt-0001",
                "ptr_prg": "evt-0002",
                "type_answer": "evt-0003",
                "value": "evt-0004",
                "current_dial": "evt-0005",
                "ptr_prg_window": "evt-0006",
            },
        }

    def test_build_sendell_run_summary_records_story_state_transition(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                mode="sendell-ball-room",
                process_name="LBA2.EXE",
                launch_save=r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA",
                run_id="sendell-summary-test",
            )
            try:
                checkpoint_order = [
                    "loaded_pre_cast",
                    "after_f_cast",
                    "dialog_1",
                    "dialog_2",
                    "post_dialog_room",
                ]
                checkpoint_captures = {
                    "loaded_pre_cast": self._sendell_checkpoint(
                        "loaded_pre_cast",
                        screenshot_path="screenshots/loaded_pre_cast.png",
                        ptr_prg_value_u32=0x004976D0,
                        type_answer_u32=0,
                        value_u32=0,
                        ptr_prg_window_bytes_hex="10 20 30 40",
                        magic_level_u8=2,
                        magic_point_u8=40,
                        sendell_inventory_value_s16=0,
                        inventory_model_id_s16=-1,
                        current_dial_s32=3,
                    ),
                    "after_f_cast": self._sendell_checkpoint(
                        "after_f_cast",
                        screenshot_path="screenshots/after_f_cast.png",
                        ptr_prg_value_u32=0x004976E0,
                        type_answer_u32=0,
                        value_u32=0,
                        ptr_prg_window_bytes_hex="11 22 33 44",
                        magic_level_u8=3,
                        magic_point_u8=60,
                        sendell_inventory_value_s16=1,
                        inventory_model_id_s16=0,
                        current_dial_s32=3,
                    ),
                    "dialog_1": self._sendell_checkpoint(
                        "dialog_1",
                        screenshot_path="screenshots/dialog_1.png",
                        ptr_prg_value_u32=0x004976F0,
                        type_answer_u32=4,
                        value_u32=11,
                        ptr_prg_window_bytes_hex="AA BB CC DD",
                        magic_level_u8=3,
                        magic_point_u8=60,
                        sendell_inventory_value_s16=1,
                        inventory_model_id_s16=0,
                        current_dial_s32=3,
                    ),
                    "dialog_2": self._sendell_checkpoint(
                        "dialog_2",
                        screenshot_path="screenshots/dialog_2.png",
                        ptr_prg_value_u32=0x00497700,
                        type_answer_u32=4,
                        value_u32=11,
                        ptr_prg_window_bytes_hex="EE FF 00 11",
                        magic_level_u8=3,
                        magic_point_u8=60,
                        sendell_inventory_value_s16=1,
                        inventory_model_id_s16=0,
                        current_dial_s32=3,
                    ),
                    "post_dialog_room": self._sendell_checkpoint(
                        "post_dialog_room",
                        screenshot_path="screenshots/post_dialog_room.png",
                        ptr_prg_value_u32=0x00497710,
                        type_answer_u32=0,
                        value_u32=0,
                        ptr_prg_window_bytes_hex="55 66 77 88",
                        magic_level_u8=3,
                        magic_point_u8=60,
                        sendell_inventory_value_s16=1,
                        inventory_model_id_s16=0,
                        current_dial_s32=3,
                    ),
                }

                summary = capture_sendell_ball.build_sendell_run_summary(
                    writer=writer,
                    launch_save=Path(r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA"),
                    capture_variant_name="full_flow",
                    checkpoint_order=checkpoint_order,
                    checkpoint_captures=checkpoint_captures,
                )
            finally:
                writer.close()

        self.assertEqual("sendell-run-summary-v2", summary["schema_version"])
        self.assertEqual("cdb-agent", summary["debugger"])
        self.assertEqual("full_flow", summary["capture_variant"])
        self.assertTrue(summary["transitions"]["dialog_transition_seen"])
        self.assertTrue(summary["transitions"]["post_dialog_transition_seen"])
        self.assertTrue(summary["transitions"]["current_dial_transition"]["stable_across_flow"])
        self.assertFalse(summary["transitions"]["current_dial_transition"]["changed_during_flow"])
        self.assertEqual(
            "sendell_story_state_transition_observed",
            summary["verdict"]["result"],
        )
        self.assertEqual(
            "AA BB CC DD",
            summary["transitions"]["dialog_signature"]["dialog_1"]["ptr_prg_window_bytes_hex"],
        )
        self.assertTrue(summary["transitions"]["direct_story_state_transition_seen"])
        self.assertEqual(
            {"after": 3, "before": 2, "changed": True},
            summary["transitions"]["story_state_transition"]["magic_level"],
        )
        self.assertEqual(
            {"after": 1, "before": 0, "changed": True},
            summary["transitions"]["story_state_transition"]["sendell_inventory_value"],
        )
        self.assertEqual(
            [3],
            summary["transitions"]["current_dial_transition"]["observed_unique_values"],
        )

    def test_write_sendell_run_summary_registers_menu_lane_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                mode="sendell-ball-room",
                process_name="LBA2.EXE",
                launch_save=r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA",
                run_id="sendell-menu-summary-test",
            )
            try:
                output_path = capture_sendell_ball.write_sendell_run_summary(
                    writer,
                    launch_save=Path(r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA"),
                    capture_variant_name="pre_inventory",
                    checkpoint_order=["loaded_pre_cast", "pre_inventory"],
                    checkpoint_captures={
                        "loaded_pre_cast": self._sendell_checkpoint(
                            "loaded_pre_cast",
                            screenshot_path="screenshots/loaded_pre_cast.png",
                            ptr_prg_value_u32=0x004976D0,
                            type_answer_u32=0,
                            value_u32=0,
                            ptr_prg_window_bytes_hex="10 20 30 40",
                        ),
                        "pre_inventory": self._sendell_checkpoint(
                            "pre_inventory",
                            screenshot_path="screenshots/pre_inventory.png",
                            ptr_prg_value_u32=0x004976D0,
                            type_answer_u32=0,
                            value_u32=0,
                            ptr_prg_window_bytes_hex="10 20 30 40",
                        ),
                    },
                )
            finally:
                writer.close()

            manifest = json.loads(writer.manifest_path.read_text(encoding="utf-8"))
            payload = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertEqual("sendell_summary.json", manifest["artifacts"]["sendell_summary"])
        self.assertEqual("sendell_menu_capture_complete", payload["verdict"]["result"])
        self.assertEqual(["loaded_pre_cast", "pre_inventory"], payload["checkpoint_order"])
        self.assertTrue(payload["checkpoints"]["pre_inventory"]["present"])
        self.assertIn("direct_state", payload["checkpoints"]["pre_inventory"])
        self.assertTrue(payload["transitions"]["current_dial_transition"]["present_at_loaded_pre_cast"])
        self.assertFalse(payload["transitions"]["current_dial_transition"]["fully_sampled_flow"])
        self.assertFalse(payload["transitions"]["current_dial_transition"]["stable_across_flow"])
        self.assertFalse(payload["transitions"]["current_dial_transition"]["changed_during_flow"])
        self.assertEqual([0], payload["transitions"]["current_dial_transition"]["observed_unique_values"])

    def test_sendell_capture_contract_records_current_dial_as_transient_only(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(
                Path(temp_dir),
                mode="sendell-ball-room",
                process_name="LBA2.EXE",
                launch_save=r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA",
                run_id="sendell-currentdial-contract-test",
            )
            try:
                output_path = capture_sendell_ball.write_sendell_run_summary(
                    writer,
                    launch_save=Path(r"D:\repos\reverse\littlebigreversing\work\saves\ball of sendell.LBA"),
                    capture_variant_name="pre_inventory",
                    checkpoint_order=["loaded_pre_cast", "pre_inventory"],
                    checkpoint_captures={
                        "loaded_pre_cast": self._sendell_checkpoint(
                            "loaded_pre_cast",
                            screenshot_path="screenshots/loaded_pre_cast.png",
                            ptr_prg_value_u32=0x004976D0,
                            type_answer_u32=0,
                            value_u32=0,
                            ptr_prg_window_bytes_hex="10 20 30 40",
                        ),
                        "pre_inventory": self._sendell_checkpoint(
                            "pre_inventory",
                            screenshot_path="screenshots/pre_inventory.png",
                            ptr_prg_value_u32=0x004976D0,
                            type_answer_u32=0,
                            value_u32=0,
                            ptr_prg_window_bytes_hex="10 20 30 40",
                        ),
                    },
                )
            finally:
                writer.close()

            payload = json.loads(output_path.read_text(encoding="utf-8"))

        self.assertIn("CurrentDial", payload["captured_transient_state_fields"])
        self.assertNotIn("CurrentDial", payload["captured_state_fields"])
        self.assertNotIn("CurrentDial", payload["checkpoints"]["loaded_pre_cast"]["direct_state"])
        self.assertNotIn("CurrentDial", payload["checkpoints"]["pre_inventory"]["direct_state"])
        self.assertEqual(
            0,
            payload["checkpoints"]["loaded_pre_cast"]["transient_dialog_state"]["current_dial_s32"],
        )


class CdbAgentMemoryReaderTest(unittest.TestCase):
    def test_read_scalars_uses_cdb_agent_json_memory_commands(self) -> None:
        reader = life_trace_debugger.CdbMemoryReader(
            Path(r"C:\debuggers\cdb.exe"),
            4321,
            timeout_sec=12.5,
            cdb_agent_command=["cdb-agent"],
        )

        with mock.patch.object(
            life_trace_debugger,
            "run_cdb_agent_json",
            side_effect=[
                {"rows": [{"address": 0x004976D0, "value": 0x00420000}]},
                {"rows": [{"address": 0x00497D44, "value": 0x0004}]},
            ],
        ) as mocked_run:
            dwords, words = reader.read_scalars(
                dword_addresses=(0x004976D0,),
                word_addresses=(0x00497D44,),
            )

        self.assertEqual({0x004976D0: 0x00420000}, dwords)
        self.assertEqual({0x00497D44: 0x0004}, words)
        mocked_run.assert_has_calls(
            [
                mock.call(
                    ["cdb-agent"],
                    [
                        "memory",
                        "dword",
                        "--pid",
                        "4321",
                        "--cdb-path",
                        r"C:\debuggers\cdb.exe",
                        "--wow64",
                        "--timeout-sec",
                        "12.5",
                        "0x004976D0",
                    ],
                    timeout_sec=12.5,
                ),
                mock.call(
                    ["cdb-agent"],
                    [
                        "memory",
                        "word",
                        "--pid",
                        "4321",
                        "--cdb-path",
                        r"C:\debuggers\cdb.exe",
                        "--wow64",
                        "--timeout-sec",
                        "12.5",
                        "0x00497D44",
                    ],
                    timeout_sec=12.5,
                ),
            ]
        )

    def test_read_bytes_collects_contiguous_rows_from_cdb_agent_output(self) -> None:
        reader = life_trace_debugger.CdbMemoryReader(
            Path(r"C:\debuggers\cdb.exe"),
            4321,
            cdb_agent_command=["cdb-agent"],
        )

        with mock.patch.object(
            life_trace_debugger,
            "run_cdb_agent_json",
            return_value={
                "rows": [
                    {
                        "address": 0x0049BCC6,
                        "bytes": [0x00, 0x01, 0x17, 0x42, 0x00, 0x75, 0x2D, 0x00, 0x74, 0x17],
                        "bytes_hex": "00 01 17 42 00 75 2D 00 74 17",
                    }
                ]
            },
        ):
            data = reader.read_bytes(0x0049BCC6, 10)

        self.assertEqual(
            bytes([0x00, 0x01, 0x17, 0x42, 0x00, 0x75, 0x2D, 0x00, 0x74, 0x17]),
            data,
        )


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


class SaveProfilesCliTest(unittest.TestCase):
    def test_validate_profiles_payload_rejects_duplicate_profile_ids(self) -> None:
        payload = {
            "schema_version": "lba2-save-profiles-v3",
            "purpose": "test",
            "profiles": [
                {
                    "profile_id": "dup",
                    "scene_name": "One",
                    "scene_id": 1,
                    "raw_scene_entry_index": 2,
                    "proof_goal": "first",
                    "generation_spec": {
                        "story_arc": "arc",
                        "story_prerequisites": ["a"],
                        "hero_state": ["b"],
                        "room_requirement": "room",
                        "interaction_boundary": "boundary",
                        "record_with_save": ["field"],
                    },
                    "visual_verification": {
                        "validation_method": "manual",
                        "screenshot_step": "step",
                        "expected_visual_cues": ["cue"],
                        "mismatch_examples": ["mismatch"],
                    },
                    "operator_generation_instructions": ["step"],
                },
                {
                    "profile_id": "dup",
                    "scene_name": "Two",
                    "scene_id": 3,
                    "raw_scene_entry_index": 4,
                    "proof_goal": "second",
                    "generation_spec": {
                        "story_arc": "arc",
                        "story_prerequisites": ["a"],
                        "hero_state": ["b"],
                        "room_requirement": "room",
                        "interaction_boundary": "boundary",
                        "record_with_save": ["field"],
                    },
                    "visual_verification": {
                        "validation_method": "manual",
                        "screenshot_step": "step",
                        "expected_visual_cues": ["cue"],
                        "mismatch_examples": ["mismatch"],
                    },
                    "operator_generation_instructions": ["step"],
                },
            ],
        }

        with self.assertRaisesRegex(RuntimeError, "duplicate save profile id 'dup'"):
            save_profiles.validate_profiles_payload(payload, Path(r"D:\temp\save_profiles.json"))

    def test_render_profile_text_includes_generation_instructions(self) -> None:
        payload = save_profiles.load_profiles(save_profiles.DEFAULT_PROFILES_PATH)
        profile = save_profiles.find_profile(payload, "scene11-returned-house")

        rendered = save_profiles.render_profile_text(profile)

        self.assertIn("profile_id: scene11-returned-house", rendered)
        self.assertIn("story_arc: Returned-to-Twinsun / kidnapped-children late-house family", rendered)
        self.assertIn("visual_validation_method:", rendered)
        self.assertIn("visual_screenshot_step:", rendered)
        self.assertIn("expected_visual_cues:", rendered)
        self.assertIn("operator_generation_instructions:", rendered)
        self.assertIn("Go to Neighbour's House during the kidnapped-children or equivalent late-house branch.", rendered)

    def test_save_profiles_cli_list_writes_human_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "profiles.txt"

            exit_code = save_profiles.main(["list", "--output", str(output_path)])

            rendered = output_path.read_text(encoding="utf-8")
            self.assertEqual(0, exit_code)
            self.assertIn("scene11-early-house: Early-game baseline contrast", rendered)
            self.assertIn("tavern-sendell-ball: Tavern proof in the lightning-spell / Sendell-ball story family.", rendered)
            self.assertIn("wizard-tent-lightning-spell: Weather-mage proof for the lightning-spell step that feeds the Sendell story family.", rendered)
            self.assertIn("sendell-ball-room: Direct story-critical proof in the actual Sendell's Ball room.", rendered)

    def test_save_profiles_cli_show_json_writes_selected_profile(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "profile.json"

            exit_code = save_profiles.main(
                ["show", "scene11-wizard-house", "--json", "--output", str(output_path)]
            )

            rendered = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(0, exit_code)
            self.assertEqual("scene11-wizard-house", rendered["profile_id"])
            self.assertEqual("School-of-Magic / wizard-disguise family", rendered["generation_spec"]["story_arc"])

    def test_save_profiles_cli_validate_json_reports_ok(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "validate.json"

            exit_code = save_profiles.main(["validate", "--json", "--output", str(output_path)])

            rendered = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(0, exit_code)
            self.assertEqual("ok", rendered["status"])
            self.assertEqual("lba2-save-profiles-v3", rendered["schema_version"])
            self.assertGreaterEqual(rendered["profile_count"], 1)


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


class LaunchPreflightTest(unittest.TestCase):
    def test_preflight_kills_existing_owned_launch_processes_only_with_takeover(self) -> None:
        completed = subprocess.CompletedProcess(["taskkill"], 0, stdout="SUCCESS", stderr="")

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with (
                    mock.patch.object(
                        trace_life.runtime,
                        "list_running_image_pids",
                        side_effect=lambda image: [111] if image in {"LBA2.EXE", "cdb.exe"} else [],
                    ),
                    mock.patch.object(
                        trace_life.runtime.subprocess,
                        "run",
                        side_effect=[completed, completed],
                    ) as mocked_run,
                ):
                    trace_life.runtime.preflight_owned_launch_processes(
                        writer,
                        "LBA2.EXE",
                        takeover_existing_processes=True,
                    )
            finally:
                writer.close()

            mocked_run.assert_has_calls(
                [
                    mock.call(
                        ["taskkill", "/IM", "LBA2.EXE", "/F"],
                        capture_output=True,
                        text=True,
                        check=False,
                    ),
                    mock.call(
                        ["taskkill", "/IM", "cdb.exe", "/F"],
                        capture_output=True,
                        text=True,
                        check=False,
                    ),
                ]
            )
            messages = [line["message"] for line in read_jsonl_lines(writer.enriched_output_path)]
            self.assertEqual(
                [
                    "preflight killed existing LBA2.EXE",
                    "preflight killed existing cdb.exe",
                ],
                messages,
            )

    def test_preflight_refuses_existing_owned_processes_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with mock.patch.object(
                    trace_life.runtime,
                    "list_running_image_pids",
                    side_effect=lambda image: [111] if image == "LBA2.EXE" else [],
                ):
                    with self.assertRaisesRegex(RuntimeError, "--takeover-existing-processes"):
                        trace_life.runtime.preflight_owned_launch_processes(writer, "LBA2.EXE")
            finally:
                writer.close()

            self.assertEqual([], read_jsonl_lines(writer.enriched_output_path))

    def test_preflight_skips_taskkill_when_no_existing_processes_are_running(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                with (
                    mock.patch.object(trace_life.runtime, "list_running_image_pids", return_value=[]),
                    mock.patch.object(trace_life.runtime.subprocess, "run") as mocked_run,
                ):
                    trace_life.runtime.preflight_owned_launch_processes(writer, "LBA2.EXE")
            finally:
                writer.close()

            mocked_run.assert_not_called()
            self.assertEqual([], read_jsonl_lines(writer.enriched_output_path))


class ApplicationErrorDialogDetectionTest(unittest.TestCase):
    def test_detect_application_error_dialog_records_status(self) -> None:
        fake_capture = mock.Mock()
        fake_capture.find_window.return_value = trace_life.WindowInfo(
            hwnd=1,
            title="Application Error: D:\\games\\LBA2.EXE",
            left=0,
            top=0,
            right=640,
            bottom=480,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                title = trace_life.runtime.detect_application_error_dialog(
                    writer,
                    1234,
                    capture=fake_capture,
                )
            finally:
                writer.close()

            self.assertEqual("Application Error: D:\\games\\LBA2.EXE", title)
            messages = [line["message"] for line in read_jsonl_lines(writer.enriched_output_path)]
            self.assertEqual(
                ["detected Application Error dialog: Application Error: D:\\games\\LBA2.EXE"],
                messages,
            )

    def test_detect_application_error_dialog_returns_none_for_normal_window(self) -> None:
        fake_capture = mock.Mock()
        fake_capture.find_window.return_value = trace_life.WindowInfo(
            hwnd=1,
            title="LBA2",
            left=0,
            top=0,
            right=640,
            bottom=480,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                title = trace_life.runtime.detect_application_error_dialog(
                    writer,
                    1234,
                    capture=fake_capture,
                )
            finally:
                writer.close()

            self.assertIsNone(title)
            self.assertEqual([], read_jsonl_lines(writer.enriched_output_path))

    def test_detect_application_error_dialog_falls_back_to_global_title_match(self) -> None:
        fake_capture = mock.Mock()
        fake_capture.find_window.return_value = None
        fake_capture.find_window_title_fragments.return_value = trace_life.WindowInfo(
            hwnd=2,
            title="Application Error: D:\\games\\LBA2.EXE",
            left=0,
            top=0,
            right=640,
            bottom=480,
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir))
            try:
                title = trace_life.runtime.detect_application_error_dialog(
                    writer,
                    1234,
                    capture=fake_capture,
                    process_name="LBA2.EXE",
                    launch_path=r"D:\games\LBA2.EXE",
                )
            finally:
                writer.close()

            self.assertEqual("Application Error: D:\\games\\LBA2.EXE", title)
            messages = [line["message"] for line in read_jsonl_lines(writer.enriched_output_path)]
            self.assertEqual(
                ["detected Application Error dialog: Application Error: D:\\games\\LBA2.EXE"],
                messages,
            )


if __name__ == "__main__":
    unittest.main()
