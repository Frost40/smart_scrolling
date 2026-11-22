"""The pipeline's local SQLite lists and history."""

import sqlite3

from . import settings


def connect():
    """Open the local database, creating the five tables on first use."""
    db = sqlite3.connect(settings.home() / "pipeline.db")
    db.row_factory = sqlite3.Row
    try:
        db.executescript("""
            CREATE TABLE IF NOT EXISTS books (
                id TEXT PRIMARY KEY, title TEXT, authors TEXT, year INTEGER,
                isbn13 TEXT, ol_work TEXT, topics TEXT, origin TEXT, score REAL,
                priority INTEGER, status TEXT, attempts INTEGER, next_try_at TEXT,
                last_error TEXT, job_id TEXT, added_at TEXT, updated_at TEXT
            );
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY, kind TEXT, title TEXT, origin TEXT, status TEXT,
                step TEXT, attempts INTEGER, error TEXT, counts TEXT,
                created_at TEXT, updated_at TEXT
            );
            CREATE TABLE IF NOT EXISTS seen (
                key TEXT PRIMARY KEY, job_id TEXT, at TEXT
            );
            CREATE TABLE IF NOT EXISTS runs (
                id INTEGER PRIMARY KEY, stage TEXT, started_at TEXT, ended_at TEXT,
                result TEXT, summary TEXT
            );
            CREATE TABLE IF NOT EXISTS calls (
                at TEXT, provider TEXT, role TEXT, job_id TEXT, ok INTEGER,
                error_kind TEXT, seconds REAL, tokens_in INTEGER, tokens_out INTEGER
            );
        """)
    except BaseException:
        db.close()
        raise
    return db
