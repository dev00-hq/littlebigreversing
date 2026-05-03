from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CHECKPOINT_ROOT = REPO_ROOT / "tools" / "fixtures" / "game_drive_checkpoints"
VISUAL_RESULT_SCHEMA_PATH = (
    REPO_ROOT / "tools" / "fixtures" / "game_drive_visual_results" / "schema.json"
)
SCHEMA = "game-drive-checkpoint-v1"
VISUAL_RESULT_SCHEMA = "game-drive-visual-classification-v1"
AUTOSAVE_GUARDS = {"hide_active_autosave_preserve_generated"}
POSE_METHODS = {"existing_pose", "direct_pose", "teleport", "heading_input"}
DIRECT_POSE_METHODS = {"direct_pose", "teleport"}
CLASSIFIERS = {"codex_exec"}
VISUAL_SOURCES = {"live_window_capture"}
CONFIDENCE_VALUES = {"low", "medium", "high"}
UI_STATES = {"gameplay", "dialog", "menu", "unknown"}


class GameDriveCheckpointError(Exception):
    pass


def repo_path(raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        raise GameDriveCheckpointError(f"path must be repo-relative: {raw}")
    if ".." in path.parts:
        raise GameDriveCheckpointError(f"path must not escape repo root: {raw}")
    return REPO_ROOT / path


def repo_relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def require_dict(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise GameDriveCheckpointError(f"missing object: {key}")
    return value


def require_string(parent: dict[str, Any], key: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value:
        raise GameDriveCheckpointError(f"missing non-empty string: {key}")
    return value


def require_bool(parent: dict[str, Any], key: str) -> bool:
    value = parent.get(key)
    if not isinstance(value, bool):
        raise GameDriveCheckpointError(f"missing boolean: {key}")
    return value


def require_int(parent: dict[str, Any], key: str) -> int:
    value = parent.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise GameDriveCheckpointError(f"missing integer: {key}")
    return value


def optional_int(parent: dict[str, Any], key: str) -> int | None:
    value = parent.get(key)
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        raise GameDriveCheckpointError(f"{key} must be an integer")
    return value


def require_string_list(parent: dict[str, Any], key: str) -> list[str]:
    value = parent.get(key)
    if not isinstance(value, list):
        raise GameDriveCheckpointError(f"missing string list: {key}")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise GameDriveCheckpointError(f"{key} entries must be non-empty strings")
        result.append(item)
    return result


def optional_string(parent: dict[str, Any], key: str) -> str | None:
    value = parent.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise GameDriveCheckpointError(f"{key} must be a non-empty string")
    return value


def optional_string_list(parent: dict[str, Any], key: str) -> list[str]:
    value = parent.get(key)
    if value is None:
        return []
    if not isinstance(value, list):
        raise GameDriveCheckpointError(f"{key} must be a string list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise GameDriveCheckpointError(f"{key} entries must be non-empty strings")
        result.append(item)
    return result


def load_json_file(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise GameDriveCheckpointError(f"file does not exist: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise GameDriveCheckpointError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise GameDriveCheckpointError(f"JSON file must contain an object: {path}")
    return value


def load_checkpoint(path: Path) -> dict[str, Any]:
    checkpoint = load_json_file(path)
    if checkpoint.get("schema") != SCHEMA:
        raise GameDriveCheckpointError(f"{path}: schema must be {SCHEMA}")
    return checkpoint


def validate_pose(checkpoint_id: str, setup: dict[str, Any]) -> dict[str, Any]:
    pose = require_dict(setup, "pose")
    method = require_string(pose, "method")
    if method not in POSE_METHODS:
        raise GameDriveCheckpointError(f"{checkpoint_id}: unsupported pose method {method}")
    scene = require_int(pose, "scene")
    background = optional_int(pose, "background")
    active_cube = optional_int(pose, "active_cube")
    coordinates = require_dict(pose, "coordinates")
    x = require_int(coordinates, "x")
    y = require_int(coordinates, "y")
    z = require_int(coordinates, "z")
    beta = require_int(coordinates, "beta")
    tolerance = require_dict(pose, "tolerance")
    position_tolerance = require_int(tolerance, "position")
    beta_tolerance = require_int(tolerance, "beta")
    if position_tolerance < 0 or beta_tolerance < 0:
        raise GameDriveCheckpointError(f"{checkpoint_id}: pose tolerances must be non-negative")
    safe_source = require_string(pose, "safe_source")
    if method in DIRECT_POSE_METHODS and not safe_source:
        raise GameDriveCheckpointError(f"{checkpoint_id}: direct pose methods require safe_source")
    return {
        "method": method,
        "scene": scene,
        "background": background,
        "active_cube": active_cube,
        "coordinates": {"x": x, "y": y, "z": z, "beta": beta},
        "tolerance": {"position": position_tolerance, "beta": beta_tolerance},
        "safe_source": safe_source,
    }


def validate_visual_expect(checkpoint_id: str, visual: dict[str, Any], *, direct_pose: bool) -> dict[str, Any]:
    checkpoint_name = require_string(visual, "checkpoint")
    source = require_string(visual, "source")
    if source not in VISUAL_SOURCES:
        raise GameDriveCheckpointError(f"{checkpoint_id}: unsupported visual source {source}")
    classifier = require_string(visual, "classifier")
    if classifier not in CLASSIFIERS:
        raise GameDriveCheckpointError(f"{checkpoint_id}: unsupported visual classifier {classifier}")
    if not require_bool(visual, "summary_required"):
        raise GameDriveCheckpointError(f"{checkpoint_id}: visual summary must be required")
    screenshot_required = require_bool(visual, "screenshot_required")
    if direct_pose and not screenshot_required:
        raise GameDriveCheckpointError(f"{checkpoint_id}: direct pose requires screenshot_required=true")
    expected = require_dict(visual, "expected")
    require_bool(expected, "twinsen_visible")
    require_bool(expected, "target_visible")
    ui_state = require_string(expected, "ui_state")
    if ui_state not in UI_STATES:
        raise GameDriveCheckpointError(f"{checkpoint_id}: unsupported expected ui_state {ui_state}")
    require_bool(expected, "unsafe_pose_signs")
    summary_must_mention = require_string_list(visual, "summary_must_mention")
    if direct_pose and not summary_must_mention:
        raise GameDriveCheckpointError(f"{checkpoint_id}: direct pose requires summary_must_mention")
    negative_controls = visual.get("negative_controls")
    if direct_pose:
        if not isinstance(negative_controls, list) or not negative_controls:
            raise GameDriveCheckpointError(f"{checkpoint_id}: direct pose requires negative visual controls")
        for index, control in enumerate(negative_controls):
            if not isinstance(control, dict):
                raise GameDriveCheckpointError(f"{checkpoint_id}: negative control {index} must be an object")
            require_string(control, "id")
            require_string(control, "description")
            if require_bool(control, "expected_matches") is not False:
                raise GameDriveCheckpointError(f"{checkpoint_id}: negative controls must expect matches=false")
    return {
        "checkpoint": checkpoint_name,
        "source": source,
        "classifier": classifier,
        "screenshot_required": screenshot_required,
        "summary_required": True,
        "scene_description": optional_string(visual, "scene_description"),
        "target_description": optional_string(visual, "target_description"),
        "expected": expected,
        "summary_must_mention": summary_must_mention,
        "negative_controls": negative_controls or [],
    }


def validate_runtime_expect(checkpoint_id: str, runtime: dict[str, Any], pose: dict[str, Any]) -> dict[str, Any]:
    if not require_bool(runtime, "life_not_lost"):
        raise GameDriveCheckpointError(f"{checkpoint_id}: runtime expectation must require life_not_lost")
    if require_int(runtime, "scene") != pose["scene"]:
        raise GameDriveCheckpointError(f"{checkpoint_id}: runtime scene must match pose scene")
    background = runtime.get("background")
    if background is not None and background != pose["background"]:
        raise GameDriveCheckpointError(f"{checkpoint_id}: runtime background must match pose background")
    active_cube = runtime.get("active_cube")
    if active_cube is not None and active_cube != pose["active_cube"]:
        raise GameDriveCheckpointError(f"{checkpoint_id}: runtime active_cube must match pose active_cube")
    return runtime


def validate_checkpoint(path: Path) -> dict[str, Any]:
    checkpoint = load_checkpoint(path)
    checkpoint_id = require_string(checkpoint, "id")
    save = require_string(checkpoint, "save")
    autosave_guard = require_string(checkpoint, "autosave_guard")
    if autosave_guard not in AUTOSAVE_GUARDS:
        raise GameDriveCheckpointError(f"{checkpoint_id}: unsupported autosave guard {autosave_guard}")

    setup = require_dict(checkpoint, "setup")
    pose = validate_pose(checkpoint_id, setup)
    direct_pose = pose["method"] in DIRECT_POSE_METHODS
    runtime_expect = validate_runtime_expect(checkpoint_id, require_dict(checkpoint, "runtime_expect"), pose)
    visual_expect = validate_visual_expect(
        checkpoint_id,
        require_dict(checkpoint, "visual_expect"),
        direct_pose=direct_pose,
    )
    actions_after_checkpoint = optional_string_list(checkpoint, "actions_after_checkpoint")
    if direct_pose and actions_after_checkpoint:
        gate = ["capture_screenshot", "codex_exec_visual_classification"]
    else:
        gate = []
    return {
        "id": checkpoint_id,
        "save": save,
        "autosave_guard": autosave_guard,
        "pose": pose,
        "runtime_expect": runtime_expect,
        "visual_expect": visual_expect,
        "actions_after_checkpoint": actions_after_checkpoint,
        "action_gate": gate,
    }


def iter_checkpoint_paths(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    if not root.is_dir():
        raise GameDriveCheckpointError(f"checkpoint path does not exist: {root}")
    return sorted(root.glob("*.json"))


def validate_all(root: Path = DEFAULT_CHECKPOINT_ROOT) -> list[dict[str, Any]]:
    paths = iter_checkpoint_paths(root)
    if not paths:
        raise GameDriveCheckpointError(f"no checkpoint files found under {root}")
    return [validate_checkpoint(path) for path in paths]


def build_visual_prompt(checkpoint: dict[str, Any], screenshot_path: str) -> dict[str, Any]:
    validated = validate_checkpoint(repo_path(checkpoint["checkpoint_file"])) if "checkpoint_file" in checkpoint else checkpoint
    visual = validated["visual_expect"]
    prompt_text = (
        "Classify this LBA2 game screenshot against the expected checkpoint. "
        "Return strict JSON only. The checkpoint_id field must exactly equal the supplied checkpoint_id. "
        "Include a non-empty summary that justifies every boolean field.\n\n"
        + json.dumps(
            {
                "checkpoint_id": validated["id"],
                "scene_description": visual.get("scene_description"),
                "target_description": visual.get("target_description"),
                "expected": visual["expected"],
                "summary_must_mention": visual["summary_must_mention"],
                "response_schema": VISUAL_RESULT_SCHEMA,
            },
            indent=2,
        )
    )
    return {
        "schema": "game-drive-visual-prompt-v1",
        "checkpoint_id": validated["id"],
        "screenshot": screenshot_path,
        "instruction": prompt_text,
        "codex_exec": {
            "argv": [
                "codex",
                "exec",
                "--image",
                screenshot_path,
                "--output-schema",
                repo_relative(VISUAL_RESULT_SCHEMA_PATH),
                "-",
            ],
            "stdin": prompt_text,
        },
        "required_response_schema": VISUAL_RESULT_SCHEMA,
        "expected": visual["expected"],
        "summary_must_mention": visual["summary_must_mention"],
        "response_shape": {
            "schema": VISUAL_RESULT_SCHEMA,
            "checkpoint_id": validated["id"],
            "matches": "boolean",
            "confidence": "low|medium|high",
            "summary": "non-empty visual justification",
            "observed": {
                "twinsen_visible": "boolean",
                "target_visible": "boolean",
                "ui_state": "gameplay|dialog|menu|unknown",
                "unsafe_pose_signs": "boolean",
            },
            "mismatches": ["strings"],
        },
    }


def validate_visual_result(checkpoint_path: Path, result_path: Path) -> dict[str, Any]:
    checkpoint = validate_checkpoint(checkpoint_path)
    result = load_json_file(result_path)
    if result.get("schema") != VISUAL_RESULT_SCHEMA:
        raise GameDriveCheckpointError(f"{result_path}: schema must be {VISUAL_RESULT_SCHEMA}")
    if result.get("checkpoint_id") != checkpoint["id"]:
        raise GameDriveCheckpointError("visual result checkpoint_id mismatch")
    matches = result.get("matches")
    if not isinstance(matches, bool):
        raise GameDriveCheckpointError("visual result matches must be boolean")
    confidence = require_string(result, "confidence")
    if confidence not in CONFIDENCE_VALUES:
        raise GameDriveCheckpointError(f"unsupported visual confidence {confidence}")
    summary = require_string(result, "summary")
    for required in checkpoint["visual_expect"]["summary_must_mention"]:
        if required.lower() not in summary.lower():
            raise GameDriveCheckpointError(f"visual summary must mention {required}")
    observed = require_dict(result, "observed")
    expected = checkpoint["visual_expect"]["expected"]
    mismatches: list[str] = []
    for key in ("twinsen_visible", "target_visible", "unsafe_pose_signs"):
        if require_bool(observed, key) != expected[key]:
            mismatches.append(key)
    ui_state = require_string(observed, "ui_state")
    if ui_state not in UI_STATES:
        raise GameDriveCheckpointError(f"unsupported observed ui_state {ui_state}")
    if ui_state != expected["ui_state"]:
        mismatches.append("ui_state")
    result_mismatches = result.get("mismatches")
    if not isinstance(result_mismatches, list):
        raise GameDriveCheckpointError("visual result mismatches must be a list")
    for item in result_mismatches:
        if not isinstance(item, str):
            raise GameDriveCheckpointError("visual result mismatch entries must be strings")
    expected_matches = len(mismatches) == 0
    if matches != expected_matches:
        raise GameDriveCheckpointError("visual result matches disagrees with observed fields")
    if matches and result_mismatches:
        raise GameDriveCheckpointError("visual result cannot match while listing mismatches")
    return {
        "checkpoint_id": checkpoint["id"],
        "matches": matches,
        "confidence": confidence,
        "summary": summary,
        "derived_mismatches": mismatches,
        "verdict": "visual_checkpoint_matches" if matches else "visual_checkpoint_mismatch",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate game-drive checkpoint contracts and visual results.")
    subparsers = parser.add_subparsers(dest="command")

    validate_parser = subparsers.add_parser("validate", help="Validate checkpoint files.")
    validate_parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_CHECKPOINT_ROOT)
    validate_parser.add_argument("--json", action="store_true")

    prompt_parser = subparsers.add_parser("prompt", help="Emit a codex-exec visual classification prompt envelope.")
    prompt_parser.add_argument("checkpoint", type=Path)
    prompt_parser.add_argument("screenshot", help="Screenshot path to classify.")

    result_parser = subparsers.add_parser("validate-result", help="Validate a visual classification result.")
    result_parser.add_argument("checkpoint", type=Path)
    result_parser.add_argument("result", type=Path)
    result_parser.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)
    command = args.command or "validate"

    try:
        if command == "validate":
            results = validate_all(args.path)
            if args.json:
                print(json.dumps({"schema": SCHEMA, "validated": results}, indent=2))
            else:
                for result in results:
                    print(f"{result['id']}: action gate {', '.join(result['action_gate'])}")
            return 0
        if command == "prompt":
            checkpoint = validate_checkpoint(args.checkpoint)
            print(json.dumps(build_visual_prompt(checkpoint, args.screenshot), indent=2))
            return 0
        if command == "validate-result":
            result = validate_visual_result(args.checkpoint, args.result)
            if args.json:
                print(json.dumps(result, indent=2))
            else:
                print(f"{result['checkpoint_id']}: {result['verdict']}")
            return 0
    except GameDriveCheckpointError as exc:
        print(f"game-drive checkpoint validation failed: {exc}", file=sys.stderr)
        return 1

    parser.print_help(file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
