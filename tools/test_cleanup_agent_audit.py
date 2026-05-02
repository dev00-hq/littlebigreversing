from __future__ import annotations

import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cleanup_agent_audit


class CleanupAgentAuditTests(unittest.TestCase):
    def test_status_parser_groups_cleanup_candidates_without_editing_policy(self) -> None:
        items = cleanup_agent_audit.parse_git_status_porcelain(
            "\n".join(
                [
                    " M docs/codex_memory/current_focus.md",
                    " M docs/codex_memory/generated/task_briefing.md",
                    " M tools/lba2_save_loader.py",
                    "?? work/live_proofs/example/",
                    "R  old.txt -> docs/new.txt",
                ]
            )
        )

        self.assertEqual("docs/new.txt", items[-1].path)
        groups = cleanup_agent_audit.grouped_status(items)

        self.assertEqual(
            [
                {"code": " M", "path": "docs/codex_memory/current_focus.md"},
                {"code": "R ", "path": "docs/new.txt"},
            ],
            groups["canonical"],
        )
        self.assertEqual(
            [{"code": " M", "path": "docs/codex_memory/generated/task_briefing.md"}],
            groups["generated"],
        )
        self.assertEqual(
            [{"code": " M", "path": "tools/lba2_save_loader.py"}],
            groups["user_work"],
        )
        self.assertEqual(
            [{"code": "??", "path": "work/live_proofs/example/"}],
            groups["rebuildable_work"],
        )

    def test_json_report_is_read_only_by_policy(self) -> None:
        report = cleanup_agent_audit.build_report(run_validation=False)

        self.assertEqual("cleanup-agent-audit-v1", report["schema"])
        self.assertEqual("read_only", report["mode"])
        self.assertFalse(report["policy"]["may_edit"])
        self.assertIn("findings", report)
        self.assertEqual("dirty_canonical", report["scan"]["scope"])
        self.assertNotIn("validation", report)

    def test_dirty_scan_paths_ignores_generated_work_and_known_user_files(self) -> None:
        items = cleanup_agent_audit.parse_git_status_porcelain(
            "\n".join(
                [
                    " M port/src/runtime/session.zig",
                    " M docs/codex_memory/generated/task_briefing.md",
                    " M tools/lba2_save_loader.py",
                    "?? work/live_proofs/example/",
                    "?? tools/cleanup_agent_audit.py",
                ]
            )
        )

        self.assertEqual(["port/src/runtime/session.zig"], cleanup_agent_audit.dirty_scan_paths(items))

    def test_dirty_scan_paths_ignores_untracked_directories(self) -> None:
        items = cleanup_agent_audit.parse_git_status_porcelain("?? tools/fixtures/affordance_probes/")

        self.assertEqual([], cleanup_agent_audit.dirty_scan_paths(items))

    def test_hard_cut_scan_reports_line_level_warnings(self) -> None:
        watched_fixture = "fallback"
        self.assertEqual("fallback", watched_fixture)
        findings = cleanup_agent_audit.scan_hard_cut_terms(["tools/test_cleanup_agent_audit.py"])

        self.assertTrue(any(finding.rule_id == "hard_cut_term_review" for finding in findings))
        self.assertTrue(all(finding.severity == "warning" for finding in findings))
        self.assertTrue(all(finding.path == "tools/test_cleanup_agent_audit.py" for finding in findings))
        self.assertTrue(all(finding.line is not None for finding in findings))


if __name__ == "__main__":
    unittest.main()
