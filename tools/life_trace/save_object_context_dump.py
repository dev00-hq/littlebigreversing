from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))

from lba2_save_loader import (  # noqa: E402
    SAVE_COMPRESS,
    SAVE_IMAGE_SIZE,
    decode_ascii_z,
    parse_save_payload,
)


MAX_VARS_GAME = 256
MAX_VARS_CUBE = 80
MAX_OBJECTIF = 50
MAX_CUBE = 255
MAX_INVENTORY = 40
MAX_DARTS = 3
SAVED_OBJECT_STRIDE = 276


def s16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little", signed=True)


def u16(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little", signed=False)


def s32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little", signed=True)


def u32(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little", signed=False)


def saved_object_count_offset() -> int:
    globals_len = (
        1  # Comportement
        + 4  # money
        + 1  # MagicLevel
        + 1  # MagicPoint
        + 1  # NbLittleKeys
        + 2  # NbCloverBox
        + 12  # SceneStart
        + 12  # StartCube
        + 1  # Weapon
        + 4  # savetimerrefhr
        + 1  # NumObjFollow
        + 1  # SaveComportementHero
        + 1  # SaveBodyHero
    )
    post_inventory_globals_len = (
        4  # Checksum
        + 4  # LastMyFire
        + 4  # LastMyJoy
        + 4  # LastInput
        + 4  # LastJoyFlag
        + 1  # Bulle
        + 1  # ActionNormal
        + 4  # InventoryAction
        + 4  # MagicBall
        + 1  # MagicBallType
        + 1  # MagicBallCount
        + 4  # MagicBallFlags
        + 1  # FlagClimbing
        + 4  # StartYFalling
        + 1  # CameraZone
        + 4  # InvSelect
        + 4  # ExtraConque
        + 1  # PingouinActif
        + 4  # PtrZoneClimb
    )
    return (
        SAVE_IMAGE_SIZE
        + MAX_VARS_GAME * 2
        + MAX_VARS_CUBE
        + globals_len
        + (MAX_OBJECTIF + MAX_CUBE)
        + MAX_INVENTORY * (4 + 4 + 2)
        + post_inventory_globals_len
        + MAX_DARTS * (7 * 4)
    )


def parse_saved_object(data: bytes, index: int, offset: int) -> dict[str, Any]:
    row = {
        "index": index,
        "gen_body": data[offset],
        "col": data[offset + 1],
        "gen_anim": u16(data, offset + 2),
        "next_gen_anim": u16(data, offset + 4),
        "old_x": s32(data, offset + 6),
        "old_y": s32(data, offset + 10),
        "old_z": s32(data, offset + 14),
        "info": s32(data, offset + 18),
        "info1": s32(data, offset + 22),
        "info2": s32(data, offset + 26),
        "info3": s32(data, offset + 30),
        "hit_by": data[offset + 48],
        "hit_force": data[offset + 49],
        "life_point": s16(data, offset + 50),
        "option_flags": u16(data, offset + 52),
        "sprite": s16(data, offset + 54),
        "offset_label_track": s16(data, offset + 56),
        "index_file3d": s32(data, offset + 58),
        "armor": data[offset + 62],
        "old_beta": s32(data, offset + 75),
        "offset_track": s16(data, offset + 99),
        "srot": s16(data, offset + 101),
        "offset_life": s16(data, offset + 103),
        "move": data[offset + 109],
        "obj_col": data[offset + 110],
        "zone_sce": s16(data, offset + 111),
        "label_track": s16(data, offset + 113),
        "memo_label_track": s16(data, offset + 115),
        "memo_comportement": s16(data, offset + 117),
        "flags": u32(data, offset + 119),
        "work_flags": u32(data, offset + 123),
        "door_width": s16(data, offset + 127),
        "flag_anim": data[offset + 129],
        "code_jeu": data[offset + 130],
        "exe_switch_func": data[offset + 131],
        "exe_switch_type_answer": data[offset + 132],
        "exe_switch_value": s16(data, offset + 133),
        "sample_always": s32(data, offset + 135),
        "sample_volume": data[offset + 139],
        "obj_x": s32(data, offset + 140),
        "obj_y": s32(data, offset + 144),
        "obj_z": s32(data, offset + 148),
        "obj_beta": s32(data, offset + 156),
    }
    return row


def dump_save_objects(save_path: Path) -> dict[str, Any]:
    data = save_path.read_bytes()
    compressed = bool(data[0] & SAVE_COMPRESS)
    save_name, payload_offset = decode_ascii_z(data, 5)
    payload = parse_save_payload(data, payload_offset, compressed)
    object_count_offset = saved_object_count_offset()
    object_count = s32(payload, object_count_offset)
    if object_count < 0 or object_count > 100:
        raise RuntimeError(f"implausible saved object count {object_count} at offset {object_count_offset}")
    objects_offset = object_count_offset + 4
    objects = [
        parse_saved_object(payload, index, objects_offset + index * SAVED_OBJECT_STRIDE)
        for index in range(object_count)
    ]
    return {
        "schema": "lba2-save-object-context-v1",
        "save": str(save_path),
        "save_name": save_name,
        "compressed": compressed,
        "payload_size": len(payload),
        "object_count_offset": object_count_offset,
        "saved_object_stride": SAVED_OBJECT_STRIDE,
        "object_count": object_count,
        "objects": objects,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Dump original-runtime saved object context slots from an LBA2 save.")
    parser.add_argument("save", type=Path)
    parser.add_argument("--only", type=str, default="", help="Comma-separated saved object indices to print.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = dump_save_objects(args.save.resolve())
    if args.only:
        wanted = {int(item.strip(), 0) for item in args.only.split(",") if item.strip()}
        payload["objects"] = [row for row in payload["objects"] if row["index"] in wanted]
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
