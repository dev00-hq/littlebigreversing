#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPO_ROOT / "work" / "_innoextract_full" / "Speedrun" / "Windows" / "LBA2_cdrom" / "LBA2"
SOURCE_ROOT = REPO_ROOT / "reference" / "lba2-classic" / "SOURCES"
EVIDENCE_DB = REPO_ROOT / "work" / "mbn_workbench" / "mbn_workbench.sqlite3"
PHASE0_DOCS = REPO_ROOT / "docs" / "phase0"
PHASE0_WORK = REPO_ROOT / "work" / "phase0"

ASSET_OUTPUT = PHASE0_WORK / "asset_inventory.json"
SOURCE_OUTPUT = PHASE0_WORK / "source_ownership.json"
EVIDENCE_OUTPUT = PHASE0_WORK / "evidence_bundle.json"
MANIFEST_OUTPUT = PHASE0_WORK / "phase0_manifest.json"

REQUIRED_DOCS = (
    PHASE0_DOCS / "README.md",
    PHASE0_DOCS / "canonical_inputs.md",
    PHASE0_DOCS / "golden_targets.md",
    PHASE0_DOCS / "source_ownership.md",
    PHASE0_DOCS / "unresolved_gaps.md",
)

REQUIRED_PHASE1_FILES = (
    "SCENE.HQR",
    "LBA_BKG.HQR",
    "RESS.HQR",
    "BODY.HQR",
    "ANIM.HQR",
    "SPRITES.HQR",
    "TEXT.HQR",
    "VIDEO/VIDEO.HQR",
)

LOCALE_DIRS = {
    "ENGLISH": "english",
    "FRENCH": "french",
    "GERMAN": "german",
    "ITALIAN": "italian",
    "SPANISH": "spanish",
}

VOX_PREFIX_LOCALES = {
    "DE": "german",
    "EN": "english",
    "ES": "spanish",
    "FR": "french",
    "GE": "german",
    "GR": "german",
    "IT": "italian",
}

ASSET_FAMILY_PATTERNS = (
    ("SCENE.HQR", (r"scene\.hqr", r"LoadScene\s*\(", r"PtrScene")),
    ("LBA_BKG.HQR", (r"lba_bkg\.hqr", r"BKG_HQR_NAME")),
    ("RESS.HQR", (r"ress\.hqr", r"RESS_HQR_NAME")),
    ("BODY.HQR", (r"body\.hqr", r"HQR_Bodys")),
    ("ANIM.HQR", (r"anim\.hqr", r"HQR_Anims")),
    ("SPRITES.HQR", (r"sprites\.hqr", r"HQRPtrSprite")),
    ("TEXT.HQR", (r"text\.hqr", r"NAME_HQR_TEXT")),
    ("VIDEO/VIDEO.HQR", (r"video\\\\video\.hqr", r"VIDEO\.HQR", r"PlayAcf")),
    ("VOX/*.VOX", (r"\.VOX", r"PATH_VOX_", r"InitDial")),
    ("*.ILE/*.OBL", (r"\.ILE", r"\.OBL", r"LoadIsland", r"LoadCube")),
    ("SCREEN.HQR", (r"screen\.hqr", r"SCREEN_HQR_NAME")),
    ("SAMPLES.HQR", (r"samples\.hqr", r"HQR_Samples")),
)

SOURCE_BUCKETS = (
    {
        "bucket_id": "boot-entrypoint",
        "label": "boot and entrypoint",
        "owner_files": ("PERSO.CPP", "CONFIG/MAIN.CPP"),
        "entrypoint_patterns": (r"\bWinMain\b", r"\bmain\s*\("),
        "marker_patterns": (r"\bWinMain\b", r"\bmain\s*\(", r"InitDial", r"HQR_Init_Ressource"),
    },
    {
        "bucket_id": "scene-loading",
        "label": "scene loading",
        "owner_files": ("DISKFUNC.CPP", "GRILLE.CPP", "INTEXT.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"LoadScene\s*\(", r"scene\.hqr", r"BKG_HQR_NAME", r"LoadUsedBrick"),
    },
    {
        "bucket_id": "exterior-loading",
        "label": "exterior loading",
        "owner_files": ("EXTFUNC.CPP", "3DEXT/LOADISLE.CPP", "3DEXT/TERRAIN.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"LoadIsland", r"LoadCube", r"\.ILE", r"\.OBL", r"PtrInitGrille"),
    },
    {
        "bucket_id": "object-runtime-loop",
        "label": "object/runtime loop",
        "owner_files": ("OBJECT.CPP", "PERSO.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"StartInitAllObjs", r"InitBody", r"InitAnim", r"ListObjet", r"ManageSystem"),
    },
    {
        "bucket_id": "life-scripts",
        "label": "life scripts",
        "owner_files": ("GERELIFE.CPP", "COMPORTE.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"PtrLife", r"Dial", r"InitBody", r"InitAnim", r"SaveBodyHero"),
    },
    {
        "bucket_id": "track-handling",
        "label": "track handling",
        "owner_files": ("GERETRAK.CPP", "FLOW.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"PtrTrack", r"PlayAcf", r"LoadPartFlow", r"Track"),
    },
    {
        "bucket_id": "text-voice",
        "label": "text/voice",
        "owner_files": ("MESSAGE.CPP", "INVENT.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"PATH_VOX_", r"TEXT\.HQR", r"InitDial", r"Dial", r"\.VOX"),
    },
    {
        "bucket_id": "video-playback",
        "label": "video playback",
        "owner_files": ("PLAYACF.CPP", "GERELIFE.CPP", "GERETRAK.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"PlayAcf", r"VIDEO\.HQR", r"RESS_ACFLIST"),
    },
    {
        "bucket_id": "music-audio",
        "label": "music/audio",
        "owner_files": ("AMBIANCE.CPP", "GAMEMENU.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"HQ_StopSample", r"HQR_Samples", r"Load_HQR", r"RESS_HQR_NAME", r"samples\.hqr"),
    },
    {
        "bucket_id": "save-load",
        "label": "save/load",
        "owner_files": ("SAVEGAME.CPP", "VALIDPOS.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"SaveGame", r"LoadGame", r"SaveContexte", r"LoadContexte"),
    },
    {
        "bucket_id": "config-input",
        "label": "config/input",
        "owner_files": ("CONFIG.CPP", "GAMEMENU.CPP", "PERSO.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"DefFileBuffer", r"Joystick", r"Key", r"Screen", r"PCR_MENU"),
    },
    {
        "bucket_id": "shared-hqr-resource-loading",
        "label": "shared HQR/resource loading",
        "owner_files": ("COMMON.H", "MEM.CPP", "PERSO.CPP"),
        "entrypoint_patterns": (),
        "marker_patterns": (r"RESS_HQR_NAME", r"SCREEN_HQR_NAME", r"HQR_Init_Ressource", r"LoadMalloc_HQR"),
    },
)


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True) + "\n"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def repo_relative(path: Path) -> str:
    return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()


def load_text(path: Path) -> str:
    return path.read_text(encoding="latin-1", errors="ignore")


def compile_regex(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern, re.IGNORECASE)


def find_line_matches(text: str, patterns: tuple[str, ...]) -> list[dict[str, Any]]:
    if not patterns:
        return []
    matches: list[dict[str, Any]] = []
    compiled = [compile_regex(pattern) for pattern in patterns]
    for line_no, line in enumerate(text.splitlines(), start=1):
        matched_patterns = [pattern.pattern for pattern in compiled if pattern.search(line)]
        if matched_patterns:
            matches.append(
                {
                    "line": line_no,
                    "patterns": matched_patterns,
                    "text": line.strip(),
                }
            )
    return matches


def find_first_line(path: Path, pattern: str) -> dict[str, Any]:
    regex = compile_regex(pattern)
    for line_no, line in enumerate(load_text(path).splitlines(), start=1):
        if regex.search(line):
            return {
                "kind": "classic_source",
                "line": line_no,
                "path": repo_relative(path),
                "text": line.strip(),
            }
    raise SystemExit(f"Pattern not found in {repo_relative(path)}: {pattern}")


def find_first_doc_line(path: Path, pattern: str) -> dict[str, Any]:
    regex = compile_regex(pattern)
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if regex.search(line):
            return {
                "kind": "checked_in_doc",
                "line": line_no,
                "path": repo_relative(path),
                "text": line.strip(),
            }
    raise SystemExit(f"Pattern not found in {repo_relative(path)}: {pattern}")


def ensure_roots() -> None:
    if not ASSET_ROOT.is_dir():
        raise SystemExit(f"Missing canonical asset root: {repo_relative(ASSET_ROOT)}")
    if not SOURCE_ROOT.is_dir():
        raise SystemExit(f"Missing classic source root: {repo_relative(SOURCE_ROOT)}")
    if not EVIDENCE_DB.is_file():
        raise SystemExit(f"Missing evidence database: {repo_relative(EVIDENCE_DB)}")


def required_vox_files() -> list[Path]:
    vox_dir = ASSET_ROOT / "VOX"
    if not vox_dir.is_dir():
        raise SystemExit(f"Missing VOX directory: {repo_relative(vox_dir)}")
    vox_files = sorted((path for path in vox_dir.glob("*.VOX") if path.is_file()), key=lambda path: path.name.lower())
    if not vox_files:
        raise SystemExit("No canonical VOX files found under the canonical asset root")
    return vox_files


def island_pair_summary() -> list[dict[str, Any]]:
    stems: dict[str, set[str]] = {}
    for path in ASSET_ROOT.iterdir():
        if not path.is_file():
            continue
        suffix = path.suffix.upper()
        if suffix not in {".ILE", ".OBL"}:
            continue
        stems.setdefault(path.stem.upper(), set()).add(suffix)
    if not stems:
        raise SystemExit("No canonical island .ILE/.OBL files found in the asset root")
    pairs: list[dict[str, Any]] = []
    for stem in sorted(stems):
        suffixes = stems[stem]
        if suffixes != {".ILE", ".OBL"}:
            raise SystemExit(f"Incomplete island pair for {stem}: found {sorted(suffixes)}")
        pairs.append(
            {
                "ile_path": f"{stem}.ILE",
                "obl_path": f"{stem}.OBL",
                "stem": stem,
            }
        )
    return pairs


def detect_locale(relative_path: str) -> str | None:
    parts = relative_path.split("/")
    if parts[0].upper() in LOCALE_DIRS:
        return LOCALE_DIRS[parts[0].upper()]
    if parts[0].upper() == "VOX" and len(parts) > 1:
        stem = Path(parts[1]).stem.upper()
        prefix = stem.split("_", 1)[0]
        return VOX_PREFIX_LOCALES.get(prefix)
    return None


def classify_asset(relative_path: str) -> str:
    upper = relative_path.upper()
    if upper == "SCENE.HQR":
        return "scene-hqr"
    if upper == "LBA_BKG.HQR":
        return "background-hqr"
    if upper == "RESS.HQR":
        return "resource-hqr"
    if upper == "BODY.HQR":
        return "body-hqr"
    if upper == "ANIM.HQR":
        return "animation-hqr"
    if upper == "SPRITES.HQR":
        return "sprite-hqr"
    if upper == "TEXT.HQR":
        return "text-hqr"
    if upper == "VIDEO/VIDEO.HQR":
        return "video-hqr"
    if upper.endswith(".HQR"):
        return "hqr-container"
    if upper.endswith(".VOX"):
        return "voice-container"
    if upper.endswith(".ILE"):
        return "island-heightmap"
    if upper.endswith(".OBL"):
        return "island-objects"
    if upper.endswith(".SMK"):
        return "smacker-video"
    if upper.startswith("VIDEO/"):
        return "video-support"
    if upper.startswith("MUSIC/"):
        return "music-data"
    if upper.startswith("CONFIG/"):
        return "config-data"
    if upper.endswith(".CFG") or upper.endswith(".INI"):
        return "config-file"
    if upper.endswith(".DLL"):
        return "runtime-library"
    if upper.endswith(".EXE") or upper.endswith(".BAT"):
        return "runtime-binary"
    return "other"


def is_required_phase1(relative_path: str) -> bool:
    upper = relative_path.upper()
    if upper in {value.upper() for value in REQUIRED_PHASE1_FILES}:
        return True
    if upper.startswith("VOX/") and upper.endswith(".VOX"):
        return True
    if upper.endswith(".ILE") or upper.endswith(".OBL"):
        return True
    return False


def generate_asset_inventory() -> dict[str, Any]:
    ensure_roots()
    for rel in REQUIRED_PHASE1_FILES:
        path = ASSET_ROOT / Path(rel)
        if not path.is_file():
            raise SystemExit(f"Missing required canonical asset file: {repo_relative(path)}")

    vox_files = required_vox_files()
    island_pairs = island_pair_summary()

    inventory: list[dict[str, Any]] = []
    files = sorted((path for path in ASSET_ROOT.rglob("*") if path.is_file()), key=lambda path: repo_relative(path).lower())
    for path in files:
        relative_path = path.relative_to(ASSET_ROOT).as_posix()
        inventory.append(
            {
                "asset_class": classify_asset(relative_path),
                "locale_bucket": detect_locale(relative_path),
                "relative_path": relative_path,
                "required_for_phase1": is_required_phase1(relative_path),
                "sha256": sha256_file(path),
                "size_bytes": path.stat().st_size,
            }
        )

    required_dependency_paths = sorted(
        {
            *REQUIRED_PHASE1_FILES,
            *(path.relative_to(ASSET_ROOT).as_posix() for path in vox_files),
            *(pair["ile_path"] for pair in island_pairs),
            *(pair["obl_path"] for pair in island_pairs),
        },
        key=str.lower,
    )
    flagged_paths = sorted((entry["relative_path"] for entry in inventory if entry["required_for_phase1"]), key=str.lower)
    if flagged_paths != required_dependency_paths:
        raise SystemExit("Phase 1 dependency flags drifted from the canonical required file set")

    return {
        "asset_root": repo_relative(ASSET_ROOT),
        "inventory": inventory,
        "required_phase1_dependencies": {
            "explicit_files": list(REQUIRED_PHASE1_FILES),
            "island_pairs": island_pairs,
            "required_paths": required_dependency_paths,
            "vox_files": [path.relative_to(ASSET_ROOT).as_posix() for path in vox_files],
        },
    }


def detect_asset_families(text: str) -> list[str]:
    families = []
    for asset_family, patterns in ASSET_FAMILY_PATTERNS:
        if any(compile_regex(pattern).search(text) for pattern in patterns):
            families.append(asset_family)
    return sorted(families)


def generate_source_map() -> dict[str, Any]:
    ensure_roots()
    buckets: list[dict[str, Any]] = []
    for spec in SOURCE_BUCKETS:
        owner_files: list[dict[str, Any]] = []
        bucket_assets: set[str] = set()
        bucket_entrypoints: list[dict[str, Any]] = []

        for relative_owner in spec["owner_files"]:
            path = SOURCE_ROOT / Path(relative_owner)
            if not path.is_file():
                raise SystemExit(f"Missing source owner file: {repo_relative(path)}")
            text = load_text(path)
            marker_matches = find_line_matches(text, spec["marker_patterns"])
            asset_families = detect_asset_families(text)
            bucket_assets.update(asset_families)
            entrypoints = find_line_matches(text, spec["entrypoint_patterns"])
            for entrypoint in entrypoints:
                bucket_entrypoints.append(
                    {
                        "file": repo_relative(path),
                        "line": entrypoint["line"],
                        "text": entrypoint["text"],
                    }
                )
            owner_files.append(
                {
                    "asset_families": asset_families,
                    "entrypoint_lines": [item["line"] for item in entrypoints],
                    "evidence_lines": marker_matches,
                    "path": repo_relative(path),
                }
            )

        if not owner_files:
            raise SystemExit(f"Bucket has no owner files: {spec['bucket_id']}")
        if not any(owner["evidence_lines"] for owner in owner_files):
            raise SystemExit(f"Bucket has no matching evidence lines: {spec['bucket_id']}")

        buckets.append(
            {
                "asset_families": sorted(bucket_assets),
                "bucket_id": spec["bucket_id"],
                "entrypoints": bucket_entrypoints,
                "label": spec["label"],
                "owner_files": owner_files,
            }
        )

    boot_bucket = next(bucket for bucket in buckets if bucket["bucket_id"] == "boot-entrypoint")
    if not boot_bucket["entrypoints"]:
        raise SystemExit("Boot and entrypoint bucket did not identify a concrete entrypoint")

    return {
        "source_root": repo_relative(SOURCE_ROOT),
        "subsystem_buckets": buckets,
    }


def connect_db() -> sqlite3.Connection:
    ensure_roots()
    conn = sqlite3.connect(EVIDENCE_DB)
    conn.row_factory = sqlite3.Row
    return conn


def asset_entry_ref(conn: sqlite3.Connection, asset_name: str, entry_index: int) -> dict[str, Any]:
    row = conn.execute(
        """
        SELECT asset_name, entry_index, descriptor, topic_id, post_id, source_url, confidence, parser_name
        FROM asset_entries
        WHERE asset_name = ? AND entry_index = ?
        ORDER BY confidence DESC, post_id ASC
        LIMIT 1
        """,
        (asset_name, entry_index),
    ).fetchone()
    if row is None:
        raise SystemExit(f"Missing asset_entries evidence for {asset_name}[{entry_index}]")
    return {
        "asset_name": row["asset_name"],
        "confidence": row["confidence"],
        "descriptor": row["descriptor"],
        "entry_index": row["entry_index"],
        "kind": "mbn_asset_entry",
        "parser_name": row["parser_name"],
        "post_id": row["post_id"],
        "source_url": row["source_url"],
        "topic_id": row["topic_id"],
    }


def evidence_ref(conn: sqlite3.Connection, evidence_id: int) -> dict[str, Any]:
    row = conn.execute(
        """
        SELECT evidence_id, kind, topic_id, post_id, post_number, source_url, confidence, excerpt
        FROM evidence
        WHERE evidence_id = ?
        """,
        (evidence_id,),
    ).fetchone()
    if row is None:
        raise SystemExit(f"Missing evidence row: {evidence_id}")
    return {
        "confidence": row["confidence"],
        "evidence_id": row["evidence_id"],
        "evidence_kind": row["kind"],
        "excerpt": row["excerpt"],
        "kind": "mbn_evidence",
        "post_id": row["post_id"],
        "post_number": row["post_number"],
        "source_url": row["source_url"],
        "topic_id": row["topic_id"],
    }


def generate_evidence_bundle() -> dict[str, Any]:
    ensure_roots()
    with connect_db() as conn:
        golden_targets = [
            {
                "asset_references": [
                    {"entry_index": 2, "path": "SCENE.HQR"},
                    {"entry_index": 2, "path": "LBA_BKG.HQR"},
                ],
                "confidence_level": "high",
                "semantic_label": "Twinsen's house interior room",
                "supporting_evidence": [
                    asset_entry_ref(conn, "SCENE.HQR", 2),
                    evidence_ref(conn, 10614),
                ],
                "target_id": "interior-room-twinsens-house",
                "unresolved_questions": [],
            },
            {
                "asset_references": [
                    {"entry_index": 44, "path": "SCENE.HQR"},
                ],
                "confidence_level": "high",
                "semantic_label": "Citadel Island exterior scene with the tavern and the shop",
                "supporting_evidence": [
                    asset_entry_ref(conn, "SCENE.HQR", 44),
                    evidence_ref(conn, 10609),
                    find_first_line(SOURCE_ROOT / "DISKFUNC.CPP", r"numscene\+1"),
                    find_first_line(SOURCE_ROOT / "EXTFUNC.CPP", r"char\s+\*IleLst\[\]\s*="),
                    find_first_line(SOURCE_ROOT / "EXTFUNC.CPP", r"\"citadel\""),
                ],
                "target_id": "exterior-area-citadel-tavern-and-shop",
                "unresolved_questions": [],
            },
            {
                "actor_binding": {
                    "linked_animation_reference": None,
                    "linked_body_reference": None,
                    "scene_actor_slot": 0,
                },
                "asset_references": [
                    {"entry_index": 2, "path": "SCENE.HQR", "role": "hero block"},
                ],
                "confidence_level": "medium",
                "semantic_label": "Player actor instance in SCENE.HQR entry 2",
                "supporting_evidence": [
                    find_first_line(SOURCE_ROOT / "COMMON.H", r"#define\s+NUM_PERSO\s+\(\(U8\)0\)"),
                    find_first_line(SOURCE_ROOT / "DISKFUNC.CPP", r"hero inits:\s+HERO_START"),
                    find_first_line(SOURCE_ROOT / "DISKFUNC.CPP", r"ptrobj->GenBody\s*=\s*GET_S8"),
                    find_first_line(SOURCE_ROOT / "OBJECT.CPP", r"if\s*\(\s*numobj==NUM_PERSO\s*\)\s*gennewbody\s*=\s*ChoiceHeroBody"),
                ],
                "target_id": "actor-player-scene2",
                "unresolved_questions": [
                    "SCENE.HQR entry 2 does not yet provide a direct, locked body entry for the hero block.",
                    "SCENE.HQR entry 2 does not yet provide a direct, locked animation entry for the hero block.",
                ],
            },
            {
                "asset_references": [
                    {"entry_index": 1, "path": "VOX/EN_GAM.VOX"},
                ],
                "confidence_level": "high",
                "semantic_label": 'VOX/EN_GAM.VOX entry 1, "You just found your Holomap!"',
                "supporting_evidence": [
                    evidence_ref(conn, 11254),
                    evidence_ref(conn, 11257),
                ],
                "target_id": "dialog-voice-holomap",
                "unresolved_questions": [
                    "The exact TEXT.HQR subtitle pairing is still provisional in phase 0.",
                ],
            },
            {
                "asset_references": [
                    {"entry_index": 1, "path": "VIDEO/VIDEO.HQR"},
                    {"entry_index": 49, "path": "RESS.HQR", "role": "movie-name index evidence path"},
                ],
                "confidence_level": "high",
                "semantic_label": "VIDEO/VIDEO.HQR entry 1 / ASCENSEU.SMK",
                "supporting_evidence": [
                    evidence_ref(conn, 11659),
                    asset_entry_ref(conn, "RESS.HQR", 49),
                ],
                "target_id": "cutscene-ascenseu",
                "unresolved_questions": [],
            },
            {
                "asset_references": [
                    {"entry_index": 2, "path": "SCENE.HQR", "role": "house scene"},
                    {"entry_index": 1, "path": "LBA_BKG.HQR", "role": "house background"},
                    {"entry_index": 0, "path": "LBA_BKG.HQR", "role": "cellar background"},
                ],
                "confidence_level": "high",
                "semantic_label": "Early house key and cellar access affordance",
                "state_context": {
                    "location": "early Twinsen-house state",
                    "inventory": "starts without the hidden key",
                    "player_affordance": "find hidden key, open keyed cellar door, enter and return from cellar",
                    "runtime_gate": "key pickup and consumption plus house/cellar active-cube changes",
                },
                "supporting_evidence": [
                    find_first_doc_line(REPO_ROOT / "docs" / "lba2_walkthrough.md", r"Get the key first.*golden ball"),
                    find_first_doc_line(REPO_ROOT / "docs" / "PHASE5_0013_RUNTIME_PROOF.md", r"NbLittleKeys 0 -> 1"),
                    find_first_doc_line(REPO_ROOT / "docs" / "promotion_packets" / "phase5" / "phase5_0013_key_door_cellar.md", r"status`: `live_positive"),
                ],
                "target_id": "quest-state-house-key-cellar-access",
                "unresolved_questions": [
                    "True New Game state equivalence is not yet proved for this target.",
                    "The exact magic ball pickup mutation is not yet promoted in the 0013 packet.",
                    "The Sendell portrait clue and dialogue/flag surface are not part of this narrow target.",
                ],
            },
        ]

    for target in golden_targets:
        if not target["supporting_evidence"]:
            raise SystemExit(f"Golden target has no evidence: {target['target_id']}")
        if target["target_id"] == "actor-player-scene2" and not target["unresolved_questions"]:
            raise SystemExit("Actor target must record the unresolved body/animation link gap")

    return {
        "canonical_roots": {
            "asset_root": repo_relative(ASSET_ROOT),
            "evidence_db": repo_relative(EVIDENCE_DB),
            "source_root": repo_relative(SOURCE_ROOT),
        },
        "golden_targets": golden_targets,
        "phase1_replan_gate": {
            "blocking_gaps": [
                "Scene-level player body and animation linkage for SCENE.HQR entry 2 remains unresolved.",
                "The first English voice target still needs a locked subtitle pairing proof.",
            ],
            "keep_targets": [
                "interior-room-twinsens-house",
                "exterior-area-citadel-tavern-and-shop",
                "dialog-voice-holomap",
                "cutscene-ascenseu",
                "quest-state-house-key-cellar-access",
            ],
            "provisional_facts": [
                "TEXT.HQR pairing for VOX/EN_GAM.VOX entry 1 is provisional.",
                "Hero body/animation linkage for SCENE.HQR entry 2 is provisional.",
                "New Game equivalence, Sendell portrait dialogue/flags, and magic ball pickup state are not yet promoted as part of the 0013 runtime packet.",
            ],
        },
    }


def build_outputs() -> dict[Path, str]:
    asset_inventory = generate_asset_inventory()
    source_map = generate_source_map()
    evidence_bundle = generate_evidence_bundle()

    serialized_outputs = {
        ASSET_OUTPUT: json_dumps(asset_inventory),
        SOURCE_OUTPUT: json_dumps(source_map),
        EVIDENCE_OUTPUT: json_dumps(evidence_bundle),
    }

    manifest = {
        "canonical_roots": {
            "asset_root": repo_relative(ASSET_ROOT),
            "evidence_db": repo_relative(EVIDENCE_DB),
            "source_root": repo_relative(SOURCE_ROOT),
        },
        "checked_in_baseline_docs": [repo_relative(path) for path in REQUIRED_DOCS],
        "generated_outputs": {path.name: repo_relative(path) for path in serialized_outputs},
        "golden_target_ids": [target["target_id"] for target in evidence_bundle["golden_targets"]],
        "output_hashes": {path.name: sha256_bytes(contents.encode("utf-8")) for path, contents in serialized_outputs.items()},
        "source_bucket_ids": [bucket["bucket_id"] for bucket in source_map["subsystem_buckets"]],
    }
    serialized_outputs[MANIFEST_OUTPUT] = json_dumps(manifest)
    return serialized_outputs


def write_outputs(serialized_outputs: dict[Path, str]) -> None:
    PHASE0_WORK.mkdir(parents=True, exist_ok=True)
    for path, content in serialized_outputs.items():
        path.write_text(content, encoding="utf-8")


def validate_outputs() -> None:
    ensure_roots()
    for doc in REQUIRED_DOCS:
        if not doc.is_file():
            raise SystemExit(f"Missing checked-in phase 0 doc: {repo_relative(doc)}")

    expected = build_outputs()
    for path, expected_content in expected.items():
        if not path.is_file():
            raise SystemExit(f"Missing generated phase 0 output: {repo_relative(path)}")
        actual = path.read_text(encoding="utf-8")
        if actual != expected_content:
            raise SystemExit(f"Generated output drifted from the canonical phase 0 baseline: {repo_relative(path)}")

    asset_inventory = json.loads(expected[ASSET_OUTPUT])
    source_map = json.loads(expected[SOURCE_OUTPUT])
    evidence_bundle = json.loads(expected[EVIDENCE_OUTPUT])

    required_paths = set(asset_inventory["required_phase1_dependencies"]["required_paths"])
    inventory_paths = {entry["relative_path"] for entry in asset_inventory["inventory"] if entry["required_for_phase1"]}
    if inventory_paths != required_paths:
        raise SystemExit("Asset inventory lost required phase 1 dependency coverage")

    for bucket in source_map["subsystem_buckets"]:
        if not bucket["owner_files"]:
            raise SystemExit(f"Source bucket missing owner files: {bucket['bucket_id']}")
    if not any(bucket["entrypoints"] for bucket in source_map["subsystem_buckets"] if bucket["bucket_id"] == "boot-entrypoint"):
        raise SystemExit("Source map lost the main entrypoint file")

    for target in evidence_bundle["golden_targets"]:
        if not target["supporting_evidence"]:
            raise SystemExit(f"Golden target missing evidence: {target['target_id']}")
        if target["target_id"] == "actor-player-scene2":
            binding = target["actor_binding"]
            if binding["scene_actor_slot"] != 0:
                raise SystemExit("Actor target no longer resolves slot 0 for the player actor")
            if not target["unresolved_questions"]:
                raise SystemExit("Actor target lost its explicit unresolved body/animation gap")


def run_build() -> None:
    outputs = build_outputs()
    write_outputs(outputs)
    print(f"Wrote {len(outputs)} deterministic phase 0 outputs to {repo_relative(PHASE0_WORK)}")


def run_inventory_assets() -> None:
    outputs = build_outputs()
    PHASE0_WORK.mkdir(parents=True, exist_ok=True)
    ASSET_OUTPUT.write_text(outputs[ASSET_OUTPUT], encoding="utf-8")
    print(f"Wrote {repo_relative(ASSET_OUTPUT)}")


def run_map_source() -> None:
    outputs = build_outputs()
    PHASE0_WORK.mkdir(parents=True, exist_ok=True)
    SOURCE_OUTPUT.write_text(outputs[SOURCE_OUTPUT], encoding="utf-8")
    print(f"Wrote {repo_relative(SOURCE_OUTPUT)}")


def run_export_evidence() -> None:
    outputs = build_outputs()
    PHASE0_WORK.mkdir(parents=True, exist_ok=True)
    EVIDENCE_OUTPUT.write_text(outputs[EVIDENCE_OUTPUT], encoding="utf-8")
    print(f"Wrote {repo_relative(EVIDENCE_OUTPUT)}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Phase 0 canonical baseline tool for LBA2 port planning")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("build", help="Run the full phase 0 generation pipeline")
    subparsers.add_parser("inventory-assets", help="Generate the deterministic canonical asset inventory")
    subparsers.add_parser("map-source", help="Generate the classic source ownership map")
    subparsers.add_parser("export-evidence", help="Generate the golden-target evidence bundle")
    subparsers.add_parser("validate", help="Validate roots, docs, evidence, and deterministic output drift")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "build":
        run_build()
    elif args.command == "inventory-assets":
        run_inventory_assets()
    elif args.command == "map-source":
        run_map_source()
    elif args.command == "export-evidence":
        run_export_evidence()
    elif args.command == "validate":
        validate_outputs()
        print("Phase 0 validation passed")
    else:
        parser.error(f"Unknown command: {args.command}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
