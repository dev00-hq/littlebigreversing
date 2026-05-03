from __future__ import annotations

from dataclasses import dataclass
import unittest

from tools import behavior_animation_root_motion_compare as compare


def linear_from_zero_for_test(target: int, elapsed: int, duration: int) -> int:
    if duration <= 0:
        return target
    return (target * elapsed) // duration


@dataclass(frozen=True)
class FakeKeyframe:
    duration: int
    root_3: int


@dataclass(frozen=True)
class FakeAnimation:
    keyframes: tuple[FakeKeyframe, ...]
    loop_start_keyframe: int


class BehaviorAnimationRootMotionCompareTests(unittest.TestCase):
    def test_root_motion_repeats_loop_segment_after_intro(self) -> None:
        animation = FakeAnimation(
            keyframes=(
                FakeKeyframe(duration=100, root_3=0),
                FakeKeyframe(duration=100, root_3=10),
                FakeKeyframe(duration=100, root_3=20),
            ),
            loop_start_keyframe=1,
        )

        self.assertEqual(
            0,
            compare.root_motion_z_at(animation, linear_from_zero_for_test, 50),
        )
        self.assertEqual(
            20,
            compare.root_motion_z_at(animation, linear_from_zero_for_test, 250),
        )
        self.assertEqual(
            60,
            compare.root_motion_z_at(animation, linear_from_zero_for_test, 500),
        )

    def test_first_nonzero_root_motion_ms_honors_intro_delay(self) -> None:
        animation = FakeAnimation(
            keyframes=(
                FakeKeyframe(duration=100, root_3=0),
                FakeKeyframe(duration=100, root_3=10),
            ),
            loop_start_keyframe=1,
        )

        self.assertEqual(
            110,
            compare.first_nonzero_root_motion_ms(
                animation,
                linear_from_zero_for_test,
                limit_ms=200,
            ),
        )


if __name__ == "__main__":
    unittest.main()
