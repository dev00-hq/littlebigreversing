#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mbn_catalog_parser import canonicalize_asset_name, parse_asset_catalog_entries


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS_ROOT = REPO_ROOT / "docs" / "mbn_reference"
DEFAULT_DB_PATH = REPO_ROOT / "work" / "mbn_workbench" / "mbn_workbench.sqlite3"
SPEC_STATUSES = (
    "unverified",
    "verified_by_asset",
    "verified_by_source",
    "verified_by_asset_and_source",
    "disproven",
)
SOURCE_KINDS = ("evidence", "manual", "asset", "source", "mixed")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=True, sort_keys=True)


def json_hash(value: Any) -> str:
    return hashlib.sha256(json_dumps(value).encode("utf-8")).hexdigest()


def repo_relative(path: Path) -> str:
    return str(path.resolve().relative_to(REPO_ROOT))


def connect_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS corpus_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS topics (
            topic_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            slug TEXT,
            posts_count INTEGER,
            source_path TEXT NOT NULL,
            raw_json TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS posts (
            post_id INTEGER PRIMARY KEY,
            topic_id INTEGER NOT NULL,
            post_number INTEGER NOT NULL,
            username TEXT,
            created_at TEXT,
            post_url TEXT,
            source_path TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            raw_json TEXT NOT NULL,
            FOREIGN KEY(topic_id) REFERENCES topics(topic_id)
        );

        CREATE TABLE IF NOT EXISTS evidence (
            evidence_id INTEGER PRIMARY KEY AUTOINCREMENT,
            corpus_row_hash TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            topic_id INTEGER NOT NULL,
            post_id INTEGER,
            post_number INTEGER,
            source_url TEXT,
            matched_terms_json TEXT NOT NULL,
            confidence REAL NOT NULL,
            excerpt TEXT NOT NULL,
            notes_json TEXT NOT NULL,
            raw_json TEXT NOT NULL,
            FOREIGN KEY(topic_id) REFERENCES topics(topic_id),
            FOREIGN KEY(post_id) REFERENCES posts(post_id)
        );

        CREATE TABLE IF NOT EXISTS topic_cards (
            topic_id INTEGER PRIMARY KEY,
            title TEXT NOT NULL,
            labels_json TEXT NOT NULL,
            summary TEXT NOT NULL,
            formats_json TEXT NOT NULL,
            tools_json TEXT NOT NULL,
            workflows_json TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            raw_json TEXT NOT NULL,
            FOREIGN KEY(topic_id) REFERENCES topics(topic_id)
        );

        CREATE TABLE IF NOT EXISTS asset_entries (
            asset_entry_id INTEGER PRIMARY KEY AUTOINCREMENT,
            topic_id INTEGER NOT NULL,
            post_id INTEGER NOT NULL,
            post_number INTEGER NOT NULL,
            asset_name TEXT NOT NULL,
            entry_index INTEGER NOT NULL,
            type_code INTEGER NOT NULL,
            entry_type_label TEXT,
            visibility_code INTEGER NOT NULL,
            visibility_label TEXT NOT NULL,
            descriptor TEXT NOT NULL,
            raw_line TEXT NOT NULL,
            parser_name TEXT NOT NULL,
            confidence REAL NOT NULL,
            source_url TEXT,
            UNIQUE(post_id, asset_name, entry_index, raw_line),
            FOREIGN KEY(topic_id) REFERENCES topics(topic_id),
            FOREIGN KEY(post_id) REFERENCES posts(post_id)
        );

        CREATE TABLE IF NOT EXISTS spec_facts (
            spec_fact_id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject TEXT NOT NULL,
            statement TEXT NOT NULL,
            status TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            evidence_id INTEGER,
            post_id INTEGER,
            asset_name TEXT,
            entry_index INTEGER,
            verification_notes TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(evidence_id) REFERENCES evidence(evidence_id),
            FOREIGN KEY(post_id) REFERENCES posts(post_id)
        );

        CREATE INDEX IF NOT EXISTS idx_posts_topic_number
            ON posts(topic_id, post_number);
        CREATE INDEX IF NOT EXISTS idx_evidence_topic_kind
            ON evidence(topic_id, kind);
        CREATE INDEX IF NOT EXISTS idx_evidence_post
            ON evidence(post_id);
        CREATE INDEX IF NOT EXISTS idx_asset_entries_asset
            ON asset_entries(asset_name, entry_index);
        CREATE INDEX IF NOT EXISTS idx_spec_facts_status
            ON spec_facts(status, subject);
        """
    )


def ensure_topic_stub(
    conn: sqlite3.Connection,
    *,
    topic_id: int,
    title: str | None = None,
    slug: str | None = None,
) -> None:
    conn.execute(
        """
        INSERT INTO topics(topic_id, title, slug, posts_count, source_path, raw_json)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(topic_id) DO UPDATE SET
            title = CASE
                WHEN topics.source_path = '[generated]' AND excluded.title <> ''
                    THEN excluded.title
                ELSE topics.title
            END,
            slug = COALESCE(topics.slug, excluded.slug)
        """,
        (
            topic_id,
            title or f"Topic {topic_id}",
            slug,
            0,
            "[generated]",
            "{}",
        ),
    )


def reset_corpus_tables(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        DELETE FROM asset_entries;
        DELETE FROM topic_cards;
        DELETE FROM evidence;
        DELETE FROM posts;
        DELETE FROM topics;
        DELETE FROM corpus_meta;
        """
    )


def set_meta(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute(
        """
        INSERT INTO corpus_meta(key, value)
        VALUES (?, ?)
        ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """,
        (key, value),
    )


def topic_record_from_file(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    posts = payload.get("post_stream", {}).get("posts", [])
    first_post = posts[0] if posts else {}
    topic_id = int(first_post.get("topic_id") or path.stem)
    title = payload.get("title") or first_post.get("topic_slug") or f"Topic {topic_id}"
    slug = payload.get("slug") or first_post.get("topic_slug")
    posts_count = payload.get("posts_count") or first_post.get("posts_count") or len(posts)
    return {
        "topic_id": topic_id,
        "title": title,
        "slug": slug,
        "posts_count": posts_count,
        "source_path": repo_relative(path),
        "raw_json": json_dumps(payload),
    }


def ingest_topics(conn: sqlite3.Connection, corpus_root: Path) -> int:
    count = 0
    for path in sorted((corpus_root / "corpus" / "raw" / "topics").glob("*.json")):
        record = topic_record_from_file(path)
        conn.execute(
            """
            INSERT INTO topics(topic_id, title, slug, posts_count, source_path, raw_json)
            VALUES (:topic_id, :title, :slug, :posts_count, :source_path, :raw_json)
            ON CONFLICT(topic_id) DO UPDATE SET
                title = excluded.title,
                slug = excluded.slug,
                posts_count = excluded.posts_count,
                source_path = excluded.source_path,
                raw_json = excluded.raw_json
            """,
            record,
        )
        count += 1
    return count


def insert_asset_entries(
    conn: sqlite3.Connection,
    *,
    post_id: int,
    topic_id: int,
    post_number: int,
    post_url: str | None,
    raw_text: str,
) -> int:
    parsed_entries = parse_asset_catalog_entries(raw_text)
    for entry in parsed_entries:
        conn.execute(
            """
            INSERT OR IGNORE INTO asset_entries(
                topic_id, post_id, post_number, asset_name, entry_index, type_code,
                entry_type_label, visibility_code, visibility_label, descriptor,
                raw_line, parser_name, confidence, source_url
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                topic_id,
                post_id,
                post_number,
                entry["asset_name"],
                entry["entry_index"],
                entry["type_code"],
                entry["entry_type_label"],
                entry["visibility_code"],
                entry["visibility_label"],
                entry["descriptor"],
                entry["raw_line"],
                entry["parser_name"],
                entry["confidence"],
                post_url,
            ),
        )
    return len(parsed_entries)


def canonical_post_url(post_url: str | None) -> str | None:
    if not post_url:
        return None
    if post_url.startswith("http://") or post_url.startswith("https://"):
        return post_url
    if post_url.startswith("/"):
        return f"https://forum.magicball.net{post_url}"
    return post_url


def ingest_posts(conn: sqlite3.Connection, corpus_root: Path) -> tuple[int, int]:
    post_count = 0
    asset_entry_count = 0
    for path in sorted((corpus_root / "corpus" / "raw" / "posts").glob("*.jsonl")):
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
                payload = json.loads(line)
                topic_id = int(payload["topic_id"])
                post_id = int(payload["id"])
                post_number = int(payload["post_number"])
                raw_text = payload.get("raw") or ""
                post_url = canonical_post_url(payload.get("post_url"))
                ensure_topic_stub(
                    conn,
                    topic_id=topic_id,
                    slug=payload.get("topic_slug"),
                )
                conn.execute(
                    """
                    INSERT INTO posts(
                        post_id, topic_id, post_number, username, created_at,
                        post_url, source_path, raw_text, raw_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        post_id,
                        topic_id,
                        post_number,
                        payload.get("username"),
                        payload.get("created_at"),
                        post_url,
                        repo_relative(path),
                        raw_text,
                        json_dumps(payload),
                    ),
                )
                asset_entry_count += insert_asset_entries(
                    conn,
                    post_id=post_id,
                    topic_id=topic_id,
                    post_number=post_number,
                    post_url=post_url,
                    raw_text=raw_text,
                )
                post_count += 1
    return post_count, asset_entry_count


def ingest_evidence(conn: sqlite3.Connection, corpus_root: Path) -> int:
    path = corpus_root / "corpus" / "index" / "evidence_index.jsonl"
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            payload = json.loads(line)
            ensure_topic_stub(conn, topic_id=payload["topic_id"])
            conn.execute(
                """
                INSERT INTO evidence(
                    corpus_row_hash, kind, topic_id, post_id, post_number, source_url,
                    matched_terms_json, confidence, excerpt, notes_json, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    json_hash(payload),
                    payload["kind"],
                    payload["topic_id"],
                    payload.get("post_id"),
                    payload.get("post_number"),
                    payload.get("source_url"),
                    json_dumps(payload.get("matched_terms") or []),
                    payload.get("confidence") or 0.0,
                    payload.get("excerpt") or "",
                    json_dumps(payload.get("notes") or {}),
                    json_dumps(payload),
                ),
            )
            count += 1
    return count


def ingest_topic_cards(conn: sqlite3.Connection, corpus_root: Path) -> int:
    path = corpus_root / "corpus" / "analysis" / "topic_cards_merged.jsonl"
    count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            payload = json.loads(line)
            ensure_topic_stub(
                conn,
                topic_id=payload["topic_id"],
                title=payload.get("title"),
            )
            conn.execute(
                """
                INSERT INTO topic_cards(
                    topic_id, title, labels_json, summary, formats_json, tools_json,
                    workflows_json, metadata_json, raw_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    payload["topic_id"],
                    payload.get("title") or f"Topic {payload['topic_id']}",
                    json_dumps(payload.get("labels") or []),
                    payload.get("summary") or "",
                    json_dumps(payload.get("formats") or []),
                    json_dumps(payload.get("tools") or []),
                    json_dumps(payload.get("workflows") or []),
                    json_dumps(payload.get("metadata") or {}),
                    json_dumps(payload),
                ),
            )
            count += 1
    return count


def build_database(corpus_root: Path, db_path: Path) -> None:
    if not corpus_root.exists():
        raise SystemExit(f"Corpus root does not exist: {corpus_root}")
    conn = connect_db(db_path)
    ensure_schema(conn)
    spec_fact_count = conn.execute("SELECT COUNT(*) FROM spec_facts").fetchone()[0]
    if spec_fact_count:
        raise SystemExit(
            "Refusing to rebuild while spec_facts is non-empty. "
            "Clear or export spec_facts first."
        )
    with conn:
        reset_corpus_tables(conn)
        raw_topic_count = ingest_topics(conn, corpus_root)
        post_count, asset_entry_count = ingest_posts(conn, corpus_root)
        evidence_count = ingest_evidence(conn, corpus_root)
        topic_card_count = ingest_topic_cards(conn, corpus_root)
        topic_row_count = conn.execute("SELECT COUNT(*) FROM topics").fetchone()[0]
        set_meta(conn, "corpus_root", str(corpus_root.resolve()))
        set_meta(conn, "rebuilt_at", utc_now())
        set_meta(conn, "raw_topic_count", str(raw_topic_count))
        set_meta(conn, "topic_row_count", str(topic_row_count))
        set_meta(conn, "post_count", str(post_count))
        set_meta(conn, "evidence_count", str(evidence_count))
        set_meta(conn, "topic_card_count", str(topic_card_count))
        set_meta(conn, "asset_entry_count", str(asset_entry_count))
    print(f"Built {db_path}")
    print(
        f"raw_topics={raw_topic_count} topic_rows={topic_row_count} "
        f"posts={post_count} evidence={evidence_count} "
        f"topic_cards={topic_card_count} asset_entries={asset_entry_count}"
    )


def query_rows(conn: sqlite3.Connection, sql: str, params: tuple[Any, ...]) -> list[sqlite3.Row]:
    return conn.execute(sql, params).fetchall()


def search_evidence(
    conn: sqlite3.Connection,
    *,
    query: str,
    kind: str | None,
    limit: int,
) -> None:
    like_query = f"%{query.lower()}%"
    clauses = [
        "("
        "LOWER(e.excerpt) LIKE ? OR "
        "LOWER(e.matched_terms_json) LIKE ? OR "
        "LOWER(p.raw_text) LIKE ? OR "
        "LOWER(tc.title) LIKE ?"
        ")"
    ]
    params: list[Any] = [like_query, like_query, like_query, like_query]
    if kind:
        clauses.append("e.kind = ?")
        params.append(kind)
    params.append(limit)
    rows = query_rows(
        conn,
        f"""
        SELECT
            e.evidence_id,
            e.kind,
            e.topic_id,
            e.post_number,
            e.confidence,
            t.title AS topic_title,
            e.excerpt,
            e.source_url
        FROM evidence e
        LEFT JOIN posts p ON p.post_id = e.post_id
        LEFT JOIN topics t ON t.topic_id = e.topic_id
        LEFT JOIN topic_cards tc ON tc.topic_id = e.topic_id
        WHERE {' AND '.join(clauses)}
        ORDER BY e.confidence DESC, e.topic_id ASC, e.post_number ASC
        LIMIT ?
        """,
        tuple(params),
    )
    for row in rows:
        print(
            f"[evidence:{row['evidence_id']}] kind={row['kind']} "
            f"topic={row['topic_id']} post={row['post_number']} "
            f"confidence={row['confidence']:.2f}"
        )
        print(f"  title={row['topic_title']}")
        print(f"  excerpt={row['excerpt']}")
        if row["source_url"]:
            print(f"  source={row['source_url']}")


def list_assets(conn: sqlite3.Connection, *, asset_name: str | None, limit: int) -> None:
    clauses = []
    params: list[Any] = []
    if asset_name:
        clauses.append("asset_name = ?")
        params.append(canonicalize_asset_name(asset_name))
    where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    params.append(limit)
    rows = query_rows(
        conn,
        f"""
        SELECT
            asset_name,
            COUNT(*) AS entry_rows,
            COUNT(DISTINCT entry_index) AS distinct_entries,
            MIN(entry_index) AS first_entry,
            MAX(entry_index) AS last_entry
        FROM asset_entries
        {where_sql}
        GROUP BY asset_name
        ORDER BY distinct_entries DESC, asset_name ASC
        LIMIT ?
        """,
        tuple(params),
    )
    for row in rows:
        print(
            f"{row['asset_name']}: distinct_entries={row['distinct_entries']} "
            f"rows={row['entry_rows']} range={row['first_entry']}-{row['last_entry']}"
        )


def show_asset(
    conn: sqlite3.Connection,
    *,
    asset_name: str,
    entry_index: int | None,
    limit: int,
) -> None:
    clauses = ["ae.asset_name = ?"]
    params: list[Any] = [canonicalize_asset_name(asset_name)]
    if entry_index is not None:
        clauses.append("ae.entry_index = ?")
        params.append(entry_index)
    params.append(limit)
    rows = query_rows(
        conn,
        f"""
        SELECT
            ae.asset_name,
            ae.entry_index,
            ae.visibility_label,
            ae.type_code,
            ae.entry_type_label,
            ae.descriptor,
            ae.confidence,
            ae.raw_line,
            ae.parser_name,
            ae.topic_id,
            ae.post_number,
            ae.source_url
        FROM asset_entries ae
        WHERE {' AND '.join(clauses)}
        ORDER BY ae.entry_index ASC, ae.confidence DESC, ae.topic_id ASC, ae.post_number ASC
        LIMIT ?
        """,
        tuple(params),
    )
    for row in rows:
        type_label = row["entry_type_label"] or "unknown"
        print(
            f"{row['asset_name']}[{row['entry_index']}] "
            f"{row['descriptor']} "
            f"(visibility={row['visibility_label']}, type={row['type_code']}:{type_label}, "
            f"confidence={row['confidence']:.2f}, parser={row['parser_name']})"
        )
        print(f"  topic={row['topic_id']} post={row['post_number']}")
        if row["source_url"]:
            print(f"  source={row['source_url']}")
        print(f"  raw={row['raw_line']}")


def promote_evidence(
    conn: sqlite3.Connection,
    *,
    evidence_id: int,
    subject: str,
    statement: str,
    status: str,
    notes: str,
    asset_name: str | None,
    entry_index: int | None,
) -> None:
    if status not in SPEC_STATUSES:
        raise SystemExit(f"Invalid status: {status}")
    evidence_row = conn.execute(
        "SELECT post_id FROM evidence WHERE evidence_id = ?",
        (evidence_id,),
    ).fetchone()
    if evidence_row is None:
        raise SystemExit(f"Unknown evidence_id: {evidence_id}")
    timestamp = utc_now()
    with conn:
        conn.execute(
            """
            INSERT INTO spec_facts(
                subject, statement, status, source_kind, evidence_id, post_id,
                asset_name, entry_index, verification_notes, created_at, updated_at
            )
            VALUES (?, ?, ?, 'evidence', ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                subject,
                statement,
                status,
                evidence_id,
                evidence_row["post_id"],
                canonicalize_asset_name(asset_name) if asset_name else None,
                entry_index,
                notes,
                timestamp,
                timestamp,
            ),
        )
    print(f"Promoted evidence {evidence_id} into spec_facts")


def add_spec_fact(
    conn: sqlite3.Connection,
    *,
    subject: str,
    statement: str,
    status: str,
    source_kind: str,
    notes: str,
    asset_name: str | None,
    entry_index: int | None,
) -> None:
    if status not in SPEC_STATUSES:
        raise SystemExit(f"Invalid status: {status}")
    if source_kind not in SOURCE_KINDS:
        raise SystemExit(f"Invalid source_kind: {source_kind}")
    timestamp = utc_now()
    with conn:
        conn.execute(
            """
            INSERT INTO spec_facts(
                subject, statement, status, source_kind, asset_name, entry_index,
                verification_notes, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                subject,
                statement,
                status,
                source_kind,
                canonicalize_asset_name(asset_name) if asset_name else None,
                entry_index,
                notes,
                timestamp,
                timestamp,
            ),
        )
    print("Added spec fact")


def list_spec(
    conn: sqlite3.Connection,
    *,
    status: str | None,
    subject_query: str | None,
    limit: int,
) -> None:
    clauses = []
    params: list[Any] = []
    if status:
        clauses.append("sf.status = ?")
        params.append(status)
    if subject_query:
        clauses.append("LOWER(sf.subject) LIKE ?")
        params.append(f"%{subject_query.lower()}%")
    where_sql = f"WHERE {' AND '.join(clauses)}" if clauses else ""
    params.append(limit)
    rows = query_rows(
        conn,
        f"""
        SELECT
            sf.spec_fact_id,
            sf.subject,
            sf.statement,
            sf.status,
            sf.source_kind,
            sf.asset_name,
            sf.entry_index,
            sf.updated_at
        FROM spec_facts sf
        {where_sql}
        ORDER BY sf.updated_at DESC, sf.spec_fact_id DESC
        LIMIT ?
        """,
        tuple(params),
    )
    for row in rows:
        location = ""
        if row["asset_name"]:
            location = f" asset={row['asset_name']}"
            if row["entry_index"] is not None:
                location += f"[{row['entry_index']}]"
        print(
            f"[fact:{row['spec_fact_id']}] {row['status']} {row['source_kind']}{location}"
        )
        print(f"  subject={row['subject']}")
        print(f"  statement={row['statement']}")
        print(f"  updated_at={row['updated_at']}")


def meta_summary(conn: sqlite3.Connection) -> None:
    rows = query_rows(
        conn,
        "SELECT key, value FROM corpus_meta ORDER BY key ASC",
        (),
    )
    for row in rows:
        print(f"{row['key']}={row['value']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="MBN evidence/spec workbench and asset semantics cataloger"
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB_PATH,
        help=f"SQLite database path (default: {DEFAULT_DB_PATH})",
    )
    parser.add_argument(
        "--corpus-root",
        type=Path,
        default=DEFAULT_CORPUS_ROOT,
        help=f"MBN corpus root (default: {DEFAULT_CORPUS_ROOT})",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("build-db", help="Rebuild the workbench database from the corpus")
    subparsers.add_parser("meta", help="Print database corpus metadata")

    search_parser = subparsers.add_parser("search-evidence", help="Search evidence rows")
    search_parser.add_argument("query")
    search_parser.add_argument("--kind")
    search_parser.add_argument("--limit", type=int, default=20)

    list_assets_parser = subparsers.add_parser("list-assets", help="List cataloged assets")
    list_assets_parser.add_argument("--asset")
    list_assets_parser.add_argument("--limit", type=int, default=50)

    show_asset_parser = subparsers.add_parser("show-asset", help="Show catalog entries for an asset")
    show_asset_parser.add_argument("asset_name")
    show_asset_parser.add_argument("--entry", type=int)
    show_asset_parser.add_argument("--limit", type=int, default=50)

    promote_parser = subparsers.add_parser(
        "promote-evidence",
        help="Create a spec fact linked to an evidence row",
    )
    promote_parser.add_argument("evidence_id", type=int)
    promote_parser.add_argument("subject")
    promote_parser.add_argument("statement")
    promote_parser.add_argument("--status", required=True, choices=SPEC_STATUSES)
    promote_parser.add_argument("--notes", default="")
    promote_parser.add_argument("--asset")
    promote_parser.add_argument("--entry", type=int)

    add_fact_parser = subparsers.add_parser("add-spec-fact", help="Add a manual spec fact")
    add_fact_parser.add_argument("subject")
    add_fact_parser.add_argument("statement")
    add_fact_parser.add_argument("--status", required=True, choices=SPEC_STATUSES)
    add_fact_parser.add_argument("--source-kind", required=True, choices=SOURCE_KINDS)
    add_fact_parser.add_argument("--notes", default="")
    add_fact_parser.add_argument("--asset")
    add_fact_parser.add_argument("--entry", type=int)

    list_spec_parser = subparsers.add_parser("list-spec", help="List spec facts")
    list_spec_parser.add_argument("--status", choices=SPEC_STATUSES)
    list_spec_parser.add_argument("--subject")
    list_spec_parser.add_argument("--limit", type=int, default=50)

    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "build-db":
        build_database(args.corpus_root, args.db)
        return 0

    conn = connect_db(args.db)
    ensure_schema(conn)

    if args.command == "meta":
        meta_summary(conn)
    elif args.command == "search-evidence":
        search_evidence(conn, query=args.query, kind=args.kind, limit=args.limit)
    elif args.command == "list-assets":
        list_assets(conn, asset_name=args.asset, limit=args.limit)
    elif args.command == "show-asset":
        show_asset(
            conn,
            asset_name=args.asset_name,
            entry_index=args.entry,
            limit=args.limit,
        )
    elif args.command == "promote-evidence":
        promote_evidence(
            conn,
            evidence_id=args.evidence_id,
            subject=args.subject,
            statement=args.statement,
            status=args.status,
            notes=args.notes,
            asset_name=args.asset,
            entry_index=args.entry,
        )
    elif args.command == "add-spec-fact":
        add_spec_fact(
            conn,
            subject=args.subject,
            statement=args.statement,
            status=args.status,
            source_kind=args.source_kind,
            notes=args.notes,
            asset_name=args.asset,
            entry_index=args.entry,
        )
    elif args.command == "list-spec":
        list_spec(
            conn,
            status=args.status,
            subject_query=args.subject,
            limit=args.limit,
        )
    else:
        parser.error(f"Unhandled command: {args.command}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
