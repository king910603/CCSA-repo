import os
import sqlite3
from pathlib import Path

from flask import Flask, jsonify, request


DEFAULT_DATABASE_PATH = (
    "/data/names.db"
    if Path("/data").is_dir()
    else str(Path(__file__).resolve().parent / "data" / "names.db")
)


def get_connection(database_path):
    connection = sqlite3.connect(database_path, timeout=10)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA busy_timeout = 10000")
    return connection


def ensure_schema(database_path):
    Path(database_path).parent.mkdir(parents=True, exist_ok=True)
    with get_connection(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS names (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )


def create_app(database_path=None):
    app = Flask(__name__)
    app.config["DATABASE_PATH"] = database_path or os.getenv(
        "DATABASE_PATH", DEFAULT_DATABASE_PATH
    )
    ensure_schema(app.config["DATABASE_PATH"])

    @app.get("/health")
    def health():
        try:
            with get_connection(app.config["DATABASE_PATH"]) as connection:
                connection.execute("SELECT 1 FROM names LIMIT 1").fetchone()
            return jsonify(status="healthy")
        except sqlite3.Error as exc:
            return jsonify(status="unhealthy", error=str(exc)), 503

    @app.post("/api/add_name")
    def add_name():
        payload = request.get_json(silent=True) or {}
        name = payload.get("name")
        if not isinstance(name, str) or not name.strip():
            return jsonify(error="Name is required."), 400

        name = name.strip()
        if len(name) > 100:
            return jsonify(error="Name must be 100 characters or fewer."), 400

        with get_connection(app.config["DATABASE_PATH"]) as connection:
            cursor = connection.execute("INSERT INTO names (name) VALUES (?)", (name,))
            row = connection.execute(
                "SELECT id, name, created_at FROM names WHERE id = ?", (cursor.lastrowid,)
            ).fetchone()

        return jsonify(dict(row)), 201

    @app.get("/api/get_names")
    def get_names():
        with get_connection(app.config["DATABASE_PATH"]) as connection:
            rows = connection.execute(
                "SELECT id, name, created_at FROM names ORDER BY id ASC"
            ).fetchall()
        return jsonify(names=[dict(row) for row in rows])

    @app.delete("/api/remove_name")
    def remove_name():
        payload = request.get_json(silent=True) or {}
        row_id = payload.get("id")
        name = payload.get("name")

        with get_connection(app.config["DATABASE_PATH"]) as connection:
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                cursor = connection.execute("DELETE FROM names WHERE id = ?", (row_id,))
            elif isinstance(name, str) and name.strip():
                cursor = connection.execute(
                    "DELETE FROM names WHERE id = (SELECT id FROM names WHERE name = ? ORDER BY id LIMIT 1)",
                    (name.strip(),),
                )
            else:
                return jsonify(error="A numeric id or non-empty name is required."), 400

        if cursor.rowcount == 0:
            return jsonify(error="Name not found."), 404
        return jsonify(message="Name removed successfully.")

    @app.errorhandler(405)
    def method_not_allowed(_error):
        return jsonify(error="Method not allowed."), 405

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
