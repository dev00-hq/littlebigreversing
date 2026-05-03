from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ASSET_ROOT = (
    REPO_ROOT
    / "work"
    / "_innoextract_full"
    / "Speedrun"
    / "Windows"
    / "LBA2_cdrom"
    / "LBA2"
)
DEFAULT_LM2_VIEWER_ROOT = Path(r"D:\repos\reverse\lba2-lm2-viewer")
DEFAULT_FIXTURE = (
    REPO_ROOT
    / "tools"
    / "fixtures"
    / "promotion_packets"
    / "phase5_behavior_movement_speed_startup_otringal_live_positive.json"
)
DEFAULT_OUT = (
    REPO_ROOT
    / "work"
    / "behavior_animation_root_motion_compare"
    / "summary.json"
)


class RootMotionCompareError(Exception):
    pass


@dataclass(frozen=True)
class CandidateAnimation:
    mode: str
    comportement: int
    asset_id: str
    file3d_object: int


CANDIDATE_ANIMATIONS = (
    CandidateAnimation("normal", 0, "ANIM.HQR:1", 0),
    CandidateAnimation("sporty", 1, "ANIM.HQR:67", 1),
    CandidateAnimation("aggressive", 2, "ANIM.HQR:83", 2),
    CandidateAnimation("discreet", 3, "ANIM.HQR:94", 3),
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def import_lm2_viewer(lm2_viewer_root: Path) -> tuple[Any, Any]:
    if not lm2_viewer_root.exists():
        raise RootMotionCompareError(f"LM2 viewer repo not found: {lm2_viewer_root}")
    sys.path.insert(0, str(lm2_viewer_root))
    try:
        from lba2_lm2_viewer import viewer
        from lba2_lm2_viewer.animation import linear_from_zero, parse_lba2_animation_records
    except Exception as error:  # pragma: no cover - depends on adjacent repo
        raise RootMotionCompareError(f"could not import LM2 viewer modules: {error}") from error
    return viewer, {
        "linear_from_zero": linear_from_zero,
        "parse_lba2_animation_records": parse_lba2_animation_records,
    }


def live_profiles(fixture_path: Path) -> dict[str, dict[str, Any]]:
    fixture = read_json(fixture_path)
    profiles = fixture.get("runtime_contract", {}).get("profiles", [])
    if not isinstance(profiles, list):
        raise RootMotionCompareError("fixture runtime_contract.profiles is missing")
    by_mode: dict[str, dict[str, Any]] = {}
    for profile in profiles:
        if not isinstance(profile, dict) or not isinstance(profile.get("mode"), str):
            continue
        by_mode[profile["mode"]] = profile
    missing = [candidate.mode for candidate in CANDIDATE_ANIMATIONS if candidate.mode not in by_mode]
    if missing:
        raise RootMotionCompareError(f"fixture missing live profiles: {', '.join(missing)}")
    return by_mode


def root_motion_z_at(animation: Any, linear_from_zero: Any, t_ms: int) -> int:
    z = 0
    remaining = t_ms
    for keyframe in animation.keyframes:
        if remaining <= 0:
            return z
        if remaining < keyframe.duration:
            return z + linear_from_zero(keyframe.root_3, remaining, keyframe.duration)
        z += keyframe.root_3
        remaining -= keyframe.duration

    loop_keyframes = animation.keyframes[animation.loop_start_keyframe :]
    loop_duration = sum(keyframe.duration for keyframe in loop_keyframes)
    loop_z = sum(keyframe.root_3 for keyframe in loop_keyframes)
    if loop_duration <= 0:
        return z

    cycles, remaining = divmod(remaining, loop_duration)
    z += cycles * loop_z
    for keyframe in loop_keyframes:
        if remaining <= 0:
            return z
        if remaining < keyframe.duration:
            return z + linear_from_zero(keyframe.root_3, remaining, keyframe.duration)
        z += keyframe.root_3
        remaining -= keyframe.duration
    return z


def first_nonzero_root_motion_ms(animation: Any, linear_from_zero: Any, limit_ms: int = 1000) -> int | None:
    for t_ms in range(limit_ms + 1):
        if root_motion_z_at(animation, linear_from_zero, t_ms) != 0:
            return t_ms
    return None


def compare_root_motion(
    *,
    asset_root: Path,
    lm2_viewer_root: Path,
    fixture_path: Path,
    hold_ms: int,
    sample_ms: tuple[int, ...],
) -> dict[str, Any]:
    viewer, animation_api = import_lm2_viewer(lm2_viewer_root)
    linear_from_zero = animation_api["linear_from_zero"]
    parse_lba2_animation_records = animation_api["parse_lba2_animation_records"]

    if not asset_root.exists():
        raise RootMotionCompareError(f"asset root not found: {asset_root}")

    catalog = viewer.build_catalog(asset_root)
    assets = {asset["id"]: asset for asset in catalog.get("assets", []) if isinstance(asset, dict) and "id" in asset}
    live_by_mode = live_profiles(fixture_path)
    rows = []
    for candidate in CANDIDATE_ANIMATIONS:
        asset = assets.get(candidate.asset_id)
        if asset is None:
            raise RootMotionCompareError(f"catalog asset not found: {candidate.asset_id}")
        payload, _resource = viewer.read_hqr_payload(asset_root, asset["source"])
        animation = parse_lba2_animation_records(payload)
        live = live_by_mode[candidate.mode]
        decoded_z = root_motion_z_at(animation, linear_from_zero, hold_ms)
        live_z = int(live["final_dz"])
        decoded_first = first_nonzero_root_motion_ms(animation, linear_from_zero)
        live_first = int(live["first_movement_ms"])
        metadata = asset.get("animation_metadata") or {}
        rows.append(
            {
                "mode": candidate.mode,
                "comportement": candidate.comportement,
                "animation_asset": candidate.asset_id,
                "file3d_object": candidate.file3d_object,
                "metadata": {
                    "generic_ids": metadata.get("generic_ids"),
                    "generic_names": metadata.get("generic_names"),
                    "labels": metadata.get("labels"),
                    "file3d_objects": metadata.get("file3d_objects"),
                    "compatible_body_ids": metadata.get("compatible_body_ids"),
                },
                "decoded_animation": {
                    "keyframes": animation.keyframe_count,
                    "bone_count": animation.bone_count,
                    "loop_start_keyframe": animation.loop_start_keyframe,
                    "total_duration_ms": sum(keyframe.duration for keyframe in animation.keyframes),
                    "loop_duration_ms": sum(
                        keyframe.duration for keyframe in animation.keyframes[animation.loop_start_keyframe :]
                    ),
                    "root_z_at_hold_ms": decoded_z,
                    "first_nonzero_root_z_ms": decoded_first,
                    "samples": [
                        {"t_ms": t_ms, "root_z": root_motion_z_at(animation, linear_from_zero, t_ms)}
                        for t_ms in sample_ms
                    ],
                },
                "live_otringal": {
                    "hold_ms": hold_ms,
                    "first_movement_ms": live_first,
                    "final_dz": live_z,
                },
                "comparison": {
                    "final_dz_delta_decoded_minus_live": decoded_z - live_z,
                    "final_dz_abs_error": abs(decoded_z - live_z),
                    "final_dz_abs_error_ratio": abs(decoded_z - live_z) / max(1, abs(live_z)),
                    "first_motion_delta_decoded_minus_live_ms": None
                    if decoded_first is None
                    else decoded_first - live_first,
                },
            }
        )

    max_error_ratio = max(row["comparison"]["final_dz_abs_error_ratio"] for row in rows)
    return {
        "schema": "behavior-animation-root-motion-compare-v1",
        "asset_root": str(asset_root),
        "lm2_viewer_root": str(lm2_viewer_root),
        "fixture": str(fixture_path),
        "hold_ms": hold_ms,
        "candidate_mapping_hypothesis": (
            "File3D objects 0, 1, 2, and 3 correspond to Normal, Sporty, "
            "Aggressive, and Discreet Twinsen behavior walk families."
        ),
        "rows": rows,
        "summary": {
            "max_final_dz_abs_error_ratio": max_error_ratio,
            "verdict": "supports_animation_root_motion_hypothesis"
            if max_error_ratio <= 0.03
            else "does_not_support_animation_root_motion_hypothesis",
            "limitation": (
                "Decoded ANIM root motion matching live movement is strong correlation, "
                "not proof that the original runtime commits root deltas directly."
            ),
        },
    }


def parse_sample_ms(values: str) -> tuple[int, ...]:
    parsed = []
    for value in values.split(","):
        value = value.strip()
        if not value:
            continue
        parsed.append(int(value))
    if not parsed:
        raise argparse.ArgumentTypeError("sample list must not be empty")
    return tuple(parsed)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compare Otringal live behavior movement with decoded Twinsen ANIM root motion."
    )
    parser.add_argument("--asset-root", type=Path, default=DEFAULT_ASSET_ROOT)
    parser.add_argument("--lm2-viewer-root", type=Path, default=DEFAULT_LM2_VIEWER_ROOT)
    parser.add_argument("--fixture", type=Path, default=DEFAULT_FIXTURE)
    parser.add_argument("--hold-ms", type=int, default=2000)
    parser.add_argument("--sample-ms", type=parse_sample_ms, default=parse_sample_ms("500,1000,1500,2000"))
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    try:
        payload = compare_root_motion(
            asset_root=args.asset_root,
            lm2_viewer_root=args.lm2_viewer_root,
            fixture_path=args.fixture,
            hold_ms=args.hold_ms,
            sample_ms=args.sample_ms,
        )
        write_json(args.out, payload)
    except Exception as error:
        if args.json:
            print(json.dumps({"schema": "behavior-animation-root-motion-compare-v1", "verdict": "error", "error": str(error)}, indent=2))
        else:
            print(f"behavior animation root-motion compare failed: {error}")
        return 1

    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print(f"wrote {args.out}")
        print(f"verdict: {payload['summary']['verdict']}")
        for row in payload["rows"]:
            comparison = row["comparison"]
            print(
                f"{row['mode']}: {row['animation_asset']} decoded-live dz "
                f"{comparison['final_dz_delta_decoded_minus_live']} "
                f"({comparison['final_dz_abs_error_ratio']:.3%})"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
