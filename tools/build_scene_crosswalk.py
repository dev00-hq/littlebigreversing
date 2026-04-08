from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from map_idajs_saves import CALL_RE, iter_relevant_scene_files, trim_to_lba2_scope, unquote


@dataclass(frozen=True)
class SourceSceneRecord:
    scene_id: int
    raw_scene_entry_index: int
    node_kind: str
    planet: str
    island: str | None
    section: str | None
    scene_name: str
    parent_scene_name: str | None
    source_file: str
    source_path: str
    source_line: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a deterministic crosswalk from IdaJS old-source scene ids to repo-facing raw entries and sample saves."
    )
    parser.add_argument(
        "--scene-root",
        default=r"D:\repos\idajs\Ida\srcjs\lba2editor",
        help="Directory containing IdaJS scene-id TypeScript files.",
    )
    parser.add_argument(
        "--save-map",
        default=r"D:\repos\reverse\littlebigreversing\work\idajs_samples_save_map.jsonl",
        help="JSONL save map generated from IdaJS sample saves.",
    )
    parser.add_argument(
        "--output",
        default=r"D:\repos\reverse\littlebigreversing\work\idajs_scene_crosswalk.jsonl",
        help="Output JSONL path.",
    )
    return parser.parse_args()


def parse_scene_table_with_locations(scene_root: Path) -> dict[int, SourceSceneRecord]:
    records: dict[int, SourceSceneRecord] = {}

    for path in iter_relevant_scene_files(scene_root):
        text = trim_to_lba2_scope(path, path.read_text(encoding="utf-8"))

        current_planet: str | None = None
        current_island: str | None = None
        current_section: str | None = None
        iso_stack: list[tuple[int, str]] = []

        for line_number, raw_line in enumerate(text.splitlines(), start=1):
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
                scene_id = int(first, 10)
                current_section = unquote(second or "")
                iso_stack.clear()
                if scene_id >= 0 and current_planet is not None:
                    records.setdefault(
                        scene_id,
                        SourceSceneRecord(
                            scene_id=scene_id,
                            raw_scene_entry_index=scene_id + 2,
                            node_kind="section",
                            planet=current_planet,
                            island=current_island,
                            section=current_section,
                            scene_name=current_section,
                            parent_scene_name=None,
                            source_file=path.name,
                            source_path=str(path),
                            source_line=line_number,
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
                    SourceSceneRecord(
                        scene_id=scene_id,
                        raw_scene_entry_index=scene_id + 2,
                        node_kind="iso",
                        planet=current_planet,
                        island=current_island,
                        section=current_section,
                        scene_name=scene_name,
                        parent_scene_name=parent_scene_name,
                        source_file=path.name,
                        source_path=str(path),
                        source_line=line_number,
                    ),
                )

            iso_stack.append((indent, scene_name))

    return records


def load_save_map(path: Path) -> dict[int, list[dict[str, object]]]:
    save_samples: dict[int, list[dict[str, object]]] = {}

    if not path.exists():
        return save_samples

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        record = json.loads(line)
        scene_lookup = record.get("scene_lookup")
        if not scene_lookup:
            continue

        scene_id = int(scene_lookup["scene_id"])
        save_samples.setdefault(scene_id, []).append(
            {
                "file_name": record["file_name"],
                "save_name": record["save_name"],
                "file_size": record["file_size"],
                "version_hex": record["version_hex"],
                "num_cube": record["num_cube"],
                "raw_scene_entry_index": record["raw_scene_entry_index"],
            }
        )

    for samples in save_samples.values():
        samples.sort(key=lambda item: (str(item["file_name"]).lower(), str(item["save_name"]).lower()))

    return save_samples


def build_crosswalk_records(
    source_records: dict[int, SourceSceneRecord],
    save_samples: dict[int, list[dict[str, object]]],
) -> Iterable[dict[str, object]]:
    for scene_id in sorted(source_records):
        source = source_records[scene_id]
        samples = save_samples.get(scene_id, [])

        yield {
            "scene_id": source.scene_id,
            "raw_scene_entry_index": source.raw_scene_entry_index,
            "node_kind": source.node_kind,
            "planet": source.planet,
            "island": source.island,
            "section": source.section,
            "scene_name": source.scene_name,
            "parent_scene_name": source.parent_scene_name,
            "source_file": source.source_file,
            "source_path": source.source_path,
            "source_line": source.source_line,
            "sample_save_count": len(samples),
            "sample_saves": samples,
        }


def main() -> int:
    args = parse_args()
    scene_root = Path(args.scene_root)
    save_map_path = Path(args.save_map)
    output_path = Path(args.output)

    if not scene_root.exists():
        raise FileNotFoundError(f"scene root not found: {scene_root}")

    source_records = parse_scene_table_with_locations(scene_root)
    save_samples = load_save_map(save_map_path)
    crosswalk_records = list(build_crosswalk_records(source_records, save_samples))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as handle:
        for record in crosswalk_records:
            handle.write(json.dumps(record, ensure_ascii=True))
            handle.write("\n")

    print(f"wrote {len(crosswalk_records)} records to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
