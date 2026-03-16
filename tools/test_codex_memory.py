from __future__ import annotations

import sys
import sqlite3
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import codex_memory


class CodexMemoryTest(unittest.TestCase):
    def make_paths(self) -> codex_memory.MemoryPaths:
        temp_dir = Path(tempfile.mkdtemp())
        return codex_memory.MemoryPaths.defaults(temp_dir)

    def test_init_and_validate_scaffold(self) -> None:
        paths = self.make_paths()
        codex_memory.init_memory(paths)
        errors = codex_memory.validate_all(paths)
        self.assertEqual(errors, [])

    def test_add_records_and_render_context(self) -> None:
        paths = self.make_paths()
        codex_memory.init_memory(paths)

        codex_memory.add_decision(
            paths,
            topic="memory",
            status="accepted",
            statement="Store durable memory in docs and derived state in work.",
            rationale="Keeps memory reviewable and rebuildable.",
            evidence_refs=["docs/source.md"],
            affected_paths=["docs/codex_memory", "tools/codex_memory.py"],
            supersedes=[],
            author="tester",
            timestamp="2026-03-16T12:00:00Z",
        )
        codex_memory.add_task_event(
            paths,
            task_id="bootstrap memory",
            title="Bootstrap memory",
            status="completed",
            summary="Created initial durable memory records.",
            next_actions=["Use context output at task start."],
            affected_paths=["docs/codex_memory", "tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-16T12:05:00Z",
        )

        output = codex_memory.render_context(paths, recent_limit=5)
        self.assertIn("# Codex Context", output)
        self.assertIn("Store durable memory in docs and derived state in work.", output)
        self.assertIn("Created initial durable memory records.", output)

    def test_build_index_creates_expected_tables(self) -> None:
        paths = self.make_paths()
        codex_memory.init_memory(paths)
        codex_memory.build_index(paths)

        conn = sqlite3.connect(paths.db_path)
        try:
            table_names = {
                row[0]
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                ).fetchall()
            }
        finally:
            conn.close()

        self.assertIn("documents", table_names)
        self.assertIn("decisions", table_names)
        self.assertIn("task_events", table_names)

    def test_validate_rejects_bad_schema_version(self) -> None:
        paths = self.make_paths()
        codex_memory.init_memory(paths)
        paths.decision_log.write_text(
            '{"schema_version":"wrong","decision_id":"decision-20260316T000000Z-9274443ebd","timestamp_utc":"2026-03-16T00:00:00Z","topic":"memory","status":"accepted","statement":"Use canonical memory.","rationale":"Test invalid schema handling.","evidence_refs":["docs/source.md"],"affected_paths":["docs/codex_memory"],"supersedes":[],"author":"tester"}\n',
            encoding="utf-8",
        )

        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("unsupported schema_version" in error for error in errors))

    def test_rejects_absolute_paths(self) -> None:
        paths = self.make_paths()
        codex_memory.init_memory(paths)

        with self.assertRaises(ValueError):
            codex_memory.add_decision(
                paths,
                topic="memory",
                status="accepted",
                statement="Bad absolute path.",
                rationale="Should fail fast.",
                evidence_refs=["docs/source.md"],
                affected_paths=["/tmp/outside"],
                supersedes=[],
                author="tester",
                timestamp="2026-03-16T12:00:00Z",
            )


if __name__ == "__main__":
    unittest.main()
