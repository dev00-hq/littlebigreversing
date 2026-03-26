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

    def scaffold(self, paths: codex_memory.MemoryPaths, *, ambiguous: bool = False, obsolete: bool = False) -> None:
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
- `platform_linux`: `scripts/linux-notes.md`
- `architecture`: `AGENTS.md`, `tools/codex_memory.py`
""",
        )
        for name in codex_memory.EXPECTED_SUBSYSTEMS:
            self.write(paths.subsystem_path(name), self.pack_doc(name.title()))
        for filename in codex_memory.HISTORY_FILES:
            self.write(paths.history_path(filename), "")

        self.write(paths.repo_root / "AGENTS.md", "# agents\n")
        self.write(paths.repo_root / "tools" / "codex_memory.py", "# tool\n")
        self.write(paths.repo_root / "scripts" / "check-env.ps1", "# windows\n")
        self.write(paths.repo_root / "scripts" / "linux-notes.md", "# linux\n")
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

    def test_validate_rejects_obsolete_v1_paths(self) -> None:
        paths = self.make_paths()
        self.scaffold(paths, obsolete=True)
        errors = codex_memory.validate_all(paths)
        self.assertTrue(any("obsolete v1 path" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
