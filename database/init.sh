#!/bin/sh
set -eu

DATABASE_PATH="${DATABASE_PATH:-/data/names.db}"
DATABASE_DIR="$(dirname "$DATABASE_PATH")"

mkdir -p "$DATABASE_DIR"

sqlite3 "$DATABASE_PATH" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS names (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
SQL

chmod 666 "$DATABASE_PATH"
find "$DATABASE_DIR" -maxdepth 1 -type f -name 'names.db-*' -exec chmod 666 {} \;

echo "SQLite database initialized at $DATABASE_PATH"
exec tail -f /dev/null

