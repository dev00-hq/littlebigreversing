#!/usr/bin/env python3
"""Sidequest-only actor triage for inspect-room-intelligence dumps."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


@dataclass(frozen=True)
class ActorSummary:
    source_path: Path
    room_label: str
    scene_object_index: int
    array_index: int
    life_status: str
    life_instruction_count: int
    track_instruction_count: int
    move_speed: int
    life_points: int
    armor: int
    bonus_count: int
    file3d_index: int


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rank actors inside one inspect-room-intelligence dump by guarded-runtime follow-up value. "
            "This is a sidequest consumer and not a canonical repo interface."
        )
    )
    parser.add_argument("dump_path", help="Path to one inspect-room-intelligence JSON dump.")
    parser.add_argument("--top", type=int, default=5, help="How many ranked actors to print.")
    return parser.parse_args(argv)


def require_object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{path} must be an array")
    return value


def require_str(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{path} must be a string")
    return value


def require_int(value: Any, path: str) -> int:
    if not isinstance(value, int):
        raise ValueError(f"{path} must be an integer")
    return value


def load_actor_summaries(path: Path) -> list[ActorSummary]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    root = require_object(payload, "payload")
    selection = require_object(root.get("selection"), "selection")
    scene_selection = require_object(selection.get("scene"), "selection.scene")
    background_selection = require_object(selection.get("background"), "selection.background")
    actors = require_list(root.get("actors"), "actors")

    room_label = (
        f"{require_int(scene_selection.get('resolved_entry_index'), 'selection.scene.resolved_entry_index')}/"
        f"{require_int(background_selection.get('resolved_entry_index'), 'selection.background.resolved_entry_index')}"
    )

    summaries: list[ActorSummary] = []
    for actor_index, actor_value in enumerate(actors):
        actor = require_object(actor_value, f"actors[{actor_index}]")
        life = require_object(actor.get("life"), f"actors[{actor_index}].life")
        life_audit = require_object(life.get("audit"), f"actors[{actor_index}].life.audit")
        track = require_object(actor.get("track"), f"actors[{actor_index}].track")
        mapped = require_object(actor.get("mapped"), f"actors[{actor_index}].mapped")
        movement = require_object(mapped.get("movement"), f"actors[{actor_index}].mapped.movement")
        combat = require_object(mapped.get("combat"), f"actors[{actor_index}].mapped.combat")
        render_source = require_object(mapped.get("render_source"), f"actors[{actor_index}].mapped.render_source")

        summaries.append(
            ActorSummary(
                source_path=path,
                room_label=room_label,
                scene_object_index=require_int(
                    actor.get("scene_object_index"),
                    f"actors[{actor_index}].scene_object_index",
                ),
                array_index=require_int(actor.get("array_index"), f"actors[{actor_index}].array_index"),
                life_status=require_str(life_audit.get("status"), f"actors[{actor_index}].life.audit.status"),
                life_instruction_count=require_int(
                    life_audit.get("instruction_count"),
                    f"actors[{actor_index}].life.audit.instruction_count",
                ),
                track_instruction_count=require_int(
                    track.get("instruction_count"),
                    f"actors[{actor_index}].track.instruction_count",
                ),
                move_speed=require_int(movement.get("move"), f"actors[{actor_index}].mapped.movement.move"),
                life_points=require_int(combat.get("life_points"), f"actors[{actor_index}].mapped.combat.life_points"),
                armor=require_int(combat.get("armor"), f"actors[{actor_index}].mapped.combat.armor"),
                bonus_count=require_int(
                    combat.get("bonus_count"),
                    f"actors[{actor_index}].mapped.combat.bonus_count",
                ),
                file3d_index=require_int(
                    render_source.get("file3d_index"),
                    f"actors[{actor_index}].mapped.render_source.file3d_index",
                ),
            )
        )

    return summaries


def actor_sort_key(actor: ActorSummary) -> tuple[int, int, int, int, int, int]:
    combat_weight = actor.life_points + actor.armor + actor.bonus_count
    return (
        1 if actor.life_status == "decoded" else 0,
        actor.life_instruction_count,
        actor.track_instruction_count,
        1 if actor.move_speed > 0 else 0,
        combat_weight,
        -actor.scene_object_index,
    )


def classify_actor(actor: ActorSummary) -> str:
    if actor.life_status != "decoded":
        return "decode-risk"
    if actor.life_instruction_count >= 30:
        return "behavior-rich"
    if actor.life_instruction_count >= 10:
        return "behavior-present"
    return "minimal"


def render_report(actors: Sequence[ActorSummary], top_n: int) -> str:
    ranked = sorted(actors, key=actor_sort_key, reverse=True)
    room_label = ranked[0].room_label if ranked else "unknown"
    top = ranked[:top_n]

    lines = [
        "Room Actor Triage",
        "Question: which actors are the strongest guarded-runtime follow-up targets?",
        "Rule: prefer decoded life, then richer life logic, then richer track logic, then movement/combat as tie-breakers.",
        f"Room: {room_label}",
        f"Actor count: {len(ranked)}",
        "",
    ]

    for index, actor in enumerate(top, start=1):
        lines.append(f"{index}. actor {actor.scene_object_index} [{classify_actor(actor)}]")
        lines.append(
            "   "
            f"life={actor.life_status}/{actor.life_instruction_count}; "
            f"track={actor.track_instruction_count}; "
            f"move={actor.move_speed}; "
            f"life_points={actor.life_points}; "
            f"armor={actor.armor}; "
            f"bonus={actor.bonus_count}; "
            f"file3d={actor.file3d_index}; "
            f"array_index={actor.array_index}"
        )

    return "\n".join(lines)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    actors = load_actor_summaries(Path(args.dump_path))
    print(render_report(actors, top_n=args.top))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(__import__("sys").argv[1:]))
