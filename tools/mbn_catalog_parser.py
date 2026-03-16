from __future__ import annotations

import re
from typing import Any


VISIBILITY_LABELS = {
    1: "normal",
    2: "hidden",
    3: "repeated",
    4: "blank",
}

ENTRY_RE = re.compile(
    r"^\s*%(?P<visibility>\d+)\s+"
    r"(?P<entry_index>\d{1,6})\s+"
    r"~(?P<type_code>\d+)\s+"
    r"(?P<descriptor>.+?)"
    r"(?:\s+\*)?\s*$"
)
TYPE_DEF_RE = re.compile(r"^\s*~(?P<type_code>\d+)\s*=\s*(?P<label>.+?)\s*$")
HEADER_RE = re.compile(
    r"^\s*(?:LBA\d+\s*-\s*)?(?P<asset>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\s*$",
    re.IGNORECASE,
)
ASSET_MENTION_RE = re.compile(
    r"\b(?P<asset>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\b",
    re.IGNORECASE,
)
INLINE_ENTRY_OF_RE = re.compile(
    r"\b(?:entry|entries|entrie)\s+(?P<entry_index>\d{1,6})\s+(?:of|in)\s+"
    r"(?P<asset>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\b",
    re.IGNORECASE,
)
INLINE_ASSET_ENTRY_RE = re.compile(
    r"\b(?P<asset>[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)\b.{0,80}?"
    r"\b(?:entry|entries|entrie)\s+(?P<entry_index>\d{1,6})\b",
    re.IGNORECASE,
)
END_RE = re.compile(r"^\s*\\?-?END-?\s*$", re.IGNORECASE)
GAME_LABEL_RE = re.compile(r"^\s*LBA\d+\s*$", re.IGNORECASE)
BBCODE_RE = re.compile(r"\[/?[a-zA-Z][^\]]*\]")


def canonicalize_asset_name(asset_name: str) -> str:
    return asset_name.strip().upper()


def _strip_bbcode(line: str) -> str:
    return BBCODE_RE.sub("", line).strip()


def _header_asset_name(line: str) -> str | None:
    cleaned = _strip_bbcode(line)
    match = HEADER_RE.match(cleaned)
    if not match:
        return None
    return canonicalize_asset_name(match.group("asset"))


def _line_asset_mention(line: str) -> str | None:
    match = ASSET_MENTION_RE.search(line)
    if not match:
        return None
    return canonicalize_asset_name(match.group("asset"))


def parse_asset_catalog_entries(raw_text: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    current_asset: str | None = None
    context_asset: str | None = None
    type_labels: dict[int, str] = {}
    saw_end_marker = False
    pending_entries: list[dict[str, Any]] = []

    def flush_pending() -> None:
        nonlocal pending_entries, type_labels
        if not pending_entries:
            type_labels = {}
            return
        for entry in pending_entries:
            entry["entry_type_label"] = type_labels.get(entry["type_code"])
            entries.append(entry)
        pending_entries = []
        type_labels = {}

    for raw_line in raw_text.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue

        cleaned = _strip_bbcode(line)

        if GAME_LABEL_RE.match(cleaned):
            continue

        header_asset = _header_asset_name(line)
        if header_asset:
            flush_pending()
            current_asset = header_asset
            context_asset = header_asset
            saw_end_marker = False
            continue

        mentioned_asset = _line_asset_mention(cleaned)
        if mentioned_asset:
            context_asset = mentioned_asset

        if current_asset is not None:
            if END_RE.match(cleaned):
                saw_end_marker = True
                continue

            type_match = TYPE_DEF_RE.match(cleaned)
            if type_match:
                type_code = int(type_match.group("type_code"))
                type_labels[type_code] = type_match.group("label").strip()
                continue

            entry_match = ENTRY_RE.match(cleaned)
            if entry_match:
                visibility_code = int(entry_match.group("visibility"))
                type_code = int(entry_match.group("type_code"))
                descriptor = entry_match.group("descriptor").strip()
                confidence = 0.95
                if saw_end_marker and type_code not in type_labels:
                    confidence = 0.88
                if not raw_line.strip().endswith("*"):
                    confidence = min(confidence, 0.9)
                pending_entries.append(
                    {
                        "asset_name": current_asset,
                        "entry_index": int(entry_match.group("entry_index")),
                        "type_code": type_code,
                        "entry_type_label": None,
                        "visibility_code": visibility_code,
                        "visibility_label": VISIBILITY_LABELS.get(
                            visibility_code, f"unknown:{visibility_code}"
                        ),
                        "descriptor": descriptor,
                        "raw_line": raw_line,
                        "parser_name": "structured_list_v1",
                        "confidence": confidence,
                    }
                )
                continue

        for inline_match in INLINE_ENTRY_OF_RE.finditer(cleaned):
            entries.append(
                {
                    "asset_name": canonicalize_asset_name(inline_match.group("asset")),
                    "entry_index": int(inline_match.group("entry_index")),
                    "type_code": -1,
                    "entry_type_label": None,
                    "visibility_code": 0,
                    "visibility_label": "referenced",
                    "descriptor": cleaned,
                    "raw_line": raw_line,
                    "parser_name": "inline_reference_v1",
                    "confidence": 0.7,
                }
            )

        for inline_match in INLINE_ASSET_ENTRY_RE.finditer(cleaned):
            entries.append(
                {
                    "asset_name": canonicalize_asset_name(inline_match.group("asset")),
                    "entry_index": int(inline_match.group("entry_index")),
                    "type_code": -1,
                    "entry_type_label": None,
                    "visibility_code": 0,
                    "visibility_label": "referenced",
                    "descriptor": cleaned,
                    "raw_line": raw_line,
                    "parser_name": "inline_reference_v1",
                    "confidence": 0.7,
                }
            )

        if context_asset and re.search(r"\b(?:entry|entries|entrie)\b", cleaned, re.IGNORECASE):
            for bare_match in re.finditer(
                r"\b(?:entry|entries|entrie)\s+(?P<entry_index>\d{1,6})\b", cleaned, re.IGNORECASE
            ):
                entries.append(
                    {
                        "asset_name": context_asset,
                        "entry_index": int(bare_match.group("entry_index")),
                        "type_code": -1,
                        "entry_type_label": None,
                        "visibility_code": 0,
                        "visibility_label": "referenced",
                        "descriptor": cleaned,
                        "raw_line": raw_line,
                        "parser_name": "contextual_reference_v1",
                        "confidence": 0.55,
                    }
                )

    flush_pending()
    return entries
