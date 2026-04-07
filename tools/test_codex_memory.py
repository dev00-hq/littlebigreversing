from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import codex_memory


class CodexMemoryV2Test(unittest.TestCase):
    def make_paths(self) -> codex_memory.MemoryPaths:
        root = Path(tempfile.mkdtemp())
        return codex_memory.MemoryPaths.defaults(root)

    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def history_lines(self, output: str, heading: str) -> list[str]:
        marker = f"## {heading}"
        if marker not in output:
            return []
        lines = output.split(marker, 1)[1].splitlines()[1:]
        result = []
        for line in lines:
            if line.startswith("## "):
                break
            if line.strip():
                result.append(line)
        return result

    def pack_doc(self, name: str) -> str:
        return f"""# {name}

## Purpose

- {name} purpose.

## Invariants

- {name} invariants.

## Current Parity Status

- {name} parity.

## Known Traps

- {name} traps.

## Canonical Entry Points

- {name} entrypoints.

## Important Files

- {name} files.

## Test / Probe Commands

- {name} probes.

## Open Unknowns

- {name} unknowns.
"""

    def scaffold(self, paths: codex_memory.MemoryPaths, *, ambiguous: bool = False, obsolete: bool = False, missing_mapping: bool = False) -> None:
        self.write(
            paths.docs_dir / "README.md",
            """# Codex Memory

## Workflow

1. Read `project_brief.md` and `current_focus.md`.

## Commands

```bash
python3 tools/codex_memory.py validate
python3 tools/codex_memory.py context --subsystem architecture
```

## Write Rules

- Keep typed history in JSONL files only.

## Budgets

- `project_brief.md` <= 2 KB
- `current_focus.md` <= 3 KB
- subsystem packs <= 4 KB
""",
        )
        self.write(
            paths.docs_dir / "project_brief.md",
            """# Project Brief

## Purpose

Repo-scoped memory for tests.

## Repo Map

- `docs/`
- `tools/`
- `port/`

## Canonical Sources

- `docs/LBA2_ZIG_PORT_PLAN.md`

## Invariants

- One v2 memory tree.

## Non-Goals

- v1 compatibility.
""",
        )
        self.write(
            paths.docs_dir / "current_focus.md",
            """# Current Focus

## Current Priorities

- Keep the v2 tree canonical.

## Active Streams

- Memory validation.

## Blocked Items

- None.

## Next Actions

- Use subsystem packs.

## Relevant Subsystem Packs

- architecture
- backgrounds
""",
        )
        platform_linux_rule = "" if missing_mapping else "- `platform_linux`: `docs/codex_memory/subsystems/platform_linux.md`\n"
        architecture_rule = "- `architecture`: `AGENTS.md`, `ISSUES.md`, `docs/PROMPT.md`, `docs/codex_memory/README.md`, `docs/codex_memory/current_focus.md`, `docs/codex_memory/project_brief.md`, `tools/codex_memory.py`"
        self.write(
            paths.subsystem_dir / "INDEX.md",
            f"""# Subsystem Index

## Pack List

- `assets`: asset tooling.
- `mbn_corpus`: corpus tooling.
- `phase0_baseline`: phase0 baseline.
- `scene_decode`: scene decoding.
- `life_scripts`: life scripts.
- `backgrounds`: backgrounds.
- `platform_windows`: windows host.
- `platform_linux`: linux host.
- `architecture`: repo architecture.

## Path Mapping Rules

- `assets`: `port/src/assets/`
- `mbn_corpus`: `docs/mbn_reference/`
- `phase0_baseline`: `docs/phase0/`
- `scene_decode`: `port/src/game_data/scene.zig`{", `port/src/game_data/background/`" if ambiguous else ""}
- `life_scripts`: `port/src/game_data/scene/life_program.zig`
- `backgrounds`: `port/src/game_data/background/`
- `platform_windows`: `scripts/check-env.ps1`
{platform_linux_rule}{architecture_rule}
""",
        )
        for name in codex_memory.EXPECTED_SUBSYSTEMS:
            self.write(paths.subsystem_path(name), self.pack_doc(name.title()))
        for filename in codex_memory.HISTORY_FILES:
            self.write(paths.history_path(filename), "")

        self.write(paths.repo_root / "AGENTS.md", "# agents\n")
        self.write(paths.repo_root / "ISSUES.md", "# issues\n")
        self.write(paths.repo_root / "docs" / "PROMPT.md", "# prompt\n")
        self.write(paths.repo_root / "tools" / "codex_memory.py", "# tool\n")
        self.write(paths.repo_root / "scripts" / "check-env.ps1", "# windows\n")
        self.write(paths.repo_root / "docs" / "codex_memory" / "subsystems" / "platform_linux.md", self.pack_doc("Platform Linux"))
        self.write(paths.repo_root / "docs" / "mbn_reference" / "README.md", "# corpus\n")
        self.write(paths.repo_root / "docs" / "phase0" / "README.md", "# phase0\n")
        self.write(paths.repo_root / "port" / "src" / "assets" / "hqr.zig", "// assets\n")
        self.write(paths.repo_root / "port" / "src" / "game_data" / "scene.zig", "// scene\n")
        self.write(paths.repo_root / "port" / "src" / "game_data" / "scene" / "life_program.zig", "// life\n")
        self.write(paths.repo_root / "port" / "src" / "game_data" / "background" / "parser.zig", "// background\n")

        if obsolete:
            self.write(paths.docs_dir / "handoff.md", "# obsolete\n")

    def test_validate_accepts_v2_tree(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        self.assertEqual(codex_memory.validate_all(paths), [])

    def test_context_default_only_reads_brief_and_focus(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        output = codex_memory.render_context(paths)
        self.assertIn("# Project Brief", output)
        self.assertIn("# Current Focus", output)
        self.assertNotIn("# Backgrounds", output)

    def test_context_path_and_history_filter(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_fact(
            paths,
            subsystem="backgrounds",
            status="current",
            fact="Background inspection is separate from scene inspection.",
            rationale="The loader boundary is different.",
            supersedes=[],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T22:05:00Z",
        )
        codex_memory.add_fact(
            paths,
            subsystem="scene_decode",
            status="current",
            fact="Scene inspection stays on its own facade.",
            rationale="The scene model owns its own surface.",
            supersedes=[],
            evidence_refs=["port/src/game_data/scene.zig"],
            affected_paths=["port/src/game_data/scene.zig"],
            author="tester",
            timestamp="2026-03-26T22:06:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=5,
        )
        self.assertIn("# Backgrounds", output)
        self.assertIn("Background inspection is separate", output)
        self.assertNotIn("# Scene_Decode", output)
        self.assertNotIn("Scene inspection stays", output)

    def test_context_history_prefers_fact_subsystem_over_affected_paths(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_fact(
            paths,
            subsystem="platform_linux",
            status="current",
            fact="Linux remains an analysis-only host.",
            rationale="The checked-in runtime path is still Windows-first.",
            supersedes=[],
            evidence_refs=["docs/PHASE1_IMPLEMENTATION_MEMO.md"],
            affected_paths=["scripts/check-env.ps1"],
            author="tester",
            timestamp="2026-03-26T22:07:00Z",
        )
        output = codex_memory.render_context(
            paths,
            subsystem_names=["platform_windows"],
            include_history=5,
        )
        self.assertNotIn("Linux remains an analysis-only host.", output)

    def test_context_history_excludes_noncanonical_and_nonfinal_task_records(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_task_event(
            paths,
            stream="viewer-prep",
            status="completed",
            summary="Background evidence boundary landed.",
            next_actions=["Keep the guarded path explicit."],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:10:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="prompt-refresh",
            status="completed",
            summary="Refreshed prompt text for the next slice.",
            next_actions=["Keep prompts narrow."],
            evidence_refs=["docs/PROMPT.md"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:11:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="viewer-prep",
            status="in_progress",
            summary="Still iterating on the boundary.",
            next_actions=["Finish the boundary work."],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:12:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="windows-debug-workflow",
            status="completed",
            summary="LM debugger notes touched the background workflow.",
            next_actions=["Keep debugger work task-local."],
            evidence_refs=["tools/life_trace/trace_life.py"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:13:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="lm-switch-repro-setup",
            status="completed",
            summary="LM trace work touched the same background code.",
            next_actions=["Keep LM traces out of default pickup."],
            evidence_refs=["tools/life_trace/trace_life.py"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:14:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=10,
        )
        self.assertIn("Background evidence boundary landed.", output)
        self.assertNotIn("Refreshed prompt text", output)
        self.assertNotIn("Still iterating on the boundary.", output)
        self.assertNotIn("LM debugger notes touched", output)
        self.assertNotIn("LM trace work touched", output)

    def test_context_history_can_include_excluded_records_on_request(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_task_event(
            paths,
            stream="prompt-refresh",
            status="completed",
            summary="Refreshed prompt text for the next slice.",
            next_actions=["Keep prompts narrow."],
            evidence_refs=["docs/PROMPT.md"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:11:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="lm-switch-repro-setup",
            status="completed",
            summary="LM trace work touched the same background code.",
            next_actions=["Keep LM traces out of default pickup unless requested."],
            evidence_refs=["tools/life_trace/trace_life.py"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T23:14:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=10,
            include_excluded_history=True,
        )
        self.assertIn("Refreshed prompt text", output)
        self.assertIn("LM trace work touched", output)

    def test_context_history_hides_superseded_policies(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        old = codex_memory.add_policy(
            paths,
            topic="repo-framing",
            status="accepted",
            statement="Old framing rule.",
            rationale="Older framing guidance.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:15:00Z",
        )
        codex_memory.add_policy(
            paths,
            topic="repo-framing",
            status="accepted",
            statement="New framing rule.",
            rationale="Newer framing guidance.",
            supersedes=[old["record_id"]],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:16:00Z",
        )
        output = codex_memory.render_context(
            paths,
            subsystem_names=["architecture"],
            include_history=5,
        )
        self.assertIn("New framing rule.", output)
        self.assertNotIn("Old framing rule.", output)

    def test_snapshot_render_matches_path_render(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_fact(
            paths,
            subsystem="backgrounds",
            status="current",
            fact="Background inspection is separate from scene inspection.",
            rationale="The loader boundary is different.",
            supersedes=[],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/"],
            author="tester",
            timestamp="2026-03-26T22:05:00Z",
        )
        from_paths = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=5,
        )
        snapshot = codex_memory.build_snapshot(paths)
        from_snapshot = codex_memory.render_context(
            snapshot,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=5,
        )
        self.assertEqual(from_paths, from_snapshot)

    def test_context_recent_mode_matches_default_mode(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_fact(
            paths,
            subsystem="backgrounds",
            status="current",
            fact="Older background fact.",
            rationale="Older background rationale.",
            supersedes=[],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/parser.zig"],
            author="tester",
            timestamp="2026-03-26T22:05:00Z",
        )
        codex_memory.add_fact(
            paths,
            subsystem="backgrounds",
            status="current",
            fact="Newer background fact.",
            rationale="Newer background rationale.",
            supersedes=[],
            evidence_refs=["port/src/game_data/background/parser.zig"],
            affected_paths=["port/src/game_data/background/parser.zig"],
            author="tester",
            timestamp="2026-03-26T22:06:00Z",
        )
        default_output = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=5,
        )
        recent_output = codex_memory.render_context(
            paths,
            repo_paths=["port/src/game_data/background/parser.zig"],
            include_history=5,
            history_mode="recent",
        )
        self.assertEqual(default_output, recent_output)

    def test_context_recent_includes_evidence_only_exact_path_matches(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Evidence-only tool policy.",
            rationale="Exact evidence refs should surface for path-scoped history.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=[],
            author="tester",
            timestamp="2026-03-26T22:07:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=5,
        )
        lines = self.history_lines(output, "Recent History")
        self.assertEqual(1, len(lines))
        self.assertIn("Evidence-only tool policy.", lines[0])

    def test_context_relevant_includes_evidence_only_exact_path_matches(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Evidence-only relevant policy.",
            rationale="Exact evidence refs should surface for relevant path-scoped history.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=[],
            author="tester",
            timestamp="2026-03-26T22:08:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=5,
            history_mode="relevant",
        )
        lines = self.history_lines(output, "Relevant History")
        self.assertEqual(1, len(lines))
        self.assertIn("Evidence-only relevant policy.", lines[0])

    def test_context_subsystem_query_includes_evidence_only_matches(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Subsystem evidence-only policy.",
            rationale="Subsystem-scoped history should infer ownership from evidence refs too.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=[],
            author="tester",
            timestamp="2026-03-26T22:09:00Z",
        )
        output = codex_memory.render_context(
            paths,
            subsystem_names=["architecture"],
            include_history=5,
        )
        lines = self.history_lines(output, "Recent History")
        self.assertEqual(1, len(lines))
        self.assertIn("Subsystem evidence-only policy.", lines[0])

    def test_context_path_query_includes_evidence_prefix_matches(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Evidence prefix policy.",
            rationale="Directory evidence refs should surface for child paths.",
            supersedes=[],
            evidence_refs=["tools/"],
            affected_paths=[],
            author="tester",
            timestamp="2026-03-26T22:10:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=5,
            history_mode="relevant",
        )
        lines = self.history_lines(output, "Relevant History")
        self.assertEqual(1, len(lines))
        self.assertIn("Evidence prefix policy.", lines[0])

    def test_context_relevant_ranks_exact_path_above_subsystem_only(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_fact(
            paths,
            subsystem="architecture",
            status="current",
            fact="Architecture-wide memory guidance.",
            rationale="General architecture guidance.",
            supersedes=[],
            evidence_refs=["docs/codex_memory/README.md"],
            affected_paths=["docs/codex_memory/README.md"],
            author="tester",
            timestamp="2026-03-26T23:01:00Z",
        )
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Exact tool path policy.",
            rationale="The tool path is the most specific memory target.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:02:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=2,
            history_mode="relevant",
        )
        lines = self.history_lines(output, "Relevant History")
        self.assertEqual(2, len(lines))
        self.assertIn("Exact tool path policy.", lines[0])
        self.assertIn("Architecture-wide memory guidance.", lines[1])

    def test_context_relevant_downranks_architecture_doc_churn_for_code_path_queries(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        codex_memory.add_task_event(
            paths,
            stream="viewer-prep",
            status="completed",
            summary="Prompt churn.",
            next_actions=["Keep prompts narrow."],
            evidence_refs=["docs/PROMPT.md"],
            affected_paths=["docs/PROMPT.md"],
            author="tester",
            timestamp="2026-03-26T23:10:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="viewer-prep",
            status="completed",
            summary="Current focus churn.",
            next_actions=["Keep focus current."],
            evidence_refs=["docs/codex_memory/current_focus.md"],
            affected_paths=["docs/codex_memory/current_focus.md"],
            author="tester",
            timestamp="2026-03-26T23:11:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="viewer-prep",
            status="completed",
            summary="Tool contract landed.",
            next_actions=["Keep the tool contract explicit."],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:12:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=3,
            history_mode="relevant",
        )
        lines = self.history_lines(output, "Relevant History")
        self.assertEqual(3, len(lines))
        self.assertIn("Tool contract landed.", lines[0])
        self.assertNotIn("Prompt churn.", lines[0])
        self.assertNotIn("Current focus churn.", lines[0])

    def test_context_relevant_keeps_excluded_and_superseded_rules(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        old = codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="Old exact tool rule.",
            rationale="Older exact tool guidance.",
            supersedes=[],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:15:00Z",
        )
        codex_memory.add_policy(
            paths,
            topic="memory-workflow",
            status="accepted",
            statement="New exact tool rule.",
            rationale="Newer exact tool guidance.",
            supersedes=[old["record_id"]],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:16:00Z",
        )
        codex_memory.add_task_event(
            paths,
            stream="prompt-refresh",
            status="completed",
            summary="Prompt refresh touched the tool path.",
            next_actions=["Keep prompt refresh out of default pickup."],
            evidence_refs=["tools/codex_memory.py"],
            affected_paths=["tools/codex_memory.py"],
            author="tester",
            timestamp="2026-03-26T23:17:00Z",
        )
        output = codex_memory.render_context(
            paths,
            repo_paths=["tools/codex_memory.py"],
            include_history=5,
            history_mode="relevant",
        )
        self.assertIn("New exact tool rule.", output)
        self.assertNotIn("Old exact tool rule.", output)
        self.assertNotIn("Prompt refresh touched the tool path.", output)

    def test_add_each_record_type(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        ids = [
            codex_memory.add_policy(
                paths,
                topic="memory-workflow",
                status="accepted",
                statement="Use only the v2 memory tree.",
                rationale="The cutover removes v1 entirely.",
                supersedes=[],
                evidence_refs=["docs/codex_memory/README.md"],
                affected_paths=["docs/codex_memory/README.md"],
                author="tester",
                timestamp="2026-03-26T23:00:00Z",
            )["record_id"],
            codex_memory.add_fact(
                paths,
                subsystem="architecture",
                status="current",
                fact="Architecture facts live in subsystem packs plus typed history.",
                rationale="That keeps the always-loaded layer small.",
                supersedes=[],
                evidence_refs=["tools/codex_memory.py"],
                affected_paths=["tools/codex_memory.py"],
                author="tester",
                timestamp="2026-03-26T23:01:00Z",
            )["record_id"],
            codex_memory.add_investigation(
                paths,
                subsystem="life_scripts",
                status="blocked",
                question="How should unsupported switch-family opcodes be handled?",
                current_best_answer="Keep them outside the supported decoder until stronger source evidence appears.",
                confidence="high",
                next_probe="Revisit only if checked-in evidence or assets change.",
                evidence_refs=["port/src/game_data/scene/life_program.zig"],
                affected_paths=["port/src/game_data/scene/life_program.zig"],
                author="tester",
                timestamp="2026-03-26T23:02:00Z",
            )["record_id"],
            codex_memory.add_compat_event(
                paths,
                subsystem="architecture",
                status="removed",
                title="Retire v1 memory tree",
                summary="Removed handoff, mixed logs, and generated mirrors from the canonical design.",
                evidence_refs=["tools/codex_memory.py"],
                affected_paths=["tools/codex_memory.py"],
                author="tester",
                timestamp="2026-03-26T23:03:00Z",
            )["record_id"],
            codex_memory.add_task_event(
                paths,
                stream="memory-cutover",
                status="completed",
                summary="Completed the v2 memory cutover.",
                next_actions=["Use only the v2 commands."],
                evidence_refs=["docs/codex_memory/README.md"],
                affected_paths=["docs/codex_memory/README.md"],
                author="tester",
                timestamp="2026-03-26T23:04:00Z",
            )["record_id"],
        ]
        self.assertTrue(all(record_id for record_id in ids))
        self.assertEqual(codex_memory.validate_all(paths), [])

    def test_validate_rejects_oversized_focus(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths)
        huge = "# Current Focus\n\n" + "\n".join(
            [
                "## Current Priorities",
                "x" * 3500,
                "## Active Streams",
                "ok",
                "## Blocked Items",
                "ok",
                "## Next Actions",
                "ok",
                "## Relevant Subsystem Packs",
                "- architecture",
            ]
        )
        self.write(paths.docs_dir / "current_focus.md", huge)
        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("byte budget" in error for error in errors))

    def test_validate_rejects_ambiguous_mapping(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths, ambiguous=True)
        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("ambiguous mapping" in error for error in errors))

    def test_validate_rejects_missing_path_mapping(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths, missing_mapping=True)
        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("missing path mappings" in error for error in errors))

    def test_validate_rejects_obsolete_v1_paths(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths, obsolete=True)
        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("obsolete v1 path" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
