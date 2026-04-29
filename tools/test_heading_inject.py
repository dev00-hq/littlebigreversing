from __future__ import annotations

from pathlib import Path
import sys
import unittest


LIFE_TRACE_PATH = Path(__file__).resolve().parent / "life_trace"
sys.path.insert(0, str(LIFE_TRACE_PATH))

import heading_inject  # noqa: E402


class FakeExports:
    def __init__(self) -> None:
        self.applyteleport_calls: list[tuple[int, int, int, bool, bool]] = []

    def applyteleport(
        self,
        target_x: int,
        target_y: int,
        target_z: int,
        sync_old_position: bool,
        sync_candidate_position: bool,
    ) -> dict[str, object]:
        self.applyteleport_calls.append(
            (target_x, target_y, target_z, sync_old_position, sync_candidate_position)
        )
        return {
            "beta": 0,
            "x": target_x,
            "y": target_y,
            "z": target_z,
        }


class FakeScript:
    def __init__(self) -> None:
        self.exports_sync = FakeExports()


class DisconnectedHeadingInjector(heading_inject.HeadingInjector):
    def __init__(self) -> None:
        super().__init__()
        self._script = FakeScript()

    def connect(self) -> None:
        return None


class HeadingInjectTests(unittest.TestCase):
    def test_teleport_keeps_candidate_sync_disabled_by_default(self) -> None:
        injector = DisconnectedHeadingInjector()

        result = injector.teleport_xyz(10, 20, 30)

        self.assertEqual(
            [(10, 20, 30, True, False)],
            injector._script.exports_sync.applyteleport_calls,
        )
        self.assertFalse(result["sync_candidate_position"])
        self.assertEqual({"x": 0, "y": 0, "z": 0}, result["final_delta_position"])

    def test_teleport_can_sync_candidate_position_globals(self) -> None:
        injector = DisconnectedHeadingInjector()

        result = injector.teleport_xyz(
            10,
            20,
            30,
            sync_old_position=False,
            sync_candidate_position=True,
        )

        self.assertEqual(
            [(10, 20, 30, False, True)],
            injector._script.exports_sync.applyteleport_calls,
        )
        self.assertTrue(result["sync_candidate_position"])
        self.assertFalse(result["sync_old_position"])

    def test_agent_script_writes_candidate_globals_only_when_requested(self) -> None:
        script = heading_inject.build_script()

        self.assertIn("candidateX: absAddr('0x0049a0a8')", script)
        self.assertIn("candidateY: absAddr('0x0049a0ac')", script)
        self.assertIn("candidateZ: absAddr('0x0049a0b0')", script)
        self.assertIn("if (syncCandidatePosition)", script)
        self.assertIn("ADDR.candidateX.writeS32(targetX)", script)
        self.assertIn("applyteleport(targetX, targetY, targetZ, syncOldPosition, syncCandidatePosition)", script)


if __name__ == "__main__":
    unittest.main()
