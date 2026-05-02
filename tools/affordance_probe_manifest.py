from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST_ROOT = REPO_ROOT / "tools" / "fixtures" / "affordance_probes"
SCHEMA = "affordance-probe-manifest-v1"
AUTOSAVE_GUARDS = {"hide_active_autosave_preserve_generated"}
RUNNER_TYPES = {"existing_artifact_validation"}
OBSERVERS = {
    "promotion_fixture",
    "summary_changed_object_indices",
    "timeline_artifact",
    "initial_screenshot",
    "final_screenshot",
}


class AffordanceProbeManifestError(Exception):
    pass


def repo_path(raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        raise AffordanceProbeManifestError(f"path must be repo-relative: {raw}")
    if ".." in path.parts:
        raise AffordanceProbeManifestError(f"path must not escape repo root: {raw}")
    return REPO_ROOT / path


def require_dict(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise AffordanceProbeManifestError(f"missing object: {key}")
    return value


def require_string(parent: dict[str, Any], key: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value:
        raise AffordanceProbeManifestError(f"missing non-empty string: {key}")
    return value


def require_number(parent: dict[str, Any], key: str) -> int | float:
    value = parent.get(key)
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise AffordanceProbeManifestError(f"missing number: {key}")
    return value


def require_int_list(parent: dict[str, Any], key: str) -> list[int]:
    value = parent.get(key)
    if not isinstance(value, list) or not value:
        raise AffordanceProbeManifestError(f"missing non-empty integer list: {key}")
    result: list[int] = []
    for item in value:
        if not isinstance(item, int) or isinstance(item, bool):
            raise AffordanceProbeManifestError(f"{key} entries must be integers")
        result.append(item)
    return result


def optional_string_list(parent: dict[str, Any], key: str) -> list[str]:
    value = parent.get(key)
    if value is None:
        return []
    if not isinstance(value, list):
        raise AffordanceProbeManifestError(f"{key} must be a string list")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise AffordanceProbeManifestError(f"{key} entries must be non-empty strings")
        result.append(item)
    return result


def require_string_list(parent: dict[str, Any], key: str) -> list[str]:
    value = parent.get(key)
    if not isinstance(value, list) or not value:
        raise AffordanceProbeManifestError(f"missing non-empty string list: {key}")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise AffordanceProbeManifestError(f"{key} entries must be non-empty strings")
        result.append(item)
    return result


def require_file(raw: str, manifest_id: str, label: str) -> Path:
    path = repo_path(raw)
    if not path.is_file():
        raise AffordanceProbeManifestError(f"{manifest_id}: {label} does not exist: {path}")
    return path


def repo_relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def load_json_file(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise AffordanceProbeManifestError(f"file does not exist: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise AffordanceProbeManifestError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise AffordanceProbeManifestError(f"JSON file must contain an object: {path}")
    return value


def load_manifest(path: Path) -> dict[str, Any]:
    manifest = load_json_file(path)
    if manifest.get("schema") != SCHEMA:
        raise AffordanceProbeManifestError(f"{path}: schema must be {SCHEMA}")
    return manifest


def validate_launch_input(manifest_id: str, manifest: dict[str, Any], promotion: dict[str, Any]) -> None:
    input_spec = require_dict(manifest, "input")
    launch_input = promotion.get("launch_input", {})
    if launch_input.get("key") != require_string(input_spec, "key"):
        raise AffordanceProbeManifestError(f"{manifest_id}: input key mismatch")
    if launch_input.get("source_semantics") != require_string(input_spec, "source_semantics"):
        raise AffordanceProbeManifestError(f"{manifest_id}: input semantics mismatch")
    if launch_input.get("hold_sec") != require_number(input_spec, "hold_sec"):
        raise AffordanceProbeManifestError(f"{manifest_id}: input hold_sec mismatch")


def validate_launch_saves(manifest_id: str, manifest: dict[str, Any], promotion: dict[str, Any]) -> None:
    launch = require_dict(manifest, "launch")
    saves = require_string_list(launch, "saves")
    source = promotion.get("source", {})
    if not isinstance(source, dict):
        raise AffordanceProbeManifestError(f"{manifest_id}: promotion source must be an object")
    promotion_saves: list[str] = []
    if isinstance(source.get("save"), str):
        promotion_saves.append(source["save"])
    promotion_saves.extend(optional_string_list(source, "primary_saves"))
    for save in saves:
        if save not in promotion_saves:
            raise AffordanceProbeManifestError(f"{manifest_id}: launch save missing from promotion fixture: {save}")
    autosave_guard = require_string(launch, "autosave_guard")
    if autosave_guard not in AUTOSAVE_GUARDS:
        raise AffordanceProbeManifestError(f"{manifest_id}: unsupported autosave guard {autosave_guard}")


def artifact_paths_for_run(run: dict[str, Any], manifest_id: str) -> list[str]:
    if isinstance(run.get("artifact"), str):
        return [run["artifact"]]
    artifacts = run.get("artifacts")
    if isinstance(artifacts, list) and artifacts:
        result = []
        for artifact in artifacts:
            if not isinstance(artifact, str) or not artifact:
                raise AffordanceProbeManifestError(f"{manifest_id}: artifact entries must be non-empty strings")
            result.append(artifact)
        return result
    raise AffordanceProbeManifestError(f"{manifest_id}: proof run is missing artifact path")


def validate_artifact_summary(
    manifest_id: str,
    artifact_raw: str,
    target: int,
    hold_sec: int | float,
) -> dict[str, Any]:
    artifact_path = require_file(artifact_raw, manifest_id, "artifact")
    summary = load_json_file(artifact_path)
    if summary.get("hold_sec") != hold_sec:
        raise AffordanceProbeManifestError(f"{manifest_id}: summary hold_sec mismatch: {artifact_path}")
    changed = summary.get("changed_object_indices")
    if not isinstance(changed, list) or target not in changed:
        raise AffordanceProbeManifestError(f"{manifest_id}: target object missing from summary changes")
    timeline = summary.get("timeline")
    if not isinstance(timeline, str) or not Path(timeline).is_file():
        raise AffordanceProbeManifestError(f"{manifest_id}: summary timeline does not exist: {artifact_path}")
    screenshots = summary.get("screenshots")
    if not isinstance(screenshots, list) or len(screenshots) < 2:
        raise AffordanceProbeManifestError(f"{manifest_id}: summary screenshots are incomplete: {artifact_path}")
    for screenshot in screenshots[:2]:
        if not isinstance(screenshot, str) or not Path(screenshot).is_file():
            raise AffordanceProbeManifestError(f"{manifest_id}: summary screenshot does not exist: {artifact_path}")
    return {"target_object_index": target, "artifact": repo_relative(artifact_path)}


def validate_proof_runs(
    manifest_id: str,
    manifest: dict[str, Any],
    promotion: dict[str, Any],
) -> list[dict[str, Any]]:
    expected = require_dict(manifest, "expected")
    if promotion.get("verdict") != require_string(expected, "promotion_verdict"):
        raise AffordanceProbeManifestError(f"{manifest_id}: promotion verdict mismatch")
    target_indices = require_int_list(expected, "target_object_indices")

    observers = require_string_list(manifest, "observers")
    unknown_observers = sorted(set(observers) - OBSERVERS)
    if unknown_observers:
        raise AffordanceProbeManifestError(
            f"{manifest_id}: unsupported observers: {', '.join(unknown_observers)}"
        )

    run_collection = require_string(expected, "run_collection")
    observed = promotion.get(run_collection)
    if not isinstance(observed, list) or not observed:
        raise AffordanceProbeManifestError(f"{manifest_id}: promotion fixture has no {run_collection}")
    observed_targets = [run.get("target_object_index") for run in observed if isinstance(run, dict)]
    if observed_targets != target_indices:
        raise AffordanceProbeManifestError(f"{manifest_id}: observed run target order mismatch")

    hold_sec = require_number(require_dict(manifest, "input"), "hold_sec")
    artifact_results = []
    for run in observed:
        if not isinstance(run, dict):
            raise AffordanceProbeManifestError(f"{manifest_id}: observed run entries must be objects")
        target = run.get("target_object_index")
        if not isinstance(target, int):
            raise AffordanceProbeManifestError(f"{manifest_id}: target_object_index must be an integer")
        for artifact_raw in artifact_paths_for_run(run, manifest_id):
            artifact_results.append(validate_artifact_summary(manifest_id, artifact_raw, target, hold_sec))
        timeline = run.get("timeline")
        if isinstance(timeline, str):
            require_file(timeline, manifest_id, "timeline")
    return artifact_results


def validate_manifest(path: Path) -> dict[str, Any]:
    manifest = load_manifest(path)
    manifest_id = require_string(manifest, "id")

    runner = require_string(manifest, "runner")
    if runner not in RUNNER_TYPES:
        raise AffordanceProbeManifestError(f"{manifest_id}: unsupported runner {runner}")

    source = require_dict(manifest, "source")
    promotion_fixture_path = require_file(require_string(source, "promotion_fixture"), manifest_id, "promotion fixture")
    promotion = load_json_file(promotion_fixture_path)
    if promotion.get("schema") != "promotion-packet-evidence-v1":
        raise AffordanceProbeManifestError(f"{manifest_id}: promotion fixture schema mismatch")
    if promotion.get("packet_id") != require_string(source, "promotion_packet_id"):
        raise AffordanceProbeManifestError(f"{manifest_id}: promotion packet id mismatch")

    validate_launch_saves(manifest_id, manifest, promotion)
    validate_launch_input(manifest_id, manifest, promotion)
    artifact_results = validate_proof_runs(manifest_id, manifest, promotion)
    target_indices = require_int_list(require_dict(manifest, "expected"), "target_object_indices")

    return {
        "id": manifest_id,
        "runner": runner,
        "promotion_packet_id": promotion["packet_id"],
        "promotion_fixture": repo_relative(promotion_fixture_path),
        "validated_targets": target_indices,
        "artifacts": artifact_results,
    }


def iter_manifest_paths(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    if not root.is_dir():
        raise AffordanceProbeManifestError(f"manifest path does not exist: {root}")
    return sorted(root.glob("*.json"))


def validate_all(root: Path = DEFAULT_MANIFEST_ROOT) -> list[dict[str, Any]]:
    paths = iter_manifest_paths(root)
    if not paths:
        raise AffordanceProbeManifestError(f"no manifest files found under {root}")
    return [validate_manifest(path) for path in paths]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate read-only affordance probe manifests.")
    parser.add_argument(
        "path",
        nargs="?",
        type=Path,
        default=DEFAULT_MANIFEST_ROOT,
        help="Manifest file or directory. Defaults to tools/fixtures/affordance_probes.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable validation results.")
    args = parser.parse_args(argv)

    try:
        results = validate_all(args.path)
    except AffordanceProbeManifestError as exc:
        print(f"affordance probe manifest validation failed: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps({"schema": SCHEMA, "validated": results}, indent=2))
    else:
        for result in results:
            targets = ", ".join(str(target) for target in result["validated_targets"])
            print(f"{result['id']}: validated targets {targets}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
