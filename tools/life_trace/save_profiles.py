from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PROFILES_PATH = REPO_ROOT / "work" / "saves" / "save_profiles.json"
REQUIRED_TOP_LEVEL_KEYS = ("schema_version", "purpose", "profiles")
REQUIRED_PROFILE_KEYS = (
    "profile_id",
    "scene_name",
    "scene_id",
    "raw_scene_entry_index",
    "proof_goal",
    "generation_spec",
    "visual_verification",
    "operator_generation_instructions",
)
REQUIRED_GENERATION_SPEC_KEYS = (
    "story_arc",
    "story_prerequisites",
    "hero_state",
    "room_requirement",
    "interaction_boundary",
    "record_with_save",
)
REQUIRED_VISUAL_VERIFICATION_KEYS = (
    "validation_method",
    "screenshot_step",
    "expected_visual_cues",
    "mismatch_examples",
)


def resolve_profiles_path(path_text: str | None) -> Path:
    candidate = Path(path_text).resolve() if path_text else DEFAULT_PROFILES_PATH
    if not candidate.exists():
        raise RuntimeError(f"save profile manifest does not exist: {candidate}")
    return candidate


def load_profiles_payload(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"save profile manifest is not valid JSON: {path}") from exc
    if not isinstance(payload, dict):
        raise RuntimeError(f"save profile manifest must be a JSON object: {path}")
    return payload


def validate_profiles_payload(payload: dict[str, Any], path: Path) -> None:
    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in payload:
            raise RuntimeError(f"save profile manifest is missing top-level key '{key}': {path}")
    if payload["schema_version"] != "lba2-save-profiles-v3":
        raise RuntimeError(
            "save profile manifest has unsupported schema_version "
            f"{payload['schema_version']!r}: {path}"
        )
    if not isinstance(payload["profiles"], list) or not payload["profiles"]:
        raise RuntimeError(f"save profile manifest must contain a non-empty profiles list: {path}")

    seen_ids: set[str] = set()
    for index, profile in enumerate(payload["profiles"], start=1):
        label = f"profile #{index}"
        if not isinstance(profile, dict):
            raise RuntimeError(f"{label} is not a JSON object: {path}")
        for key in REQUIRED_PROFILE_KEYS:
            if key not in profile:
                raise RuntimeError(f"{label} is missing required key '{key}': {path}")
        profile_id = profile["profile_id"]
        if not isinstance(profile_id, str) or not profile_id.strip():
            raise RuntimeError(f"{label} has an invalid profile_id: {path}")
        if profile_id in seen_ids:
            raise RuntimeError(f"duplicate save profile id '{profile_id}': {path}")
        seen_ids.add(profile_id)

        generation_spec = profile["generation_spec"]
        if not isinstance(generation_spec, dict):
            raise RuntimeError(f"{label} generation_spec must be an object: {path}")
        for key in REQUIRED_GENERATION_SPEC_KEYS:
            if key not in generation_spec:
                raise RuntimeError(
                    f"{label} generation_spec is missing required key '{key}': {path}"
                )
        visual_verification = profile["visual_verification"]
        if not isinstance(visual_verification, dict):
            raise RuntimeError(f"{label} visual_verification must be an object: {path}")
        for key in REQUIRED_VISUAL_VERIFICATION_KEYS:
            if key not in visual_verification:
                raise RuntimeError(
                    f"{label} visual_verification is missing required key '{key}': {path}"
                )
        operator_steps = profile["operator_generation_instructions"]
        if not isinstance(operator_steps, list) or not operator_steps:
            raise RuntimeError(
                f"{label} operator_generation_instructions must be a non-empty list: {path}"
            )


def load_profiles(path: Path) -> dict[str, Any]:
    payload = load_profiles_payload(path)
    validate_profiles_payload(payload, path)
    return payload


def find_profile(payload: dict[str, Any], profile_id: str) -> dict[str, Any]:
    for profile in payload["profiles"]:
        if profile["profile_id"] == profile_id:
            return profile
    raise RuntimeError(f"unknown save profile '{profile_id}'")


def render_profiles_list_text(payload: dict[str, Any]) -> str:
    lines = []
    for profile in payload["profiles"]:
        lines.append(f"{profile['profile_id']}: {profile['proof_goal']}")
    return "\n".join(lines) + "\n"


def render_profile_text(profile: dict[str, Any]) -> str:
    generation_spec = profile["generation_spec"]
    visual_verification = profile["visual_verification"]
    lines = [
        f"profile_id: {profile['profile_id']}",
        f"scene: {profile['scene_name']} (scene_id={profile['scene_id']}, raw_entry={profile['raw_scene_entry_index']})",
        f"proof_goal: {profile['proof_goal']}",
        f"story_arc: {generation_spec['story_arc']}",
        f"room_requirement: {generation_spec['room_requirement']}",
        "story_prerequisites:",
    ]
    lines.extend(f"- {value}" for value in generation_spec["story_prerequisites"])
    lines.append("hero_state:")
    lines.extend(f"- {value}" for value in generation_spec["hero_state"])
    lines.append(f"interaction_boundary: {generation_spec['interaction_boundary']}")
    lines.append("record_with_save:")
    lines.extend(f"- {value}" for value in generation_spec["record_with_save"])
    lines.append(f"visual_validation_method: {visual_verification['validation_method']}")
    lines.append(f"visual_screenshot_step: {visual_verification['screenshot_step']}")
    lines.append("expected_visual_cues:")
    lines.extend(f"- {value}" for value in visual_verification["expected_visual_cues"])
    lines.append("mismatch_examples:")
    lines.extend(f"- {value}" for value in visual_verification["mismatch_examples"])
    lines.append("operator_generation_instructions:")
    lines.extend(f"- {value}" for value in profile["operator_generation_instructions"])
    known_examples = profile.get("known_example_saves") or []
    if known_examples:
        lines.append("known_example_saves:")
        lines.extend(f"- {value}" for value in known_examples)
    return "\n".join(lines) + "\n"


def write_output(text: str, output_path_text: str | None) -> None:
    if output_path_text:
        output_path = Path(output_path_text).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Inspect and validate the canonical generation-oriented save profiles."
    )
    parser.add_argument(
        "--profiles",
        help=(
            "Optional path to save_profiles.json. "
            "Defaults to work/saves/save_profiles.json in the repo root."
        ),
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List canonical save profile ids.")
    list_parser.add_argument("--json", action="store_true", help="Render the full profile list as JSON.")
    list_parser.add_argument("--output", help="Optional path for rendered output.")

    show_parser = subparsers.add_parser("show", help="Show one canonical save profile.")
    show_parser.add_argument("profile_id", help="Save profile id to render.")
    show_parser.add_argument("--json", action="store_true", help="Render the selected profile as JSON.")
    show_parser.add_argument("--output", help="Optional path for rendered output.")

    validate_parser = subparsers.add_parser("validate", help="Validate the save profile manifest.")
    validate_parser.add_argument("--json", action="store_true", help="Render validation status as JSON.")
    validate_parser.add_argument("--output", help="Optional path for rendered output.")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    profiles_path = resolve_profiles_path(args.profiles)
    payload = load_profiles(profiles_path)

    if args.command == "list":
        rendered = (
            json.dumps(payload["profiles"], ensure_ascii=True, indent=2, sort_keys=True) + "\n"
            if args.json
            else render_profiles_list_text(payload)
        )
        write_output(rendered, args.output)
        return 0

    if args.command == "show":
        profile = find_profile(payload, args.profile_id)
        rendered = (
            json.dumps(profile, ensure_ascii=True, indent=2, sort_keys=True) + "\n"
            if args.json
            else render_profile_text(profile)
        )
        write_output(rendered, args.output)
        return 0

    if args.command == "validate":
        rendered = (
            json.dumps(
                {
                    "schema_version": payload["schema_version"],
                    "status": "ok",
                    "profiles_path": str(profiles_path),
                    "profile_count": len(payload["profiles"]),
                },
                ensure_ascii=True,
                indent=2,
                sort_keys=True,
            )
            + "\n"
            if args.json
            else "ok\n"
        )
        write_output(rendered, args.output)
        return 0

    raise RuntimeError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
