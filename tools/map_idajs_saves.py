from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


CALL_RE = re.compile(
    r"""
    (?P<kind>planet|island|section|iso)
    \(
    \s*
    (?P<first>-?\d+|'(?:\\'|[^'])*')
    (?:\s*,\s*(?P<second>'(?:\\'|[^'])*'))?
    """,
    re.VERBOSE,
)


@dataclass(frozen=True)
class SceneRecord:
    scene_id: int
    node_kind: str
    planet: str
    island: str | None
    section: str | None
    scene_name: str
    parent_scene_name: str | None
    source_file: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Map IdaJS LBA save files to header fields and scene labels."
    )
    parser.add_argument(
        "--save-dir",
        default=r"D:\repos\idajs\Ida\Samples\saves",
        help="Directory containing .LBA save files.",
    )
    parser.add_argument(
        "--scene-root",
        default=r"D:\repos\idajs\Ida\srcjs\lba2editor",
        help="Directory containing IdaJS scene-id TypeScript files.",
    )
    parser.add_argument(
        "--output",
        default=r"D:\repos\reverse\littlebigreversing\work\idajs_samples_save_map.jsonl",
        help="Output JSONL path.",
    )
    return parser.parse_args()


def unquote(value: str) -> str:
    if not (value.startswith("'") and value.endswith("'")):
        return value
    return value[1:-1].replace("\\'", "'")


def iter_relevant_scene_files(scene_root: Path) -> Iterable[Path]:
    for name in ("Twinsun.ts", "Moon.ts", "ZeelishSurface.ts", "ZeelishUndergas.ts"):
        path = scene_root / name
        if path.exists():
            yield path


def trim_to_lba2_scope(path: Path, text: str) -> str:
    if path.name == "Twinsun.ts":
        marker = "const TwinsunLBA1"
        index = text.find(marker)
        if index != -1:
            return text[:index]
    return text


def parse_scene_table(scene_root: Path) -> dict[int, SceneRecord]:
    records: dict[int, SceneRecord] = {}

    for path in iter_relevant_scene_files(scene_root):
        text = trim_to_lba2_scope(path, path.read_text(encoding="utf-8"))

        current_planet: str | None = None
        current_island: str | None = None
        current_section: str | None = None
        iso_stack: list[tuple[int, str]] = []

        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("import ") or line.startswith("export "):
                continue

            match = CALL_RE.search(raw_line)
            if not match:
                continue

            kind = match.group("kind")
            first = match.group("first")
            second = match.group("second")
            indent = len(raw_line) - len(raw_line.lstrip(" "))

            if kind == "planet":
                current_planet = unquote(first)
                current_island = None
                current_section = None
                iso_stack.clear()
                continue

            if kind == "island":
                current_island = unquote(second or "")
                current_section = None
                iso_stack.clear()
                continue

            if kind == "section":
                section_id = int(first, 10)
                current_section = unquote(second or "")
                iso_stack.clear()
                if section_id >= 0 and current_planet is not None:
                    records.setdefault(
                        section_id,
                        SceneRecord(
                            scene_id=section_id,
                            node_kind="section",
                            planet=current_planet,
                            island=current_island,
                            section=current_section,
                            scene_name=current_section,
                            parent_scene_name=None,
                            source_file=path.name,
                        ),
                    )
                continue

            if kind != "iso":
                continue

            while iso_stack and iso_stack[-1][0] >= indent:
                iso_stack.pop()

            scene_id = int(first, 10)
            scene_name = unquote(second or "")
            parent_scene_name = iso_stack[-1][1] if iso_stack else None

            if scene_id >= 0 and current_planet is not None:
                records.setdefault(
                    scene_id,
                        SceneRecord(
                            scene_id=scene_id,
                            node_kind="iso",
                            planet=current_planet,
                            island=current_island,
                            section=current_section,
                        scene_name=scene_name,
                        parent_scene_name=parent_scene_name,
                        source_file=path.name,
                    ),
                )

            iso_stack.append((indent, scene_name))

    return records


def read_save_header(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    if len(data) < 6:
        raise ValueError(f"save file too short: {path}")

    name_end = data.find(b"\x00", 5)
    if name_end == -1:
        name_end = len(data)

    version_byte = data[0]
    num_cube = int.from_bytes(data[1:5], byteorder="little", signed=True)
    save_name = data[5:name_end].decode("ascii", errors="replace")

    return {
        "version_byte": version_byte,
        "version_hex": f"0x{version_byte:02X}",
        "num_cube": num_cube,
        "raw_scene_entry_index": num_cube + 2,
        "save_name": save_name,
    }


def build_save_record(path: Path, lookup: dict[int, SceneRecord]) -> dict[str, object]:
    header = read_save_header(path)
    scene = lookup.get(int(header["num_cube"]))

    record: dict[str, object] = {
        "file_name": path.name,
        "file_path": str(path),
        "file_size": path.stat().st_size,
        **header,
    }

    if scene is None:
        record["scene_lookup"] = None
    else:
        record["scene_lookup"] = {
            "scene_id": scene.scene_id,
            "node_kind": scene.node_kind,
            "planet": scene.planet,
            "island": scene.island,
            "section": scene.section,
            "scene_name": scene.scene_name,
            "parent_scene_name": scene.parent_scene_name,
            "source_file": scene.source_file,
        }

    return record


def main() -> int:
    args = parse_args()
    save_dir = Path(args.save_dir)
    scene_root = Path(args.scene_root)
    output_path = Path(args.output)

    if not save_dir.exists():
        raise FileNotFoundError(f"save dir not found: {save_dir}")
    if not scene_root.exists():
        raise FileNotFoundError(f"scene root not found: {scene_root}")

    scene_lookup = parse_scene_table(scene_root)
    save_paths = sorted(save_dir.glob("*.LBA")) + sorted(save_dir.glob("*.lba"))

    records: list[dict[str, object]] = []
    seen: set[Path] = set()
    for path in save_paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        records.append(build_save_record(path, scene_lookup))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=True))
            handle.write("\n")

    print(f"wrote {len(records)} records to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
