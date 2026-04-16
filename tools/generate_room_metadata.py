from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path


GENERATED_RELATIVE_PATH = "port/src/generated/room_metadata.zig"
LEGACY_SCENE_RELATIVE_PATH = "reference/littlebigreversing/mbn_tools/dl18_lbarchitect/fileinfo/lba2_sce.hqd"
LEGACY_BACKGROUND_RELATIVE_PATH = "reference/littlebigreversing/mbn_tools/dl18_lbarchitect/fileinfo/lba2_bkg.hqd"

LEGACY_DISPLAY_NAME_OVERRIDES: dict[str, dict[int, str]] = {
    "scene": {
        65: "Scene 63: White Leaf Desert, near Temple of Bù",
        69: "Scene 67: White Leaf Desert, at the Temple of Bù",
        70: "Scene 68: White Leaf Desert, near Temple of Bù",
        129: "Scene 127: White Leaf Desert, Temple of Bù Secret passage",
        210: "Scene 208: Demo Scene - White Leaf Desert, Temple of Bù",
    },
    "background": {
        77: "Grid 75: White Leaf Desert, Temple of Bù Secret passage",
        142: "Grid 140: Demo Room - White Leaf Desert, Temple of Bù",
    },
}


@dataclass(frozen=True)
class GeneratedEntry:
    entry_index: int
    display_name: str
    normalized_name: str


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Generate the checked-in room metadata Zig module from the local metadata reference clone."
    )
    parser.add_argument(
        "--metadata-root",
        default=str(repo_root.parent / "lba-reference-repos" / "metadata"),
        help="Path to the cloned LBALab metadata repository root.",
    )
    parser.add_argument(
        "--output",
        default=str(repo_root / GENERATED_RELATIVE_PATH),
        help="Path to the generated Zig module.",
    )
    parser.add_argument(
        "--skip-legacy-parity-check",
        action="store_true",
        help="Skip verifying the generated selector/display corpus against the legacy checked-in .hqd files.",
    )
    return parser.parse_args()


def normalize_search_key(value: str) -> str:
    folded: list[str] = []
    pending_space = False
    for char in value:
        normalized = fold_codepoint(char)
        if normalized is None:
            pending_space = len(folded) != 0
            continue
        if pending_space and folded:
            folded.append(" ")
            pending_space = False
        folded.append(normalized)
    while folded and folded[-1] == " ":
        folded.pop()
    return "".join(folded)


def fold_codepoint(char: str) -> str | None:
    if len(char) != 1:
        raise ValueError(f"expected one codepoint, got {char!r}")
    codepoint = ord(char)
    if 0x41 <= codepoint <= 0x5A:
        return chr(codepoint + 32)
    if 0x61 <= codepoint <= 0x7A or 0x30 <= codepoint <= 0x39:
        return char
    if codepoint in {
        0x00C0,
        0x00C1,
        0x00C2,
        0x00C3,
        0x00C4,
        0x00C5,
        0x00E0,
        0x00E1,
        0x00E2,
        0x00E3,
        0x00E4,
        0x00E5,
    }:
        return "a"
    if codepoint in {0x00C7, 0x00E7}:
        return "c"
    if codepoint in {
        0x00C8,
        0x00C9,
        0x00CA,
        0x00CB,
        0x00E8,
        0x00E9,
        0x00EA,
        0x00EB,
    }:
        return "e"
    if codepoint in {
        0x00CC,
        0x00CD,
        0x00CE,
        0x00CF,
        0x00EC,
        0x00ED,
        0x00EE,
        0x00EF,
    }:
        return "i"
    if codepoint in {0x00D1, 0x00F1}:
        return "n"
    if codepoint in {
        0x00D2,
        0x00D3,
        0x00D4,
        0x00D5,
        0x00D6,
        0x00F2,
        0x00F3,
        0x00F4,
        0x00F5,
        0x00F6,
    }:
        return "o"
    if codepoint in {
        0x00D9,
        0x00DA,
        0x00DB,
        0x00DC,
        0x00F9,
        0x00FA,
        0x00FB,
        0x00FC,
    }:
        return "u"
    if codepoint in {0x00DD, 0x00FD, 0x00FF}:
        return "y"
    return None


def load_generated_entries(metadata_root: Path, kind: str) -> list[GeneratedEntry]:
    metadata_path = metadata_root / "LBA2" / "HQR" / {
        "scene": "SCENE.HQR.json",
        "background": "LBA_BKG.HQR.json",
    }[kind]
    payload = json.loads(metadata_path.read_text(encoding="utf-8"))
    entries = payload.get("entries")
    if not isinstance(entries, list):
        raise ValueError(f"{metadata_path} is missing a list-valued entries field")

    generated: list[GeneratedEntry] = []
    overrides = LEGACY_DISPLAY_NAME_OVERRIDES[kind]
    for index, entry in enumerate(entries):
        if index == 0:
            continue
        if not isinstance(entry, dict):
            continue
        description = entry.get("description")
        if not isinstance(description, str) or not description:
            continue
        display_name = overrides.get(index + 1, description)
        generated.append(
            GeneratedEntry(
                entry_index=index + 1,
                display_name=display_name,
                normalized_name=normalize_search_key(display_name),
            )
        )
    return generated


def load_legacy_entries(repo_root: Path, kind: str) -> list[GeneratedEntry]:
    legacy_path = repo_root / {
        "scene": LEGACY_SCENE_RELATIVE_PATH,
        "background": LEGACY_BACKGROUND_RELATIVE_PATH,
    }[kind]
    rows: list[GeneratedEntry] = []
    for raw_line in legacy_path.read_text(encoding="latin-1").splitlines():
        match = re.match(r"(\d+):[^|]*\|(.*)$", raw_line)
        if match is None:
            continue
        metadata_index = int(match.group(1))
        if metadata_index == 0:
            continue
        display_name = match.group(2)
        if not display_name:
            continue
        rows.append(
            GeneratedEntry(
                entry_index=metadata_index + 1,
                display_name=display_name,
                normalized_name=normalize_search_key(display_name),
            )
        )
    return rows


def validate_legacy_parity(kind: str, generated_entries: list[GeneratedEntry], legacy_entries: list[GeneratedEntry]) -> None:
    generated_by_entry = {entry.entry_index: entry for entry in generated_entries}
    legacy_by_entry = {entry.entry_index: entry for entry in legacy_entries}

    missing_entries = sorted(set(legacy_by_entry) - set(generated_by_entry))
    extra_entries = sorted(set(generated_by_entry) - set(legacy_by_entry))
    mismatched_display_entries = [
        entry_index
        for entry_index in sorted(set(legacy_by_entry) & set(generated_by_entry))
        if legacy_by_entry[entry_index].display_name != generated_by_entry[entry_index].display_name
    ]
    mismatched_normalized_entries = [
        entry_index
        for entry_index in sorted(set(legacy_by_entry) & set(generated_by_entry))
        if legacy_by_entry[entry_index].normalized_name != generated_by_entry[entry_index].normalized_name
    ]

    if not missing_entries and not extra_entries and not mismatched_display_entries and not mismatched_normalized_entries:
        return

    problems: list[str] = []
    if missing_entries:
        problems.append(f"missing entries {missing_entries[:5]}{'...' if len(missing_entries) > 5 else ''}")
    if extra_entries:
        problems.append(f"extra entries {extra_entries[:5]}{'...' if len(extra_entries) > 5 else ''}")
    if mismatched_display_entries:
        entry_index = mismatched_display_entries[0]
        problems.append(
            f"display mismatch at {entry_index}: {legacy_by_entry[entry_index].display_name!r} != {generated_by_entry[entry_index].display_name!r}"
        )
    if mismatched_normalized_entries:
        entry_index = mismatched_normalized_entries[0]
        problems.append(
            f"normalized mismatch at {entry_index}: {legacy_by_entry[entry_index].normalized_name!r} != {generated_by_entry[entry_index].normalized_name!r}"
        )
    raise ValueError(f"{kind} metadata drifted from the legacy selector/display corpus: {'; '.join(problems)}")


def zig_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_entries(entries: list[GeneratedEntry]) -> str:
    lines: list[str] = []
    for entry in entries:
        lines.extend(
            (
                "    .{",
                f"        .entry_index = {entry.entry_index},",
                f"        .display_name = {zig_quote(entry.display_name)},",
                f"        .normalized_name = {zig_quote(entry.normalized_name)},",
                "    },",
            )
        )
    return "\n".join(lines)


def render_module(scene_entries: list[GeneratedEntry], background_entries: list[GeneratedEntry]) -> str:
    return f"""// Generated by tools/generate_room_metadata.py.
// Do not edit by hand; regenerate from the local LBALab metadata clone.

pub const generated_relative_path = "{GENERATED_RELATIVE_PATH}";
pub const upstream_scene_relative_path = "../lba-reference-repos/metadata/LBA2/HQR/SCENE.HQR.json";
pub const upstream_background_relative_path = "../lba-reference-repos/metadata/LBA2/HQR/LBA_BKG.HQR.json";

pub const RoomMetadataEntry = struct {{
    entry_index: usize,
    display_name: []const u8,
    normalized_name: []const u8,
}};

pub const scene_entries: []const RoomMetadataEntry = &.{{
{render_entries(scene_entries)}
}};

pub const background_entries: []const RoomMetadataEntry = &.{{
{render_entries(background_entries)}
}};
"""


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    metadata_root = Path(args.metadata_root)
    output_path = Path(args.output)

    if not metadata_root.exists():
        raise FileNotFoundError(f"metadata root not found: {metadata_root}")

    scene_entries = load_generated_entries(metadata_root, "scene")
    background_entries = load_generated_entries(metadata_root, "background")
    if not args.skip_legacy_parity_check:
        validate_legacy_parity("scene", scene_entries, load_legacy_entries(repo_root, "scene"))
        validate_legacy_parity("background", background_entries, load_legacy_entries(repo_root, "background"))
    rendered = render_module(scene_entries, background_entries)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered, encoding="utf-8", newline="\n")

    print(
        f"wrote {len(scene_entries)} scene entries and {len(background_entries)} background entries to {output_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
