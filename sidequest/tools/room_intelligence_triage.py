#!/usr/bin/env python3
"""Sidequest-only consumer for inspect-room-intelligence dumps.

This tool answers one question: which dumped rooms are the strongest
guarded-runtime follow-up targets?
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence


@dataclass(frozen=True)
class RoomSummary:
    source_path: Path
    room_label: str
    viewer_loadable: bool
    scene_kind_status: str
    fragment_status: str
    hero_status: str
    hero_instruction_count: int
    actor_count: int
    decoded_actor_count: int
    max_actor_instruction_count: int
    fragment_layout_count: int
    runtime_tile_count: int | None
    has_runtime_height_grid: bool


@dataclass(frozen=True)
class RankedRoom:
    summary: RoomSummary
    verdict: str


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rank inspect-room-intelligence dumps by guarded-runtime follow-up value. "
            "This is a sidequest consumer and not a canonical repo interface."
        )
    )
    parser.add_argument("dump_paths", nargs="+", help="Paths to inspect-room-intelligence JSON dumps.")
    return parser.parse_args(argv)


def require_object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{path} must be an array")
    return value


def optional_list(value: Any, path: str) -> list[Any]:
    if value is None:
        return []
    return require_list(value, path)


def require_str(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{path} must be a string")
    return value


def require_int(value: Any, path: str) -> int:
    if not isinstance(value, int):
        raise ValueError(f"{path} must be an integer")
    return value


def require_bool(value: Any, path: str) -> bool:
    if not isinstance(value, bool):
        raise ValueError(f"{path} must be a boolean")
    return value


def actor_instruction_counts(actors: Iterable[dict[str, Any]]) -> list[int]:
    counts: list[int] = []
    for index, actor in enumerate(actors):
        life = require_object(actor.get("life"), f"actors[{index}].life")
        audit = require_object(life.get("audit"), f"actors[{index}].life.audit")
        counts.append(require_int(audit.get("instruction_count"), f"actors[{index}].life.audit.instruction_count"))
    return counts


def decoded_actor_total(actors: Iterable[dict[str, Any]]) -> int:
    decoded = 0
    for index, actor in enumerate(actors):
        life = require_object(actor.get("life"), f"actors[{index}].life")
        audit = require_object(life.get("audit"), f"actors[{index}].life.audit")
        status = require_str(audit.get("status"), f"actors[{index}].life.audit.status")
        if status == "decoded":
            decoded += 1
    return decoded


def load_room_summary(path: Path) -> RoomSummary:
    payload = json.loads(path.read_text(encoding="utf-8"))
    root = require_object(payload, "payload")

    selection = require_object(root.get("selection"), "selection")
    scene_selection = require_object(selection.get("scene"), "selection.scene")
    background_selection = require_object(selection.get("background"), "selection.background")
    scene = require_object(root.get("scene"), "scene")
    counts = require_object(scene.get("counts"), "scene.counts")
    hero_start = require_object(scene.get("hero_start"), "scene.hero_start")
    hero_life = require_object(hero_start.get("life"), "scene.hero_start.life")
    hero_audit = require_object(hero_life.get("audit"), "scene.hero_start.life.audit")
    validation = require_object(root.get("validation"), "validation")
    scene_kind = require_object(validation.get("scene_kind"), "validation.scene_kind")
    fragment_zones = require_object(validation.get("fragment_zones"), "validation.fragment_zones")
    actors = require_list(root.get("actors"), "actors")
    fragment_zone_layout = optional_list(root.get("fragment_zone_layout"), "fragment_zone_layout")
    background = require_object(root.get("background"), "background")
    composition = require_object(background.get("composition"), "background.composition")

    scene_index = require_int(scene_selection.get("resolved_entry_index"), "selection.scene.resolved_entry_index")
    background_index = require_int(
        background_selection.get("resolved_entry_index"),
        "selection.background.resolved_entry_index",
    )

    tiles = composition.get("tiles")
    runtime_tile_count = None
    if isinstance(tiles, list):
        runtime_tile_count = len(tiles)

    height_grid = composition.get("height_grid")

    instruction_counts = actor_instruction_counts(actors)
    return RoomSummary(
        source_path=path,
        room_label=f"{scene_index}/{background_index}",
        viewer_loadable=require_bool(validation.get("viewer_loadable"), "validation.viewer_loadable"),
        scene_kind_status=require_str(scene_kind.get("status"), "validation.scene_kind.status"),
        fragment_status=require_str(fragment_zones.get("status"), "validation.fragment_zones.status"),
        hero_status=require_str(hero_audit.get("status"), "scene.hero_start.life.audit.status"),
        hero_instruction_count=require_int(
            hero_audit.get("instruction_count"),
            "scene.hero_start.life.audit.instruction_count",
        ),
        actor_count=require_int(counts.get("decoded_actor_count"), "scene.counts.decoded_actor_count"),
        decoded_actor_count=decoded_actor_total(actors),
        max_actor_instruction_count=max(instruction_counts, default=0),
        fragment_layout_count=len(fragment_zone_layout),
        runtime_tile_count=runtime_tile_count,
        has_runtime_height_grid=isinstance(height_grid, list),
    )


def verdict_for(summary: RoomSummary) -> str:
    if not summary.viewer_loadable:
        return "decode-only"
    if summary.scene_kind_status != "interior":
        return "decode-only"
    if summary.hero_status != "decoded":
        return "runtime-risk"
    if summary.actor_count != summary.decoded_actor_count:
        return "runtime-risk"
    return "runtime-followup"


def ranked_rooms(summaries: Sequence[RoomSummary]) -> list[RankedRoom]:
    ranked = [RankedRoom(summary=summary, verdict=verdict_for(summary)) for summary in summaries]

    order = {"runtime-followup": 0, "runtime-risk": 1, "decode-only": 2}
    ranked.sort(
        key=lambda item: (
            order[item.verdict],
            -item.summary.fragment_layout_count,
            -item.summary.max_actor_instruction_count,
            -item.summary.hero_instruction_count,
            -item.summary.decoded_actor_count,
            item.summary.room_label,
        )
    )
    return ranked


def evidence_line(summary: RoomSummary) -> str:
    runtime_tiles = "n/a" if summary.runtime_tile_count is None else str(summary.runtime_tile_count)
    return (
        f"viewer_loadable={summary.viewer_loadable}; "
        f"scene_kind={summary.scene_kind_status}; "
        f"fragment_status={summary.fragment_status}; "
        f"hero={summary.hero_status}/{summary.hero_instruction_count}; "
        f"actors={summary.decoded_actor_count}/{summary.actor_count} decoded; "
        f"max_actor_instructions={summary.max_actor_instruction_count}; "
        f"fragment_layouts={summary.fragment_layout_count}; "
        f"runtime_tiles={runtime_tiles}; "
        f"height_grid={summary.has_runtime_height_grid}"
    )


def render_report(ranked: Sequence[RankedRoom]) -> str:
    followup_count = sum(1 for item in ranked if item.verdict == "runtime-followup")
    risk_count = sum(1 for item in ranked if item.verdict == "runtime-risk")
    decode_only_count = sum(1 for item in ranked if item.verdict == "decode-only")

    lines = [
        "Room Intelligence Triage",
        "Question: which dumped rooms are the strongest guarded-runtime follow-up targets?",
        "Rule: prefer viewer-loadable interiors, then richer fragment-zone/runtime structure, then richer decoded scripts.",
        f"Summary: runtime-followup={followup_count}, runtime-risk={risk_count}, decode-only={decode_only_count}",
        "",
    ]

    for index, item in enumerate(ranked, start=1):
        lines.append(f"{index}. {item.summary.room_label} [{item.verdict}]")
        lines.append(f"   {evidence_line(item.summary)}")
        lines.append(f"   source={item.summary.source_path}")

    return "\n".join(lines)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    summaries = [load_room_summary(Path(raw_path)) for raw_path in args.dump_paths]
    print(render_report(ranked_rooms(summaries)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(__import__("sys").argv[1:]))
