from __future__ import annotations

import argparse
import csv
import ctypes
import hashlib
import json
import queue
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox
import tkinter as tk
from tkinter import ttk
from typing import Any, Iterable

try:
    from PIL import Image, ImageTk
except ModuleNotFoundError:
    Image = None
    ImageTk = None


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME_DIR = (
    REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2"
)
DEFAULT_EXE = DEFAULT_GAME_DIR / "LBA2.EXE"
DEFAULT_SAVE_DIR = DEFAULT_GAME_DIR / "SAVE"
DEFAULT_RESS = DEFAULT_GAME_DIR / "RESS.HQR"
DEFAULT_SCENE_ROOT = Path(r"D:\repos\idajs\Ida\srcjs\lba2editor")
DEFAULT_PROFILE_MANIFESTS = (
    DEFAULT_SAVE_DIR / "save_profiles.json",
    REPO_ROOT / "work" / "saves" / "save_profiles.json",
)
SAVE_COMPRESS = 0x80
SAVE_IMAGE_SIZE = 160 * 120
PALETTE_COLOR_COUNT = 256
PALETTE_PAYLOAD_SIZE = PALETTE_COLOR_COUNT * 3
MAX_VARS_GAME = 256
MAX_VARS_CUBE = 80
MAX_OBJECTIF = 50
MAX_CUBE = 255
MAX_INVENTORY = 40
MAX_DARTS = 3

WINDOW_SIZE = 1 << 12
BREAK_EVEN = (1 + 12 + 4) // 9

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

COUNT_FILTER_RE = re.compile(
    r"\b(?P<field>npcs?|total_?npcs?|all_?npcs?|deferred_?npcs?|objects?|object_?slots?|slots?)"
    r"\s*(?P<op>>=|<=|>|<|=|:)\s*(?P<count>\d+)\b",
    re.IGNORECASE,
)

FLAG_NAMES = {
    0: "Holomap",
    1: "Magic Ball",
    2: "Darts",
    3: "Sendell's Ball",
    4: "Tunic",
    5: "Pearl",
    6: "Pyramid key",
    7: "Car part",
    8: "Money",
    9: "Pisto-Laser",
    10: "Saber",
    11: "Glove",
    12: "Proto-Pack",
    13: "Ferry ticket",
    14: "Mechanical penguin",
    15: "GazoGem",
    16: "Medallion half",
    17: "Gallic acid",
    18: "Song",
    19: "Lightning ring",
    20: "Umbrella",
    21: "Gem",
    22: "Conch",
    23: "Blowgun",
    24: "Route disk / ACF viewer",
    25: "Luci tart",
    26: "Radio",
    27: "Flower",
    28: "Magic slate",
    29: "Translator",
    30: "Diploma",
    31: "Dark Monk key (Knarta)",
    32: "Dark Monk key (Sup)",
    33: "Dark Monk key (Mosqui)",
    34: "Dark Monk key (Island CX)",
    35: "Queen key",
    36: "Pickaxe",
    37: "Mayor key",
    38: "Mayor note",
    39: "Protection spell",
    40: "Diving suit",
    79: "Celebration",
    94: "Dino voyage",
    251: "Clover count",
    252: "Vehicle taken",
    253: "Chapter",
    254: "Emerald Moon planet",
}

WEAPON_NAMES = {
    1: "Magic Ball",
    2: "Darts",
    9: "Pisto-Laser",
    10: "Saber",
    11: "Glove",
    22: "Conch",
    23: "Blowgun",
}

READY_WINDOW_TIMEOUT_SEC = 20.0
READY_POLL_SEC = 0.15
RESOURCE_HEADER_SIZE = 10


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


@dataclass(frozen=True)
class KnownNpcEvidence:
    visible_count: int
    deferred_count: int = 0
    visible_names: tuple[str, ...] = ()
    deferred_names: tuple[str, ...] = ()
    note: str = ""


KNOWN_NPC_EVIDENCE_BY_SAVE = {
    "newgame.lba": KnownNpcEvidence(
        visible_count=1,
        visible_names=("Zoe",),
        note="Twinsen's House start-state evidence: the saved non-hero slots include only Zoe as a real NPC.",
    ),
    "01-farm-first.lba": KnownNpcEvidence(
        visible_count=2,
        deferred_count=1,
        visible_names=("Pharmacist lady", "Pharmacy customer lady"),
        deferred_names=("Scripted pharmacy visitor after pharmacist dialog",),
        note="Pharmacy save-state evidence: two visible NPCs at load, plus one scripted NPC after speaking with the pharmacist.",
    ),
    "05-up-elevator.lba": KnownNpcEvidence(
        visible_count=2,
        visible_names=("Franco guard", "Franco guard"),
        note="Upper City elevator save-state evidence: two living Franco NPC slots; other non-hero slots are props, triggers, inactive actors, or removed enemies.",
    ),
}


@dataclass
class SaveContext:
    parsed: bool = False
    error: str | None = None
    magic_level: int | None = None
    magic_points: int | None = None
    little_keys: int | None = None
    clover_boxes: int | None = None
    gold_pieces: int | None = None
    zlitos_pieces: int | None = None
    scene_start: tuple[int, int, int] | None = None
    start_cube: tuple[int, int, int] | None = None
    weapon: int | None = None
    behavior: int | None = None
    hero_behavior: int | None = None
    hero_body: int | None = None
    saved_object_count: int | None = None
    non_hero_saved_object_count: int | None = None
    npc_count: int | None = None
    deferred_npc_count: int | None = None
    npc_names: list[str] = field(default_factory=list)
    deferred_npc_names: list[str] = field(default_factory=list)
    npc_evidence_note: str | None = None
    chapter: int | None = None
    clovers: int | None = None
    notable_flags: list[str] = field(default_factory=list)
    inventory_model_ids: list[int] = field(default_factory=list)


@dataclass
class SaveEntry:
    path: Path
    file_name: str
    file_size: int
    mtime: float
    version_byte: int
    num_cube: int
    raw_scene_entry_index: int
    save_name: str
    payload: bytes | None
    embedded_image: bytes | None
    context: SaveContext
    scene: SceneRecord | None = None
    profile: dict[str, Any] | None = None
    digest: str = ""

    @property
    def title(self) -> str:
        return self.save_name or self.path.stem

    @property
    def location_label(self) -> str:
        if self.scene is None:
            return f"Cube {self.num_cube} / raw scene {self.raw_scene_entry_index}"
        bits = [self.scene.scene_name]
        if self.scene.section and self.scene.section != self.scene.scene_name:
            bits.append(self.scene.section)
        if self.scene.island:
            bits.append(self.scene.island)
        if self.scene.planet:
            bits.append(self.scene.planet)
        return " - ".join(bits)

    @property
    def search_text(self) -> str:
        profile_bits: list[str] = []
        if self.profile is not None:
            profile_bits.extend(
                str(self.profile.get(key, ""))
                for key in ("profile_id", "proof_goal", "scene_name", "section", "planet", "island")
            )
            spec = self.profile.get("generation_spec")
            if isinstance(spec, dict):
                profile_bits.extend(str(value) for value in spec.values())

        context_bits = [
            self.title,
            self.file_name,
            self.location_label,
            f"cube {self.num_cube}",
            f"raw scene {self.raw_scene_entry_index}",
            f"npcs {self.context.npc_count}" if self.context.npc_count is not None else "",
            f"deferred npcs {self.context.deferred_npc_count}" if self.context.deferred_npc_count else "",
            f"objects {self.context.non_hero_saved_object_count}"
            if self.context.non_hero_saved_object_count is not None
            else "",
            f"slots {self.context.saved_object_count}" if self.context.saved_object_count is not None else "",
            *self.context.npc_names,
            *self.context.deferred_npc_names,
            *(self.context.notable_flags if self.context else []),
            *profile_bits,
        ]
        return " ".join(bit for bit in context_bits if bit).lower()


class BinaryReader:
    def __init__(self, data: bytes, offset: int = 0) -> None:
        self.data = data
        self.offset = offset

    def need(self, size: int) -> None:
        if self.offset + size > len(self.data):
            raise ValueError("save context ended before the expected field")

    def read_u8(self) -> int:
        self.need(1)
        value = self.data[self.offset]
        self.offset += 1
        return value

    def read_s16(self) -> int:
        self.need(2)
        value = int.from_bytes(self.data[self.offset : self.offset + 2], "little", signed=True)
        self.offset += 2
        return value

    def read_u16(self) -> int:
        self.need(2)
        value = int.from_bytes(self.data[self.offset : self.offset + 2], "little", signed=False)
        self.offset += 2
        return value

    def read_s32(self) -> int:
        self.need(4)
        value = int.from_bytes(self.data[self.offset : self.offset + 4], "little", signed=True)
        self.offset += 4
        return value

    def skip(self, size: int) -> None:
        self.need(size)
        self.offset += size


def parse_hqr_classic_entry(data: bytes, classic_index: int) -> bytes:
    if len(data) < 8:
        raise ValueError("HQR archive is too small")
    table_end = int.from_bytes(data[:4], "little", signed=False)
    if table_end < 8 or table_end % 4 or table_end > len(data):
        raise ValueError("invalid HQR table header")
    entry_table_offset = classic_index * 4
    if entry_table_offset >= table_end:
        raise ValueError(f"HQR entry index out of range: {classic_index}")
    offset = int.from_bytes(data[entry_table_offset : entry_table_offset + 4], "little", signed=False)
    if offset == 0:
        raise ValueError(f"empty HQR entry: {classic_index}")
    if offset < table_end or offset > len(data):
        raise ValueError(f"invalid HQR entry offset: {offset}")
    next_offset = len(data)
    for cursor in range(entry_table_offset + 4, table_end, 4):
        candidate = int.from_bytes(data[cursor : cursor + 4], "little", signed=False)
        if candidate == 0 or candidate <= offset:
            continue
        if candidate > len(data):
            raise ValueError(f"invalid HQR next-entry offset: {candidate}")
        next_offset = min(next_offset, candidate)
    return data[offset:next_offset]


def decode_uncompressed_resource_entry(raw_entry: bytes) -> bytes:
    if len(raw_entry) < RESOURCE_HEADER_SIZE:
        raise ValueError("truncated resource header")
    size_file = int.from_bytes(raw_entry[:4], "little", signed=False)
    compressed_size_file = int.from_bytes(raw_entry[4:8], "little", signed=False)
    compress_method = int.from_bytes(raw_entry[8:10], "little", signed=False)
    if compress_method != 0:
        raise ValueError(f"unsupported compressed resource entry: method {compress_method}")
    if compressed_size_file != size_file:
        raise ValueError("uncompressed resource header has mismatched sizes")
    payload = raw_entry[RESOURCE_HEADER_SIZE:]
    if len(payload) < size_file:
        raise ValueError("truncated resource payload")
    return payload[:size_file]


def load_lba2_palette(ress_path: Path = DEFAULT_RESS) -> list[int] | None:
    try:
        raw_entry = parse_hqr_classic_entry(ress_path.read_bytes(), 0)
        palette_payload = decode_uncompressed_resource_entry(raw_entry)
    except (OSError, ValueError):
        return None
    if len(palette_payload) != PALETTE_PAYLOAD_SIZE:
        return None
    return list(palette_payload)


LBA2_PALETTE = load_lba2_palette()


def scale_to_fit(image: Any, size: tuple[int, int], resample: Any) -> Any:
    source_width, source_height = image.size
    target_width, target_height = size
    scale = min(target_width / source_width, target_height / source_height)
    scaled_size = (
        max(1, round(source_width * scale)),
        max(1, round(source_height * scale)),
    )
    return image.resize(scaled_size, resample)


def unquote_scene_value(value: str) -> str:
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
    if not scene_root.exists():
        return records

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
                current_planet = unquote_scene_value(first)
                current_island = None
                current_section = None
                iso_stack.clear()
                continue
            if kind == "island":
                current_island = unquote_scene_value(second or "")
                current_section = None
                iso_stack.clear()
                continue
            if kind == "section":
                section_id = int(first, 10)
                current_section = unquote_scene_value(second or "")
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
            scene_name = unquote_scene_value(second or "")
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


def lzss_decompress_mode2(data: bytes, expected_size: int) -> bytes:
    window = bytearray(WINDOW_SIZE)
    current_position = 0
    out = bytearray()
    source = 0

    while source < len(data) and len(out) < expected_size:
        flags = data[source]
        source += 1
        mask = 1
        for _ in range(8):
            if len(out) >= expected_size or source >= len(data):
                break
            if flags & mask:
                value = data[source]
                source += 1
                out.append(value)
                window[current_position] = value
                current_position = (current_position + 1) & (WINDOW_SIZE - 1)
            else:
                if source + 2 > len(data):
                    break
                token = int.from_bytes(data[source : source + 2], "little")
                source += 2
                distance = token >> 4
                length = (token & 0x0F) + BREAK_EVEN + 1
                match_position = (current_position - distance - 1) & (WINDOW_SIZE - 1)
                for index in range(length):
                    value = window[(match_position + index) & (WINDOW_SIZE - 1)]
                    out.append(value)
                    window[current_position] = value
                    current_position = (current_position + 1) & (WINDOW_SIZE - 1)
                    if len(out) >= expected_size:
                        break
            mask <<= 1

    if len(out) != expected_size:
        raise ValueError(f"decompressed {len(out)} bytes, expected {expected_size}")
    return bytes(out)


def decode_ascii_z(data: bytes, start: int) -> tuple[str, int]:
    end = data.find(b"\x00", start)
    if end == -1:
        end = len(data)
    return data[start:end].decode("ascii", errors="replace"), min(end + 1, len(data))


def parse_save_payload(data: bytes, offset: int, compressed: bool) -> bytes:
    if compressed:
        if offset + 4 > len(data):
            raise ValueError("compressed save has no decompressed-size field")
        expected_size = int.from_bytes(data[offset : offset + 4], "little", signed=True)
        if expected_size <= 0:
            raise ValueError(f"invalid decompressed-size field: {expected_size}")
        return lzss_decompress_mode2(data[offset + 4 :], expected_size)
    return data[offset:]


def parse_context(payload: bytes) -> SaveContext:
    context = SaveContext()
    if len(payload) < SAVE_IMAGE_SIZE:
        context.error = "payload is smaller than the embedded 160x120 preview"
        return context

    reader = BinaryReader(payload, SAVE_IMAGE_SIZE)
    try:
        list_var_game = [reader.read_s16() for _ in range(MAX_VARS_GAME)]
        _list_var_cube = [reader.read_u8() for _ in range(MAX_VARS_CUBE)]

        context.behavior = reader.read_u8()
        money = reader.read_s32()
        context.gold_pieces = money & 0xFFFF
        context.zlitos_pieces = (money >> 16) & 0xFFFF
        context.magic_level = reader.read_u8()
        context.magic_points = reader.read_u8()
        context.little_keys = reader.read_u8()
        context.clover_boxes = reader.read_u16()
        context.scene_start = (reader.read_s32(), reader.read_s32(), reader.read_s32())
        context.start_cube = (reader.read_s32(), reader.read_s32(), reader.read_s32())
        context.weapon = reader.read_u8()
        reader.read_s32()  # saved timer
        reader.read_u8()  # NumObjFollow
        context.hero_behavior = reader.read_u8()
        context.hero_body = reader.read_u8()

        reader.skip(MAX_OBJECTIF + MAX_CUBE)

        inventory_model_ids: list[int] = []
        for _ in range(MAX_INVENTORY):
            _magic_cost = reader.read_s32()
            flag_inv = reader.read_s32()
            model_id = reader.read_u16()
            if flag_inv:
                inventory_model_ids.append(model_id)
        context.inventory_model_ids = inventory_model_ids[:12]

        reader.skip(
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
            + MAX_DARTS * (7 * 4)
        )
        context.saved_object_count = reader.read_s32()
        if context.saved_object_count < 0 or context.saved_object_count > 100:
            raise ValueError(f"implausible saved object count: {context.saved_object_count}")
        context.non_hero_saved_object_count = max(context.saved_object_count - 1, 0)

        context.chapter = list_var_game[253]
        context.clovers = list_var_game[251]
        notable_flags: list[str] = []
        for index, name in FLAG_NAMES.items():
            if 0 <= index < len(list_var_game) and list_var_game[index]:
                notable_flags.append(f"{name}: {list_var_game[index]}")
        context.notable_flags = notable_flags[:18]
        context.parsed = True
        return context
    except ValueError as error:
        context.error = str(error)
        return context


def apply_known_npc_evidence(file_name: str, context: SaveContext) -> None:
    evidence = KNOWN_NPC_EVIDENCE_BY_SAVE.get(file_name.lower())
    if evidence is None:
        return
    context.npc_count = evidence.visible_count
    context.deferred_npc_count = evidence.deferred_count
    context.npc_names = list(evidence.visible_names)
    context.deferred_npc_names = list(evidence.deferred_names)
    context.npc_evidence_note = evidence.note


def parse_save(path: Path, scene_lookup: dict[int, SceneRecord], profile_lookup: dict[str, dict[str, Any]]) -> SaveEntry:
    data = path.read_bytes()
    if len(data) < 6:
        raise ValueError(f"save file too short: {path}")

    version_byte = data[0]
    compressed = bool(version_byte & SAVE_COMPRESS)
    num_cube = int.from_bytes(data[1:5], "little", signed=True)
    save_name, payload_offset = decode_ascii_z(data, 5)
    payload: bytes | None = None
    embedded_image: bytes | None = None
    context = SaveContext()
    try:
        payload = parse_save_payload(data, payload_offset, compressed)
        embedded_image = payload[:SAVE_IMAGE_SIZE] if len(payload) >= SAVE_IMAGE_SIZE else None
        context = parse_context(payload)
        apply_known_npc_evidence(path.name, context)
    except ValueError as error:
        context.error = str(error)

    digest = hashlib.sha1(data).hexdigest()

    return SaveEntry(
        path=path,
        file_name=path.name,
        file_size=path.stat().st_size,
        mtime=path.stat().st_mtime,
        version_byte=version_byte,
        num_cube=num_cube,
        raw_scene_entry_index=num_cube + 2,
        save_name=save_name,
        payload=payload,
        embedded_image=embedded_image,
        context=context,
        scene=scene_lookup.get(num_cube),
        profile=profile_lookup.get(path.name.lower()),
        digest=digest,
    )


def load_profile_lookup(paths: Iterable[Path]) -> dict[str, dict[str, Any]]:
    lookup: dict[str, dict[str, Any]] = {}
    for path in paths:
        if not path.exists():
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        profiles = payload.get("profiles")
        if not isinstance(profiles, list):
            continue
        for profile in profiles:
            if not isinstance(profile, dict):
                continue
            examples = profile.get("known_example_saves") or []
            if isinstance(examples, list):
                for name in examples:
                    if isinstance(name, str) and name:
                        lookup.setdefault(name.lower(), profile)
    return lookup


def discover_saves(save_dir: Path, scene_lookup: dict[int, SceneRecord], profile_lookup: dict[str, dict[str, Any]]) -> list[SaveEntry]:
    if not save_dir.exists():
        raise FileNotFoundError(f"save folder does not exist: {save_dir}")
    paths = sorted(
        [
            *save_dir.glob("*.LBA"),
            *save_dir.glob("*.lba"),
        ],
        key=lambda path: (path.name.lower() not in {"current.lba", "autosave.lba"}, path.name.lower()),
    )
    entries: list[SaveEntry] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        try:
            entries.append(parse_save(path, scene_lookup, profile_lookup))
        except Exception as error:
            data = path.read_bytes() if path.exists() else b""
            digest = hashlib.sha1(data).hexdigest() if data else ""
            entries.append(
                SaveEntry(
                    path=path,
                    file_name=path.name,
                    file_size=path.stat().st_size,
                    mtime=path.stat().st_mtime,
                    version_byte=data[0] if data else 0,
                    num_cube=0,
                    raw_scene_entry_index=2,
                    save_name=path.stem,
                    payload=None,
                    embedded_image=None,
                    context=SaveContext(error=str(error)),
                    digest=digest,
                )
            )
    return entries


def tasklist_pids(image_name: str) -> list[int]:
    completed = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return []
    pids: list[int] = []
    for row in csv.reader(line for line in completed.stdout.splitlines() if line.strip()):
        if len(row) < 2:
            continue
        try:
            pids.append(int(row[1]))
        except ValueError:
            continue
    return pids


def kill_lba2() -> list[int]:
    pids = tasklist_pids("LBA2.EXE")
    if not pids:
        return []
    completed = subprocess.run(
        ["taskkill", "/IM", "LBA2.EXE", "/F"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise RuntimeError(f"taskkill failed for LBA2.EXE: {detail or completed.returncode}")
    return pids


def direct_save_argument(game_dir: Path, save_dir: Path, save_path: Path) -> str:
    try:
        relative = save_path.resolve().relative_to(game_dir.resolve())
        return str(relative)
    except ValueError:
        try:
            relative = save_path.resolve().relative_to(save_dir.resolve())
            return str(Path("SAVE") / relative)
        except ValueError:
            return str(save_path.resolve())


def delete_autosave_before_direct_launch(save_dir: Path, selected: Path) -> bool:
    autosave = save_dir / "autosave.lba"
    if selected.name.lower() == "autosave.lba" or not autosave.exists():
        return False
    autosave.unlink()
    return True


EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)


def window_for_pid(pid: int) -> int | None:
    user32 = ctypes.windll.user32
    matches: list[int] = []

    def callback(hwnd: int, _lparam: int) -> bool:
        if not user32.IsWindowVisible(hwnd):
            return True
        process_id = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
        if process_id.value == pid:
            length = user32.GetWindowTextLengthW(hwnd)
            if length >= 0:
                matches.append(hwnd)
        return True

    user32.EnumWindows(EnumWindowsProc(callback), 0)
    return matches[0] if matches else None


def wait_for_window(pid: int, timeout_sec: float = READY_WINDOW_TIMEOUT_SEC) -> int:
    deadline = time.monotonic() + timeout_sec
    while time.monotonic() < deadline:
        hwnd = window_for_pid(pid)
        if hwnd is not None:
            return hwnd
        time.sleep(READY_POLL_SEC)
    raise RuntimeError(f"no visible LBA2 window found for pid {pid}")


def activate_window(hwnd: int) -> None:
    user32 = ctypes.windll.user32
    sw_restore = 9
    hwnd_topmost = ctypes.c_void_p(-1)
    hwnd_notopmost = ctypes.c_void_p(-2)
    swp_nomove = 0x0002
    swp_nosize = 0x0001
    try:
        user32.ShowWindow(hwnd, sw_restore)
        user32.SetWindowPos(hwnd, hwnd_topmost, 0, 0, 0, 0, swp_nomove | swp_nosize)
        user32.SetWindowPos(hwnd, hwnd_notopmost, 0, 0, 0, 0, swp_nomove | swp_nosize)
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
    except Exception:
        pass
    time.sleep(0.25)


def send_enter_to_pid(pid: int) -> None:
    hwnd = wait_for_window(pid)
    activate_window(hwnd)
    user32 = ctypes.windll.user32
    keyeventf_keyup = 0x0002
    vk_return = 0x0D
    scan_code = int(user32.MapVirtualKeyW(vk_return, 0))
    user32.keybd_event(vk_return, scan_code, 0, 0)
    time.sleep(0.05)
    user32.keybd_event(vk_return, scan_code, keyeventf_keyup, 0)


def launch_save(
    exe_path: Path,
    game_dir: Path,
    save_dir: Path,
    entry: SaveEntry,
    status: callable,
) -> None:
    if not exe_path.exists():
        raise RuntimeError(f"LBA2.EXE not found: {exe_path}")
    if not entry.path.exists():
        raise RuntimeError(f"save file not found: {entry.path}")

    killed = kill_lba2()
    if killed:
        status(f"killed running LBA2.EXE pid(s): {', '.join(str(pid) for pid in killed)}")
    else:
        status("no running LBA2.EXE process found")

    if delete_autosave_before_direct_launch(save_dir, entry.path):
        status("deleted autosave.lba before direct launch")
    save_arg = direct_save_argument(game_dir, save_dir, entry.path)
    process = subprocess.Popen([str(exe_path), save_arg], cwd=str(game_dir))
    status(f"launched {entry.file_name} as pid {process.pid}")

    def finish_startup() -> None:
        try:
            send_enter_to_pid(process.pid)
            status("sent Enter through the Adeline splash")
        except Exception as error:
            status(f"automatic splash advance skipped: {error}")

    threading.Thread(target=finish_startup, daemon=True).start()


def extract_count_filters(query: str) -> tuple[list[tuple[str, str, int]], str]:
    filters: list[tuple[str, str, int]] = []

    def remember(match: re.Match[str]) -> str:
        op = match.group("op")
        if op == ":":
            op = "="
        filters.append((match.group("field").lower(), op, int(match.group("count"))))
        return " "

    cleaned = COUNT_FILTER_RE.sub(remember, query)
    return filters, cleaned


def matches_count_filters(entry: SaveEntry, filters: list[tuple[str, str, int]]) -> bool:
    if not filters:
        return True
    for field, op, expected in filters:
        normalized_field = field.replace("_", "")
        if normalized_field in {"totalnpc", "totalnpcs", "allnpc", "allnpcs"}:
            if entry.context.npc_count is None:
                return False
            actual = entry.context.npc_count + (entry.context.deferred_npc_count or 0)
        elif normalized_field in {"deferrednpc", "deferrednpcs"}:
            actual = entry.context.deferred_npc_count
        elif normalized_field in {"object", "objects"}:
            actual = entry.context.non_hero_saved_object_count
        elif normalized_field in {"objectslots", "slot", "slots"}:
            actual = entry.context.saved_object_count
        else:
            actual = entry.context.npc_count
        if actual is None:
            return False
        if op == "=" and actual != expected:
            return False
        if op == ">" and actual <= expected:
            return False
        if op == ">=" and actual < expected:
            return False
        if op == "<" and actual >= expected:
            return False
        if op == "<=" and actual > expected:
            return False
    return True


def score_entry(entry: SaveEntry, query: str, semantic: bool) -> int:
    normalized = query.strip().lower()
    count_filters, text_query = extract_count_filters(normalized)
    if not matches_count_filters(entry, count_filters):
        return 0
    text_query = text_query.strip()
    if not text_query:
        return 100 if count_filters else 1
    if not normalized:
        return 1
    haystack = entry.search_text
    words = [word for word in re.split(r"[^a-z0-9']+", text_query) if word]
    if not words:
        return 100 if count_filters else 1

    if not semantic:
        return 100 if text_query in haystack or all(word in haystack for word in words) else 0

    expansions = {
        "ball": ["magic ball", "sendell", "sphere"],
        "cellar": ["cave", "basement", "key", "cube"],
        "wizard": ["magic", "school", "diploma", "robe"],
        "moon": ["emerald", "zeelich"],
        "sewer": ["sendell", "treasure", "pyramid"],
        "late": ["chapter", "captured", "returned"],
        "money": ["kashes", "zlitos", "gold"],
    }
    expanded = list(words)
    for word in words:
        expanded.extend(expansions.get(word, []))

    score = 0
    for word in expanded:
        if word in haystack:
            score += 20 if word in words else 8
    if text_query in haystack:
        score += 100
    if entry.profile is not None and score:
        score += 10
    return score


class SaveLoaderApp(tk.Tk):
    def __init__(self, exe_path: Path, save_dir: Path, scene_root: Path) -> None:
        super().__init__()
        self.title("LBA2 Save Loader")
        self.geometry("1180x720")
        self.minsize(980, 580)

        self.exe_path = exe_path
        self.game_dir = exe_path.parent
        self.save_dir = save_dir
        self.scene_root = scene_root
        self.scene_lookup = parse_scene_table(scene_root)
        self.profile_lookup = load_profile_lookup(DEFAULT_PROFILE_MANIFESTS)
        self.entries: list[SaveEntry] = []
        self.filtered_entries: list[SaveEntry] = []
        self.selected: SaveEntry | None = None
        self.preview_image: Any | None = None
        self.thumbnail_images: dict[str, Any] = {}
        self.image_cache: dict[tuple[str, tuple[int, int]], Any] = {}
        self.entry_by_iid: dict[str, SaveEntry] = {}
        self.sort_column = "name"
        self.sort_descending = False
        self.ui_queue: queue.Queue[tuple[callable, tuple[Any, ...]]] = queue.Queue()

        self.search_var = tk.StringVar()
        self.semantic_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Ready")
        self.folder_var = tk.StringVar(value=str(save_dir))

        self.configure(bg="#f4f1ea")
        self.style = ttk.Style(self)
        self.style.theme_use("clam")
        self.style.configure("TFrame", background="#f4f1ea")
        self.style.configure("TLabel", background="#f4f1ea", foreground="#202124")
        self.style.configure("Accent.TButton", font=("Segoe UI", 10, "bold"), padding=(14, 8))
        self.style.configure("Tool.TButton", padding=(8, 5))
        self.style.configure("Save.Treeview", rowheight=44, font=("Segoe UI", 8))
        self.style.configure("Save.Treeview.Heading", font=("Segoe UI", 8, "bold"))
        self.build_ui()
        self.refresh_saves()
        self.after(50, self.process_ui_queue)

    def build_ui(self) -> None:
        top = ttk.Frame(self, padding=(14, 12, 14, 8))
        top.pack(fill=tk.X)

        title = ttk.Label(top, text="LBA2 Save Loader", font=("Segoe UI", 16, "bold"))
        title.pack(side=tk.LEFT, padx=(0, 16))

        search = ttk.Entry(top, textvariable=self.search_var, font=("Segoe UI", 11))
        search.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        search.insert(0, "")
        search.bind("<KeyRelease>", lambda _event: self.apply_filter())

        semantic = ttk.Checkbutton(top, text="Semantic", variable=self.semantic_var, command=self.apply_filter)
        semantic.pack(side=tk.LEFT, padx=(0, 10))

        refresh = ttk.Button(top, text="Refresh", style="Tool.TButton", command=self.refresh_saves)
        refresh.pack(side=tk.LEFT, padx=(0, 6))
        browse = ttk.Button(top, text="Folder", style="Tool.TButton", command=self.choose_folder)
        browse.pack(side=tk.LEFT)

        path_bar = ttk.Frame(self, padding=(14, 0, 14, 8))
        path_bar.pack(fill=tk.X)
        ttk.Label(path_bar, textvariable=self.folder_var, foreground="#586069").pack(side=tk.LEFT)

        body = ttk.Frame(self, padding=(14, 0, 14, 12))
        body.pack(fill=tk.BOTH, expand=True)

        left = ttk.Frame(body)
        left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 12))

        self.save_tree = ttk.Treeview(
            left,
            columns=("location", "npcs", "objects", "state"),
            show="tree headings",
            selectmode="browse",
            style="Save.Treeview",
        )
        self.save_tree.heading("#0", text="Save", command=lambda: self.sort_by_column("name"))
        self.save_tree.heading("location", text="Location", command=lambda: self.sort_by_column("location"))
        self.save_tree.heading("npcs", text="NPCs", command=lambda: self.sort_by_column("npcs"))
        self.save_tree.heading("objects", text="Objs", command=lambda: self.sort_by_column("objects"))
        self.save_tree.heading("state", text="State", command=lambda: self.sort_by_column("state"))
        self.save_tree.column("#0", width=230, minwidth=160, stretch=True)
        self.save_tree.column("location", width=285, minwidth=165, stretch=True)
        self.save_tree.column("npcs", width=54, minwidth=48, stretch=False, anchor=tk.E)
        self.save_tree.column("objects", width=54, minwidth=48, stretch=False, anchor=tk.E)
        self.save_tree.column("state", width=145, minwidth=120, stretch=False)
        self.scrollbar = ttk.Scrollbar(left, orient=tk.VERTICAL, command=self.save_tree.yview)
        self.save_tree.configure(yscrollcommand=self.scrollbar.set)
        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.save_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.save_tree.bind("<<TreeviewSelect>>", self.on_tree_select)

        self.inspector = ttk.Frame(body, width=420)
        self.inspector.pack(side=tk.RIGHT, fill=tk.BOTH)
        self.inspector.pack_propagate(False)

        self.preview_label = ttk.Label(self.inspector, text="No save selected", anchor=tk.CENTER, relief=tk.SOLID)
        self.preview_label.pack(fill=tk.X, pady=(0, 10))

        self.detail_title = ttk.Label(self.inspector, text="", font=("Segoe UI", 14, "bold"), wraplength=390)
        self.detail_title.pack(fill=tk.X, pady=(0, 4))
        self.detail_location = ttk.Label(self.inspector, text="", foreground="#52605d", wraplength=390)
        self.detail_location.pack(fill=tk.X, pady=(0, 8))

        self.detail_text = tk.Text(
            self.inspector,
            height=18,
            wrap=tk.WORD,
            bg="#fffdf8",
            fg="#202124",
            relief=tk.SOLID,
            borderwidth=1,
            padx=10,
            pady=8,
            font=("Segoe UI", 9),
        )
        self.detail_text.pack(fill=tk.BOTH, expand=True)
        self.detail_text.configure(state=tk.DISABLED)

        self.load_button = ttk.Button(self.inspector, text="Load Selected", style="Accent.TButton", command=self.load_selected)
        self.load_button.pack(fill=tk.X, pady=(10, 0))

        bottom = ttk.Frame(self, padding=(14, 0, 14, 10))
        bottom.pack(fill=tk.X)
        ttk.Label(bottom, textvariable=self.status_var, foreground="#52605d").pack(side=tk.LEFT)

    def choose_folder(self) -> None:
        folder = filedialog.askdirectory(initialdir=str(self.save_dir), title="Choose LBA2 SAVE folder")
        if not folder:
            return
        self.save_dir = Path(folder)
        self.folder_var.set(str(self.save_dir))
        self.refresh_saves()

    def enqueue_ui(self, func: callable, *args: Any) -> None:
        self.ui_queue.put((func, args))

    def process_ui_queue(self) -> None:
        while True:
            try:
                func, args = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            func(*args)
        self.after(50, self.process_ui_queue)

    def refresh_saves(self) -> None:
        try:
            self.entries = discover_saves(self.save_dir, self.scene_lookup, self.profile_lookup)
            self.status_var.set(f"Loaded {len(self.entries)} save(s)")
            self.apply_filter()
        except Exception as error:
            self.status_var.set(str(error))
            messagebox.showerror("Refresh failed", str(error))

    def apply_filter(self) -> None:
        query = self.search_var.get()
        semantic = self.semantic_var.get()
        scored = [(score_entry(entry, query, semantic), entry) for entry in self.entries]
        if query.strip():
            scored = [(score, entry) for score, entry in scored if score > 0]
        if query.strip() and self.sort_column == "relevance":
            scored.sort(key=lambda pair: (-pair[0], pair[1].file_name.lower()))
        else:
            scored.sort(key=lambda pair: self.sort_key(pair[1]))
            if self.sort_descending:
                scored.reverse()
        self.filtered_entries = [entry for _score, entry in scored]
        self.render_grid()

    def sort_by_column(self, column: str) -> None:
        if self.sort_column == column:
            self.sort_descending = not self.sort_descending
        else:
            self.sort_column = column
            self.sort_descending = False
        self.apply_filter()

    def sort_key(self, entry: SaveEntry) -> tuple[Any, ...]:
        if self.sort_column == "location":
            return (self.compact_location(entry).lower(), entry.title.lower(), entry.file_name.lower())
        if self.sort_column == "state":
            chapter = entry.context.chapter if entry.context.chapter is not None else -1
            npc_count = entry.context.npc_count if entry.context.npc_count is not None else -1
            return (chapter, npc_count, entry.title.lower(), entry.file_name.lower())
        if self.sort_column == "npcs":
            npc_count = entry.context.npc_count if entry.context.npc_count is not None else -1
            deferred = entry.context.deferred_npc_count if entry.context.deferred_npc_count is not None else -1
            return (npc_count, deferred, entry.title.lower(), entry.file_name.lower())
        if self.sort_column == "objects":
            object_count = (
                entry.context.non_hero_saved_object_count
                if entry.context.non_hero_saved_object_count is not None
                else -1
            )
            return (object_count, entry.title.lower(), entry.file_name.lower())
        return (entry.title.lower(), entry.file_name.lower())

    def render_grid(self) -> None:
        self.save_tree.delete(*self.save_tree.get_children())
        self.thumbnail_images.clear()
        self.entry_by_iid.clear()

        if not self.filtered_entries:
            self.status_var.set("No matching saves")
            return

        for index, entry in enumerate(self.filtered_entries):
            iid = f"save-{index}"
            image = self.make_tk_image(entry, (48, 36))
            self.thumbnail_images[iid] = image
            self.entry_by_iid[iid] = entry
            self.save_tree.insert(
                "",
                tk.END,
                iid=iid,
                text=self.compact_title(entry),
                image=image,
                values=(self.compact_location(entry), self.npc_meta(entry), self.object_meta(entry), self.tile_meta(entry)),
            )
            if entry == self.selected:
                self.save_tree.selection_set(iid)
                self.save_tree.see(iid)
        self.status_var.set(f"Showing {len(self.filtered_entries)} of {len(self.entries)} save(s)")

    def compact_title(self, entry: SaveEntry) -> str:
        if entry.title == entry.file_name or entry.file_name.lower().startswith(entry.title.lower()):
            return entry.title
        return f"{entry.title}  ({entry.file_name})"

    def compact_location(self, entry: SaveEntry) -> str:
        if entry.scene is None:
            return f"cube {entry.num_cube} / raw {entry.raw_scene_entry_index}"
        parts = [entry.scene.scene_name]
        if entry.scene.section and entry.scene.section != entry.scene.scene_name:
            parts.append(entry.scene.section)
        if entry.scene.planet:
            parts.append(entry.scene.planet)
        return " - ".join(parts)

    def tile_meta(self, entry: SaveEntry) -> str:
        preview = "preview" if entry.embedded_image else "no preview"
        chapter = f"chapter {entry.context.chapter}" if entry.context.chapter is not None else "chapter ?"
        return f"{chapter} - {preview}"

    def npc_meta(self, entry: SaveEntry) -> str:
        if entry.context.npc_count is None:
            return "-"
        if entry.context.deferred_npc_count:
            return f"{entry.context.npc_count}+{entry.context.deferred_npc_count}"
        return str(entry.context.npc_count)

    def object_meta(self, entry: SaveEntry) -> str:
        if entry.context.non_hero_saved_object_count is None:
            return "-"
        return str(entry.context.non_hero_saved_object_count)

    def select_entry(self, entry: SaveEntry) -> None:
        self.selected = entry
        self.render_details(entry)

    def on_tree_select(self, _event: tk.Event) -> None:
        selection = self.save_tree.selection()
        if not selection:
            return
        entry = self.entry_by_iid.get(selection[0])
        if entry is not None and entry != self.selected:
            self.select_entry(entry)

    def render_details(self, entry: SaveEntry) -> None:
        image = self.make_tk_image(entry, (400, 300))
        self.preview_label.configure(image=image, text="")
        self.preview_image = image
        self.detail_title.configure(text=entry.title)
        self.detail_location.configure(text=entry.location_label)

        lines = self.detail_lines(entry)
        self.detail_text.configure(state=tk.NORMAL)
        self.detail_text.delete("1.0", tk.END)
        self.detail_text.insert(tk.END, "\n".join(lines))
        self.detail_text.configure(state=tk.DISABLED)

    def detail_lines(self, entry: SaveEntry) -> list[str]:
        ctx = entry.context
        lines = [
            f"File: {entry.file_name}",
            f"Version: 0x{entry.version_byte:02X} {'compressed' if entry.version_byte & SAVE_COMPRESS else 'plain'}",
            f"Cube: {entry.num_cube}  Raw scene entry: {entry.raw_scene_entry_index}",
            f"Size: {entry.file_size:,} bytes",
            f"Modified: {datetime.fromtimestamp(entry.mtime).strftime('%Y-%m-%d %H:%M:%S')}",
        ]
        if entry.scene is not None:
            lines.extend(
                [
                    "",
                    "Location",
                    f"Scene: {entry.scene.scene_name}",
                    f"Section: {entry.scene.section or '-'}",
                    f"Island: {entry.scene.island or '-'}",
                    f"Planet: {entry.scene.planet}",
                    f"Scene table: {entry.scene.source_file}",
                ]
            )
        if ctx.parsed:
            weapon = WEAPON_NAMES.get(ctx.weapon or -1, str(ctx.weapon))
            lines.extend(
                [
                    "",
                    "Durable Save Context",
                    f"Chapter flag: {ctx.chapter}",
                    f"Magic: level {ctx.magic_level}, points {ctx.magic_points}",
                    f"Keys / clovers: {ctx.little_keys} little keys, {ctx.clovers}/{ctx.clover_boxes} clovers",
                    f"Money: {ctx.gold_pieces} gold, {ctx.zlitos_pieces} zlitos",
                    f"Known visible NPCs: {ctx.npc_count if ctx.npc_count is not None else 'unknown'}",
                    f"Known deferred NPCs: {ctx.deferred_npc_count if ctx.deferred_npc_count is not None else 'unknown'}",
                    f"Saved object slots: {ctx.saved_object_count} including Twinsen, "
                    f"{ctx.non_hero_saved_object_count} non-hero",
                    f"Scene start: {ctx.scene_start}",
                    f"Start cube xyz: {ctx.start_cube}",
                    f"Weapon: {weapon}",
                    f"Behavior/body: behavior={ctx.behavior}, hero_behavior={ctx.hero_behavior}, hero_body={ctx.hero_body}",
                ]
            )
            if ctx.npc_names:
                lines.extend(["", "Visible NPC Evidence", *ctx.npc_names])
            if ctx.deferred_npc_names:
                lines.extend(["", "Deferred NPC Evidence", *ctx.deferred_npc_names])
            if ctx.npc_evidence_note:
                lines.extend(["", f"NPC evidence note: {ctx.npc_evidence_note}"])
            if ctx.notable_flags:
                lines.extend(["", "Notable Flags", *ctx.notable_flags])
            if ctx.inventory_model_ids:
                joined = ", ".join(str(value) for value in ctx.inventory_model_ids)
                lines.extend(["", f"Inventory model ids: {joined}"])
        elif ctx.error:
            lines.extend(["", f"Context parse error: {ctx.error}"])
        if entry.profile is not None:
            lines.extend(["", "Matched Save Profile", str(entry.profile.get("profile_id", "-")), str(entry.profile.get("proof_goal", "-"))])
        lines.extend(["", f"Embedded preview: {'available' if entry.embedded_image else 'missing'}"])
        return lines

    def make_tk_image(self, entry: SaveEntry, size: tuple[int, int]) -> Any:
        if Image is None or ImageTk is None:
            return tk.PhotoImage(width=size[0], height=size[1])
        cache_key = (entry.digest, size)
        cached = self.image_cache.get(cache_key)
        if cached is not None:
            return cached

        image = None
        if entry.embedded_image:
            image = Image.frombytes("P", (160, 120), entry.embedded_image)
            if LBA2_PALETTE is not None:
                image.putpalette(LBA2_PALETTE)
                image = image.convert("RGB")
            else:
                image = image.convert("L").convert("RGB")
        else:
            image = Image.new("RGB", size, "#d7d2c8")

        resample = Image.Resampling.NEAREST if size[0] <= 96 or size[1] <= 72 else Image.Resampling.LANCZOS
        image = scale_to_fit(image, size, resample)
        canvas = Image.new("RGB", size, "#eee9df")
        x = (size[0] - image.width) // 2
        y = (size[1] - image.height) // 2
        canvas.paste(image, (x, y))
        photo = ImageTk.PhotoImage(canvas)
        self.image_cache[cache_key] = photo
        return photo

    def load_selected(self) -> None:
        if self.selected is None:
            messagebox.showinfo("No save selected", "Select a save first.")
            return
        entry = self.selected
        self.status_var.set(f"Launching {entry.file_name}...")

        def worker() -> None:
            try:
                launch_save(
                    self.exe_path,
                    self.game_dir,
                    self.save_dir,
                    entry,
                    lambda text: self.enqueue_ui(self.status_var.set, text),
                )
            except Exception as error:
                self.enqueue_ui(self.status_var.set, str(error))
                self.enqueue_ui(messagebox.showerror, "Launch failed", str(error))

        threading.Thread(target=worker, daemon=True).start()


def dump_json(save_dir: Path, scene_root: Path) -> None:
    scene_lookup = parse_scene_table(scene_root)
    profiles = load_profile_lookup(DEFAULT_PROFILE_MANIFESTS)
    entries = discover_saves(save_dir, scene_lookup, profiles)
    payload = []
    for entry in entries:
        payload.append(
            {
                "file_name": entry.file_name,
                "save_name": entry.save_name,
                "version_hex": f"0x{entry.version_byte:02X}",
                "num_cube": entry.num_cube,
                "raw_scene_entry_index": entry.raw_scene_entry_index,
                "scene": None
                if entry.scene is None
                else {
                    "scene_name": entry.scene.scene_name,
                    "section": entry.scene.section,
                    "island": entry.scene.island,
                    "planet": entry.scene.planet,
                },
                "context": {
                    "parsed": entry.context.parsed,
                    "chapter": entry.context.chapter,
                    "magic_level": entry.context.magic_level,
                    "magic_points": entry.context.magic_points,
                    "little_keys": entry.context.little_keys,
                    "clovers": entry.context.clovers,
                    "clover_boxes": entry.context.clover_boxes,
                    "saved_object_count": entry.context.saved_object_count,
                    "non_hero_saved_object_count": entry.context.non_hero_saved_object_count,
                    "npc_count": entry.context.npc_count,
                    "deferred_npc_count": entry.context.deferred_npc_count,
                    "npc_names": entry.context.npc_names,
                    "deferred_npc_names": entry.context.deferred_npc_names,
                    "npc_evidence_note": entry.context.npc_evidence_note,
                    "scene_start": entry.context.scene_start,
                    "start_cube": entry.context.start_cube,
                    "notable_flags": entry.context.notable_flags,
                    "error": entry.context.error,
                },
                "embedded_preview": entry.embedded_image is not None,
            }
        )
    print(json.dumps(payload, ensure_ascii=True, indent=2, sort_keys=True))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Browse and direct-launch original LBA2 savegames.")
    parser.add_argument("--exe", default=str(DEFAULT_EXE), help="Path to LBA2.EXE.")
    parser.add_argument("--save-dir", default=str(DEFAULT_SAVE_DIR), help="Original LBA2 SAVE folder.")
    parser.add_argument("--scene-root", default=str(DEFAULT_SCENE_ROOT), help="Optional IdaJS scene TypeScript root.")
    parser.add_argument("--dump-json", action="store_true", help="Print parsed save metadata and exit.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    exe_path = Path(args.exe).resolve()
    save_dir = Path(args.save_dir).resolve()
    scene_root = Path(args.scene_root).resolve()

    if args.dump_json:
        dump_json(save_dir, scene_root)
        return 0

    app = SaveLoaderApp(exe_path, save_dir, scene_root)
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
