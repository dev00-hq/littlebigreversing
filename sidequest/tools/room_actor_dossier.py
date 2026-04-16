#!/usr/bin/env python3
"""Sidequest-only actor dossier reader for inspect-room-intelligence dumps."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Sequence


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Render actor dossiers from one inspect-room-intelligence dump. "
            "This is a sidequest consumer and not a canonical repo interface."
        )
    )
    parser.add_argument("dump_path", help="Path to one inspect-room-intelligence JSON dump.")
    parser.add_argument("actor_indexes", nargs="+", type=int, help="Scene object indices to inspect.")
    return parser.parse_args(argv)


def require_object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{path} must be an array")
    return value


def require_int(value: Any, path: str) -> int:
    if not isinstance(value, int):
        raise ValueError(f"{path} must be an integer")
    return value


def require_str(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{path} must be a string")
    return value


def load_payload(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return require_object(payload, "payload")


def actor_lookup(payload: dict[str, Any]) -> dict[int, dict[str, Any]]:
    actors = require_list(payload.get("actors"), "actors")
    lookup: dict[int, dict[str, Any]] = {}
    for idx, actor_value in enumerate(actors):
        actor = require_object(actor_value, f"actors[{idx}]")
        scene_object_index = require_int(actor.get("scene_object_index"), f"actors[{idx}].scene_object_index")
        lookup[scene_object_index] = actor
    return lookup


def actor_classification(actor: dict[str, Any]) -> str:
    life = require_object(actor.get("life"), "actor.life")
    audit = require_object(life.get("audit"), "actor.life.audit")
    status = require_str(audit.get("status"), "actor.life.audit.status")
    instruction_count = require_int(audit.get("instruction_count"), "actor.life.audit.instruction_count")
    if status != "decoded":
        return "decode-risk"
    if instruction_count >= 30:
        return "behavior-rich"
    if instruction_count >= 10:
        return "behavior-present"
    return "minimal"


def track_mnemonic_preview(actor: dict[str, Any], limit: int = 8) -> str:
    track = require_object(actor.get("track"), "actor.track")
    instructions = require_list(track.get("instructions"), "actor.track.instructions")
    mnemonics: list[str] = []
    for instruction in instructions[:limit]:
        instruction_obj = require_object(instruction, "actor.track.instructions[]")
        mnemonics.append(require_str(instruction_obj.get("mnemonic"), "actor.track.instructions[].mnemonic"))
    return ", ".join(mnemonics) if mnemonics else "(no decoded track instructions)"


def room_label(payload: dict[str, Any]) -> str:
    selection = require_object(payload.get("selection"), "selection")
    scene = require_object(selection.get("scene"), "selection.scene")
    background = require_object(selection.get("background"), "selection.background")
    return (
        f"{require_int(scene.get('resolved_entry_index'), 'selection.scene.resolved_entry_index')}/"
        f"{require_int(background.get('resolved_entry_index'), 'selection.background.resolved_entry_index')}"
    )


def render_dossier(payload: dict[str, Any], actor: dict[str, Any]) -> str:
    raw = require_object(actor.get("raw"), "actor.raw")
    mapped = require_object(actor.get("mapped"), "actor.mapped")
    movement = require_object(mapped.get("movement"), "actor.mapped.movement")
    combat = require_object(mapped.get("combat"), "actor.mapped.combat")
    render_source = require_object(mapped.get("render_source"), "actor.mapped.render_source")
    life = require_object(actor.get("life"), "actor.life")
    life_audit = require_object(life.get("audit"), "actor.life.audit")
    track = require_object(actor.get("track"), "actor.track")

    index = require_int(actor.get("scene_object_index"), "actor.scene_object_index")
    array_index = require_int(actor.get("array_index"), "actor.array_index")
    classification = actor_classification(actor)

    lines = [
        f"Actor dossier: room {room_label(payload)} actor {index}",
        f"classification={classification}; array_index={array_index}",
        (
            "signals: "
            f"life={require_str(life_audit.get('status'), 'actor.life.audit.status')}/"
            f"{require_int(life_audit.get('instruction_count'), 'actor.life.audit.instruction_count')}; "
            f"track={require_int(track.get('instruction_count'), 'actor.track.instruction_count')}; "
            f"move={require_int(movement.get('move'), 'actor.mapped.movement.move')}; "
            f"life_points={require_int(combat.get('life_points'), 'actor.mapped.combat.life_points')}; "
            f"armor={require_int(combat.get('armor'), 'actor.mapped.combat.armor')}; "
            f"bonus={require_int(combat.get('bonus_count'), 'actor.mapped.combat.bonus_count')}; "
            f"file3d={require_int(render_source.get('file3d_index'), 'actor.mapped.render_source.file3d_index')}"
        ),
        f"track preview: {track_mnemonic_preview(actor)}",
        f"raw: {json.dumps(raw, sort_keys=True)}",
        f"mapped: {json.dumps(mapped, sort_keys=True)}",
        f"life: {json.dumps(life, sort_keys=True)}",
        f"track: {json.dumps(track, sort_keys=True)}",
    ]
    return "\n".join(lines)


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    payload = load_payload(Path(args.dump_path))
    lookup = actor_lookup(payload)

    outputs: list[str] = []
    for actor_index in args.actor_indexes:
        actor = lookup.get(actor_index)
        if actor is None:
            raise SystemExit(f"Unknown actor index {actor_index} in dump {args.dump_path}")
        outputs.append(render_dossier(payload, actor))

    print("\n\n".join(outputs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(__import__("sys").argv[1:]))
