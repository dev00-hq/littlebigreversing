from __future__ import annotations

from pathlib import Path
import unittest


SOURCE_PATH = (
    Path(__file__).resolve().parent
    / "runtime_shims"
    / "lba2_winmm_proxy"
    / "winmm_proxy.c"
)
README_PATH = SOURCE_PATH.with_name("README.md")


class RuntimeShimLifeWatchTests(unittest.TestCase):
    def test_proxy_watch_uses_canonical_clover_counter(self) -> None:
        source = SOURCE_PATH.read_text(encoding="utf-8")

        self.assertIn("#define LBA2_FLAG_CLOVER 251", source)
        self.assertIn("#define LBA2_CLOVER_COUNTER 0x0049A08E", source)
        self.assertIn('read_i16_addr(LBA2_CLOVER_COUNTER', source)
        self.assertIn('\\"counter\\":\\"ListVarGame[FLAG_CLOVER]\\"', source)

    def test_proxy_watch_is_opt_in_and_writes_life_loss_events(self) -> None:
        source = SOURCE_PATH.read_text(encoding="utf-8")

        self.assertIn('env_truthy("LBA2_RUNTIME_WATCH")', source)
        self.assertIn("#define LBA2_RUNTIME_WATCH_LOG \"lba2_runtime_watch.log\"", source)
        self.assertIn('"life_loss_detected"', source)
        self.assertIn("current < previous", source)
        self.assertIn("CreateThread(NULL, 0, runtime_watch_main", source)

    def test_readme_documents_no_debugger_watch_lane(self) -> None:
        readme = README_PATH.read_text(encoding="utf-8")

        self.assertIn("LBA2_RUNTIME_WATCH=1", readme)
        self.assertIn("life_loss_detected", readme)
        self.assertIn("0x0049A08E", readme)
        self.assertIn("canonical no-debugger life-loss detector", readme)


if __name__ == "__main__":
    unittest.main()
