from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "docs" / "promotion_packets" / "manifest.json"
CLI_PATH = REPO_ROOT / "port" / "src" / "tools" / "cli.zig"

SCHEMA = "promotion-packets-v1"
STATUSES = {"decode_only", "live_negative", "live_positive", "approved_exception"}
PROMOTABLE_STATUSES = {"live_positive", "approved_exception"}
EVIDENCE_CLASSES = {
    "room_load",
    "zone_transition",
    "inventory_state",
    "life_branch",
    "collision_locomotion",
    "dialog_text",
    "render_only",
}
REQUIRED_HEADINGS = (
    "## Packet Identity",
    "## Exact Seam Identity",
    "## Decode Evidence",
    "## Original Runtime Live Evidence",
    "## Runtime Invariant",
    "## Positive Test",
    "## Negative Test",
    "## Reproduction Command",
    "## Failure Mode",
    "## Docs And Memory",
    "## Old Hypothesis Handling",
    "## Revision History",
)
DIRECT_CONTRACT_RE = re.compile(r'canonical_runtime_contract\s*=\s*"([^"]+)"')
FUNCTION_CONTRACT_RE = re.compile(
    r"fn\s+decodedTransitionCanonicalRuntimeContract\([^)]*\)\s+\?\[\]const u8\s*\{(?P<body>.*?)\n\}",
    re.DOTALL,
)
RETURN_CONTRACT_RE = re.compile(r'return\s+"([^"]+)";')


class PacketValidationError(Exception):
    pass


def repo_path(raw: str) -> Path:
    path = Path(raw)
    if path.is_absolute():
        raise PacketValidationError(f"path must be repo-relative: {raw}")
    if ".." in path.parts:
        raise PacketValidationError(f"path must not escape repo root: {raw}")
    return REPO_ROOT / path


def require_string(packet: dict[str, Any], key: str) -> str:
    value = packet.get(key)
    if not isinstance(value, str) or not value:
        raise PacketValidationError(f"packet is missing non-empty string key '{key}'")
    return value


def validate_string_list(packet_id: str, packet: dict[str, Any], key: str) -> list[str]:
    value = packet.get(key, [])
    if not isinstance(value, list):
        raise PacketValidationError(f"{packet_id}: {key} must be a list")
    strings: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, str) or not item:
            raise PacketValidationError(f"{packet_id}: {key} entries must be non-empty strings")
        if item in seen:
            raise PacketValidationError(f"{packet_id}: duplicate {key} entry '{item}'")
        seen.add(item)
        strings.append(item)
    return strings


def validate_packet_entry(packet: dict[str, Any], seen_ids: set[str]) -> list[str]:
    packet_id = require_string(packet, "id")
    if packet_id in seen_ids:
        raise PacketValidationError(f"duplicate packet id: {packet_id}")
    seen_ids.add(packet_id)

    status = require_string(packet, "status")
    if status not in STATUSES:
        raise PacketValidationError(f"{packet_id}: unsupported status '{status}'")

    evidence_class = require_string(packet, "evidence_class")
    if evidence_class not in EVIDENCE_CLASSES:
        raise PacketValidationError(f"{packet_id}: unsupported evidence_class '{evidence_class}'")

    canonical_runtime = packet.get("canonical_runtime")
    if not isinstance(canonical_runtime, bool):
        raise PacketValidationError(f"{packet_id}: canonical_runtime must be boolean")
    if canonical_runtime and status not in PROMOTABLE_STATUSES:
        raise PacketValidationError(
            f"{packet_id}: canonical_runtime=true requires live_positive or approved_exception"
        )
    runtime_contracts = validate_string_list(packet_id, packet, "runtime_contracts")
    if runtime_contracts and not canonical_runtime:
        raise PacketValidationError(f"{packet_id}: runtime_contracts require canonical_runtime=true")

    packet_path = repo_path(require_string(packet, "packet"))
    if not packet_path.is_file():
        raise PacketValidationError(f"{packet_id}: packet file does not exist: {packet_path}")
    validate_packet_doc(packet_id, status, evidence_class, canonical_runtime, packet_path)

    fixture = packet.get("fixture")
    if fixture is not None:
        if not isinstance(fixture, str) or not fixture:
            raise PacketValidationError(f"{packet_id}: fixture must be null or non-empty string")
        fixture_path = repo_path(fixture)
        if not fixture_path.is_file():
            raise PacketValidationError(f"{packet_id}: fixture file does not exist: {fixture_path}")

    return runtime_contracts


def validate_packet_doc(
    packet_id: str,
    status: str,
    evidence_class: str,
    canonical_runtime: bool,
    packet_path: Path,
) -> None:
    text = packet_path.read_text(encoding="utf-8")
    for heading in REQUIRED_HEADINGS:
        if heading not in text:
            raise PacketValidationError(f"{packet_id}: packet missing heading '{heading}'")

    required_identity_lines = (
        f"- `id`: `{packet_id}`",
        f"- `status`: `{status}`",
        f"- `evidence_class`: `{evidence_class}`",
        f"- `canonical_runtime`: `{'true' if canonical_runtime else 'false'}`",
    )
    for line in required_identity_lines:
        if line not in text:
            raise PacketValidationError(f"{packet_id}: packet identity does not match manifest line: {line}")


def discover_runtime_contracts(path: Path = CLI_PATH) -> set[str]:
    if not path.is_file():
        raise PacketValidationError(f"runtime contract source does not exist: {path}")
    text = path.read_text(encoding="utf-8")
    contracts = set(DIRECT_CONTRACT_RE.findall(text))
    function_match = FUNCTION_CONTRACT_RE.search(text)
    if function_match:
        contracts.update(RETURN_CONTRACT_RE.findall(function_match.group("body")))
    return contracts


def validate_runtime_contract_coverage(emitted: set[str], manifest_contracts: set[str]) -> None:
    missing = emitted - manifest_contracts
    if missing:
        raise PacketValidationError(
            "runtime contracts missing promotable packets: " + ", ".join(sorted(missing))
        )


def validate_manifest(path: Path = MANIFEST_PATH) -> None:
    if not path.is_file():
        raise PacketValidationError(f"manifest does not exist: {path}")
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise PacketValidationError(f"manifest is invalid JSON: {exc}") from exc

    if not isinstance(manifest, dict):
        raise PacketValidationError("manifest must be a JSON object")
    if manifest.get("schema") != SCHEMA:
        raise PacketValidationError(f"manifest schema must be {SCHEMA}")

    packets = manifest.get("packets")
    if not isinstance(packets, list):
        raise PacketValidationError("manifest packets must be a list")

    seen_ids: set[str] = set()
    manifest_contracts: set[str] = set()
    for entry in packets:
        if not isinstance(entry, dict):
            raise PacketValidationError("manifest packet entries must be objects")
        for contract in validate_packet_entry(entry, seen_ids):
            if contract in manifest_contracts:
                raise PacketValidationError(f"duplicate runtime_contracts entry '{contract}'")
            manifest_contracts.add(contract)
    validate_runtime_contract_coverage(discover_runtime_contracts(), manifest_contracts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate canonical promotion packet docs and manifest.")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MANIFEST_PATH,
        help="Manifest path. Defaults to docs/promotion_packets/manifest.json.",
    )
    args = parser.parse_args(argv)

    try:
        validate_manifest(args.manifest)
    except PacketValidationError as exc:
        print(f"promotion packet validation failed: {exc}", file=sys.stderr)
        return 1
    print(f"promotion packet validation passed: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
