#!/usr/bin/env python3
"""
Import todos from a cyberpunk2044-style API or JSON seed into Akashic's SQLite database.
Stdlib only (urllib, sqlite3, argparse).
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

VALID_PRIORITIES = frozenset({"low", "medium", "high"})
GRDB_REFERENCE = datetime(2001, 1, 1, tzinfo=timezone.utc)
DEFAULT_DB = Path.home() / "Library/Application Support/Akashic/akashic.sqlite"
DEFAULT_API = "http://127.0.0.1:2044/api/todos"

CREATE_TODOS = """
CREATE TABLE IF NOT EXISTS todos (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  completed BOOLEAN NOT NULL DEFAULT 0,
  priority TEXT NOT NULL DEFAULT 'medium',
  complete_by DATETIME,
  created_on DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  completed_at DATETIME
);
"""


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def parse_iso8601(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        if "." in text:
            base, _, rest = text.partition(".")
            if "+" in rest or rest.endswith("Z"):
                frac, _, tz = rest.partition("+")
                if not tz and frac.endswith("Z"):
                    frac = frac[:-1]
                    tz = "+00:00"
                text = f"{base}+{tz}" if tz else base
            else:
                text = base
            dt = datetime.fromisoformat(text)
        else:
            raise
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def format_iso8601(dt: datetime) -> str:
    utc = dt.astimezone(timezone.utc)
    ms = int(utc.microsecond / 1000)
    return utc.strftime("%Y-%m-%dT%H:%M:%S") + f".{ms:03d}Z"


def to_grdb_real(dt: datetime) -> float:
    utc = dt.astimezone(timezone.utc)
    return (utc - GRDB_REFERENCE).total_seconds()


def detect_datetime_storage(conn: sqlite3.Connection) -> str:
    """Return 'real' (GRDB deferredToDate) or 'iso8601' based on existing rows."""
    row = conn.execute(
        "SELECT typeof(created_on), created_on FROM todos LIMIT 1"
    ).fetchone()
    if row is None:
        return "real"
    kind, _ = row[0], row[1]
    if kind in ("real", "integer"):
        return "real"
    if kind == "text":
        return "iso8601"
    return "real"


def encode_datetime(dt: datetime, storage: str) -> float | str:
    if storage == "iso8601":
        return format_iso8601(dt)
    return to_grdb_real(dt)


def normalize_priority(raw: Any) -> str:
    if isinstance(raw, str) and raw in VALID_PRIORITIES:
        return raw
    return "medium"


def fetch_json_from_api(url: str) -> tuple[dict[str, Any], str]:
    req = Request(url, headers={"Accept": "application/json"})
    try:
        with urlopen(req, timeout=60) as resp:
            charset = resp.headers.get_content_charset() or "utf-8"
            body = resp.read().decode(charset)
    except HTTPError as exc:
        raise SystemExit(f"HTTP error {exc.code} fetching {url}: {exc.reason}") from exc
    except URLError as exc:
        raise SystemExit(f"Failed to fetch {url}: {exc.reason}") from exc
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON from {url}: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"Expected JSON object from {url}, got {type(payload).__name__}")
    return payload, url


def load_json_file(path: Path) -> tuple[dict[str, Any], str]:
    try:
        body = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"Cannot read {path}: {exc}") from exc
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"Expected JSON object in {path}, got {type(payload).__name__}")
    return payload, str(path)


def extract_todos(payload: dict[str, Any], source_label: str) -> list[dict[str, Any]]:
    raw = payload.get("todos")
    if raw is None:
        raise SystemExit(f"No 'todos' array in JSON from {source_label}")
    if not isinstance(raw, list):
        raise SystemExit(f"'todos' must be an array in JSON from {source_label}")
    return raw


def map_todo(entry: dict[str, Any]) -> dict[str, Any]:
    title = entry.get("title")
    if not isinstance(title, str) or not title.strip():
        raise SystemExit("Each todo must have a non-empty string 'title'")

    completed = bool(entry.get("completed", False))
    priority = normalize_priority(entry.get("priority", "medium"))

    created_raw = entry.get("created_at")
    updated_raw = entry.get("updated_at")
    try:
        created = parse_iso8601(created_raw) if created_raw else datetime.now(timezone.utc)
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"Invalid created_at for todo {title!r}: {created_raw!r}") from exc
    try:
        updated = parse_iso8601(updated_raw) if updated_raw else created
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"Invalid updated_at for todo {title!r}: {updated_raw!r}") from exc

    completed_at = updated if completed else None

    return {
        "id": str(uuid.uuid4()),
        "title": title,
        "description": "",
        "completed": 1 if completed else 0,
        "priority": priority,
        "complete_by": None,
        "created_on": created,
        "updated_at": updated,
        "completed_at": completed_at,
    }


def warn_if_akashic_running() -> None:
    try:
        proc = subprocess.run(
            ["pgrep", "-x", "Akashic"],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return
    if proc.returncode == 0 and proc.stdout.strip():
        eprint(
            "warning: Akashic appears to be running (pgrep -x Akashic). "
            "Import will proceed, but relaunch Akashic to see new todos in the UI."
        )


def write_seed(path: Path, source: str, todos: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = {"source": source, "todos": todos}
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def import_todos(
    conn: sqlite3.Connection,
    mapped: list[dict[str, Any]],
    replace: bool,
    dt_storage: str,
) -> None:
    if replace:
        conn.execute("DELETE FROM todos")
    insert = """
        INSERT INTO todos (
            id, title, description, completed, priority,
            complete_by, created_on, updated_at, completed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    for row in mapped:
        conn.execute(
            insert,
            (
                row["id"],
                row["title"],
                row["description"],
                row["completed"],
                row["priority"],
                row["complete_by"],
                encode_datetime(row["created_on"], dt_storage),
                encode_datetime(row["updated_at"], dt_storage),
                encode_datetime(row["completed_at"], dt_storage)
                if row["completed_at"]
                else None,
            ),
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import cyberpunk2044 / cyberpunk2077 todos into Akashic SQLite."
    )
    parser.add_argument(
        "--api",
        metavar="URL",
        help=f"Full GET /api/todos URL (default {DEFAULT_API} if neither --api nor --json is set)",
    )
    parser.add_argument("--json", metavar="PATH", type=Path, help="Import from a seed JSON file")
    parser.add_argument(
        "--db",
        metavar="PATH",
        type=Path,
        default=DEFAULT_DB,
        help=f"Akashic SQLite path (default: {DEFAULT_DB})",
    )
    parser.add_argument(
        "--replace",
        action="store_true",
        help="Delete existing todos before import (default: append)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print summary only; do not write to the database",
    )
    parser.add_argument(
        "--write-seed",
        metavar="PATH",
        type=Path,
        help="Also write fetched todos as CyberpunkSeedFile JSON",
    )
    args = parser.parse_args()

    warn_if_akashic_running()

    if args.json is not None:
        payload, source_label = load_json_file(args.json)
    elif args.api is not None:
        payload, source_label = fetch_json_from_api(args.api)
    else:
        payload, source_label = fetch_json_from_api(DEFAULT_API)

    raw_todos = extract_todos(payload, source_label)
    mapped = [map_todo(entry) for entry in raw_todos]

    mode = "replace" if args.replace else "append"
    sample = [row["title"] for row in mapped[:3]]

    if args.dry_run:
        print(f"source: {source_label}")
        print(f"would import: {len(mapped)} todo(s)")
        print(f"database: {args.db}")
        print(f"mode: {mode} (dry run — no changes written)")
        if sample:
            print("sample titles:")
            for title in sample:
                print(f"  - {title}")
        return

    if args.write_seed is not None:
        write_seed(args.write_seed, source_label, raw_todos)

    args.db.parent.mkdir(parents=True, exist_ok=True)
    try:
        conn = sqlite3.connect(args.db)
    except sqlite3.Error as exc:
        raise SystemExit(f"Cannot open database {args.db}: {exc}") from exc

    try:
        conn.execute(CREATE_TODOS)
        dt_storage = detect_datetime_storage(conn)
        import_todos(conn, mapped, args.replace, dt_storage)
        conn.commit()
    except sqlite3.Error as exc:
        conn.rollback()
        raise SystemExit(f"SQLite error: {exc}") from exc
    finally:
        conn.close()

    print(f"source: {source_label}")
    print(f"imported: {len(mapped)} todo(s)")
    print(f"database: {args.db}")
    print(f"mode: {mode}")
    if sample:
        print("sample titles:")
        for title in sample:
            print(f"  - {title}")


if __name__ == "__main__":
    main()
