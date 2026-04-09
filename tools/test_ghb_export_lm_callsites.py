from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

try:
    from tools import ghb_export_lm_callsites
except ModuleNotFoundError:
    import ghb_export_lm_callsites


class GhbExportLmCallsitesTest(unittest.TestCase):
    def test_parse_args_defaults_to_canonical_paths(self) -> None:
        args = ghb_export_lm_callsites.parse_args([])
        self.assertEqual(str(ghb_export_lm_callsites.DEFAULT_GHB_REPO_ROOT), args.ghb_repo_root)
        self.assertEqual(str(ghb_export_lm_callsites.DEFAULT_GHIDRA_INSTALL_DIR), args.ghidra_install_dir)
        self.assertEqual(str(ghb_export_lm_callsites.DEFAULT_BINARY), args.binary)
        self.assertEqual(str(ghb_export_lm_callsites.DEFAULT_OUTPUT), args.output)
        self.assertEqual(ghb_export_lm_callsites.DEFAULT_WITHIN_ENTRY, args.within_entry)

    def test_normalize_callsite_rows_sorts_and_indexes_per_callee(self) -> None:
        raw_rows = [
            {
                "callee_name": "DoTest",
                "callee_address": "ram:0041fe30",
                "within_function": "FUN_00420574",
                "within_entry": "ram:00420574",
                "call_instruction": "ram:00420f8c",
                "caller_static": "ram:00420f91",
                "caller_static_rel": "0x00020F91",
            },
            {
                "callee_name": "DoFuncLife",
                "callee_address": "ram:0041f0a8",
                "within_function": "FUN_00420574",
                "within_entry": "ram:00420574",
                "call_instruction": "ram:00420f46",
                "caller_static": "ram:00420f4b",
                "caller_static_rel": "0x00020F4B",
            },
            {
                "callee_name": "DoTest",
                "callee_address": "ram:0041fe30",
                "within_function": "FUN_00420574",
                "within_entry": "ram:00420574",
                "call_instruction": "ram:00420f4b",
                "caller_static": "ram:00420f50",
                "caller_static_rel": "0x00020F50",
            },
            {
                "callee_name": "DoFuncLife",
                "callee_address": "ram:0041f0a8",
                "within_function": "FUN_00420574",
                "within_entry": "ram:00420574",
                "call_instruction": "ram:00420f87",
                "caller_static": "ram:00420f8c",
                "caller_static_rel": "0x00020F8C",
            },
        ]

        rows = ghb_export_lm_callsites.normalize_callsite_rows(raw_rows)

        self.assertEqual(
            [
                ("DoFuncLife", "ram:00420f46", 0),
                ("DoTest", "ram:00420f4b", 0),
                ("DoFuncLife", "ram:00420f87", 1),
                ("DoTest", "ram:00420f8c", 1),
            ],
            [(row["callee_name"], row["call_instruction"], row["call_index"]) for row in rows],
        )

    def test_build_export_script_embeds_within_filter(self) -> None:
        script = ghb_export_lm_callsites.build_export_script("ram:00420574")
        self.assertIn('targets.put("DoFuncLife", toAddr(0x0041F0A8L));', script)
        self.assertIn('targets.put("DoTest", toAddr(0x0041FE30L));', script)
        self.assertIn('String withinEntryFilter = "ram:00420574";', script)

    def test_main_writes_jsonl_summary_with_mocked_live_steps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            output_path = temp_root / "callsites.jsonl"
            project_root = temp_root / "project"
            ghb_repo_root = temp_root / "ghb"
            ghb_repo_root.mkdir()
            ghidra_install_dir = temp_root / "ghidra"
            ghidra_install_dir.mkdir()
            binary_path = temp_root / "LBA2.EXE"
            binary_path.write_bytes(b"MZ")

            raw_rows = [
                {
                    "callee_name": "DoFuncLife",
                    "callee_address": "ram:0041f0a8",
                    "within_function": "FUN_00420574",
                    "within_entry": "ram:00420574",
                    "call_instruction": "ram:00420f46",
                    "caller_static": "ram:00420f4b",
                    "caller_static_rel": "0x00020F4B",
                },
                {
                    "callee_name": "DoTest",
                    "callee_address": "ram:0041fe30",
                    "within_function": "FUN_00420574",
                    "within_entry": "ram:00420574",
                    "call_instruction": "ram:00420f4b",
                    "caller_static": "ram:00420f50",
                    "caller_static_rel": "0x00020F50",
                },
            ]

            fake_process = SimpleNamespace(
                pid=4321,
                poll=lambda: None,
                terminate=lambda: None,
                wait=lambda timeout=10: None,
            )
            fake_bridge = SimpleNamespace(pid=1234)

            with (
                mock.patch.object(ghb_export_lm_callsites, "ensure_prerequisites"),
                mock.patch.object(ghb_export_lm_callsites, "ensure_no_live_bridge"),
                mock.patch.object(ghb_export_lm_callsites, "prepare_project"),
                mock.patch.object(ghb_export_lm_callsites, "launch_ghidra", return_value=fake_process),
                mock.patch.object(ghb_export_lm_callsites, "wait_for_bridge", return_value=fake_bridge),
                mock.patch.object(ghb_export_lm_callsites, "export_raw_rows", return_value=raw_rows),
                mock.patch.object(ghb_export_lm_callsites, "stop_bridge_process"),
            ):
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    exit_code = ghb_export_lm_callsites.main(
                        [
                            "--ghb-repo-root",
                            str(ghb_repo_root),
                            "--ghidra-install-dir",
                            str(ghidra_install_dir),
                            "--binary",
                            str(binary_path),
                            "--output",
                            str(output_path),
                            "--project-root",
                            str(project_root),
                            "--json",
                        ]
                    )

            self.assertEqual(0, exit_code)
            payload = json.loads(stdout.getvalue())
            self.assertEqual(str(output_path), payload["output"])
            self.assertEqual(2, payload["records"])
            self.assertEqual({"DoFuncLife": 1, "DoTest": 1}, payload["targets"])

            lines = output_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(2, len(lines))
            first = json.loads(lines[0])
            second = json.loads(lines[1])
            self.assertEqual("DoFuncLife", first["callee_name"])
            self.assertEqual(0, first["call_index"])
            self.assertEqual("DoTest", second["callee_name"])
            self.assertEqual(0, second["call_index"])


if __name__ == "__main__":
    unittest.main()
