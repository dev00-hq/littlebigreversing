from __future__ import annotations

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import msgspec

sys.path.insert(0, str(Path(__file__).resolve().parent / "life_trace"))

import trace_life


STATUS_LINE = """{"event_id": "evt-0001", "frida_lib": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\frida\\\\x86_64", "frida_module": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages\\\\frida\\\\__init__.py", "frida_repo_root": "D:\\\\repos\\\\reverse\\\\frida", "frida_root": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida", "frida_site_packages": "D:\\\\repos\\\\reverse\\\\frida\\\\build\\\\install-root\\\\Program Files\\\\Frida\\\\lib\\\\site-packages", "kind": "status", "launch_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\_innoextract_full\\\\Speedrun\\\\Windows\\\\LBA2_cdrom\\\\LBA2\\\\LBA2.EXE", "message": "attached", "mode": "tavern-trace", "output_path": "D:\\\\repos\\\\reverse\\\\littlebigreversing\\\\work\\\\life_trace\\\\life-trace-20260405-011732.jsonl", "phase": "attached", "pid": 25148, "process_name": "LBA2.EXE", "timestamp_utc": "2026-04-05T05:17:33Z"}"""
TARGET_VALIDATION_LINE = """{"event_id": "evt-0005", "fingerprint_hex_actual": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_hex_expected": "28 14 00 21 2F 00 23 0D 0E 00", "fingerprint_start_offset": 40, "kind": "target_validation", "matches_fingerprint": true, "object_index": 0, "owner_kind": "hero", "ptr_life": "0x33a21fb", "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
BRANCH_TRACE_LINE = """{"branch_kind": "break_jump", "computed_target_offset": 103, "event_id": "evt-0014", "exe_switch_after": {"func": 0, "type_answer": 0, "value": 0}, "exe_switch_before": {"func": 0, "type_answer": 0, "value": 0}, "kind": "branch_trace", "object_index": 0, "operand_offset": 103, "ptr_prg_offset_before": 4805, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
WINDOW_TRACE_LINE = """{"current_object": "0x49a19c", "event_id": "evt-0015", "exe_switch": {"func": 0, "type_answer": 0, "value": 0}, "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "ptr_window": {"bytes_hex": "00 22 08 4e 01 75 67 00 76 37 09 00 0b 7a 00 37 09", "cursor_index": 8, "start": "0x33a3506"}, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z", "working_type_answer": 4, "working_value": 0}"""
MINIMAL_TAVERN_WINDOW_TRACE_LINE = """{"byte_at_ptr_prg": 118, "byte_at_ptr_prg_hex": "0x76", "current_object": "0x49a19c", "event_id": "evt-0015", "kind": "window_trace", "matches_target": true, "object_index": 0, "offset_life": 47, "opcode": 118, "opcode_hex": "0x76", "owner_kind": "hero", "ptr_life": "0x33a21fb", "ptr_prg": "0x33a350e", "ptr_prg_offset": 4883, "thread_id": 21624, "timestamp_utc": "2026-04-05T05:17:42Z"}"""
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

    def test_minimal_tavern_window_trace_samples_decode(self) -> None:
        persisted = trace_life.parse_persisted_event_line(MINIMAL_TAVERN_WINDOW_TRACE_LINE)
        self.assertIsInstance(persisted, trace_life.PersistedWindowTraceEvent)

        payload = json.loads(
            MINIMAL_TAVERN_WINDOW_TRACE_LINE.replace('"event_id": "evt-0015", ', "").replace(
                ', "timestamp_utc": "2026-04-05T05:17:42Z"', ""
            )
        )
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

    def test_parse_args_defaults_output_and_launch_path(self) -> None:
        args = trace_life.parse_args(["--mode", "tavern-trace", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.TAVERN_TRACE_PRESET.target_offset, args.target_offset)
        self.assertEqual(str(trace_life.REPO_ROOT / "work" / "life_trace" / "shots"), args.screenshot_dir)
        self.assertEqual(str(trace_life.DEFAULT_FRA_REPO_ROOT), args.fra_repo_root)
        self.assertIsNone(args.frida_repo_root)
        self.assertEqual(trace_life.DEFAULT_OUTPUT_DIR, Path(args.output).parent)
        self.assertEqual(".jsonl", Path(args.output).suffix)

    def test_parse_args_defaults_scene11_to_fra_lane(self) -> None:
        args = trace_life.parse_args(["--mode", "scene11-pair", "--launch"])
        self.assertEqual(str(trace_life.DEFAULT_GAME_EXE), args.launch)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_object, args.target_object)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_opcode, args.target_opcode)
        self.assertEqual(trace_life.SCENE11_PAIR_PRESET.target_offset, args.target_offset)
        self.assertEqual(str(trace_life.REPO_ROOT / "work" / "life_trace" / "shots"), args.screenshot_dir)
        self.assertEqual(str(trace_life.DEFAULT_FRA_REPO_ROOT), args.fra_repo_root)
        self.assertIsNone(args.frida_repo_root)

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
                trace_life,
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
                trace_life,
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
    def test_stage_tavern_resume_save_replaces_current_lba(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            launch_dir = Path(temp_dir) / "LBA2"
            save_dir = launch_dir / "SAVE"
            save_dir.mkdir(parents=True)
            launch_path = launch_dir / "LBA2.EXE"
            launch_path.write_bytes(b"exe")
            source_path = save_dir / "inside-tavern.LBA"
            source_path.write_bytes(b"inside-tavern-save")
            destination_path = save_dir / "current.lba"
            destination_path.write_bytes(b"old-current-save")

            writer = trace_life.JsonlWriter(Path(temp_dir) / "trace.jsonl")
            try:
                staged_source, staged_destination = trace_life.stage_tavern_resume_save(writer, launch_path)
            finally:
                writer.close()

            self.assertEqual(source_path, staged_source)
            self.assertEqual(destination_path, staged_destination)
            self.assertEqual(b"inside-tavern-save", destination_path.read_bytes())

            lines = [
                json.loads(line)
                for line in (Path(temp_dir) / "trace.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertEqual("staged inside-tavern.LBA into current.lba", lines[0]["message"])

    def test_drive_tavern_launch_startup_drives_adeline_and_resume_enters(self) -> None:
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
                self.hwnds: list[int] = []

            def send_enter(self, hwnd: int) -> None:
                self.hwnds.append(hwnd)

        with tempfile.TemporaryDirectory() as temp_dir:
            writer = trace_life.JsonlWriter(Path(temp_dir) / "trace.jsonl")
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

            self.assertEqual([0x1234, 0x1234], window_input.hwnds)
            self.assertEqual(
                [
                    (4321, trace_life.TAVERN_STARTUP_WINDOW_TIMEOUT_SEC),
                    (4321, trace_life.TAVERN_STARTUP_WINDOW_TIMEOUT_SEC),
                ],
                capture.wait_calls,
            )
            self.assertEqual(
                [
                    mock.call(trace_life.TAVERN_ADELINE_ENTER_DELAY_SEC),
                    mock.call(trace_life.TAVERN_RESUME_ENTER_DELAY_SEC),
                    mock.call(trace_life.TAVERN_RESUME_SETTLE_DELAY_SEC),
                ],
                mocked_sleep.call_args_list,
            )

            lines = [
                json.loads(line)
                for line in (Path(temp_dir) / "trace.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            messages = [line["message"] for line in lines if line.get("kind") == "status" and "message" in line]
            self.assertIn("driving Tavern startup through Adeline and Resume Game", messages)
            self.assertIn("sent Enter to continue past the Adeline splash", messages)
            self.assertIn("sent Enter to activate Resume Game", messages)
            self.assertIn("waited for Resume Game to settle before attaching fra probe", messages)


if __name__ == "__main__":
    unittest.main()
