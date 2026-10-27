import os
import time

import psycopg
from flask import Flask, jsonify, request
from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row


# Return timestamps in the same "YYYY-MM-DD HH:MM:SS" (UTC) shape that the
# HW2 SQLite version produced, so the frontend does not need to change.
ROW_COLUMNS = (
    "id, name, "
    "to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') AS created_at"
)

# Arbitrary key so concurrent Gunicorn workers do not race on CREATE TABLE.
SCHEMA_LOCK_ID = 20261027


def database_url_from_env():
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    return make_conninfo(
        host=os.getenv("DB_HOST", "db"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "names"),
        user=os.getenv("DB_USER", "names"),
        password=os.getenv("DB_PASSWORD", ""),
        connect_timeout=5,
    )


def get_connection(database_url):
    return psycopg.connect(database_url, row_factory=dict_row)


def ensure_schema(database_url, attempts=30, delay=2):
    # The api Pod may start before PostgreSQL accepts connections.
    for attempt in range(1, attempts + 1):
        try:
            with get_connection(database_url) as connection:
                connection.execute("SELECT pg_advisory_xact_lock(%s)", (SCHEMA_LOCK_ID,))
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS names (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL,
                        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                    )
                    """
                )
            return
        except psycopg.OperationalError as exc:
            if attempt == attempts:
                raise
            print(f"Database not ready (attempt {attempt}/{attempts}): {exc}", flush=True)
            time.sleep(delay)


def create_app(database_url=None):
    app = Flask(__name__)
    app.config["DATABASE_URL"] = database_url or database_url_from_env()
    ensure_schema(app.config["DATABASE_URL"])

    @app.get("/health")
    def health():
        try:
            with get_connection(app.config["DATABASE_URL"]) as connection:
                connection.execute("SELECT 1 FROM names LIMIT 1").fetchone()
            return jsonify(status="healthy")
        except psycopg.Error as exc:
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

        with get_connection(app.config["DATABASE_URL"]) as connection:
            row = connection.execute(
                f"INSERT INTO names (name) VALUES (%s) RETURNING {ROW_COLUMNS}", (name,)
            ).fetchone()

        return jsonify(row), 201

    @app.get("/api/get_names")
    def get_names():
        with get_connection(app.config["DATABASE_URL"]) as connection:
            rows = connection.execute(
                f"SELECT {ROW_COLUMNS} FROM names ORDER BY id ASC"
            ).fetchall()
        return jsonify(names=rows)

    @app.delete("/api/remove_name")
    def remove_name():
        payload = request.get_json(silent=True) or {}
        row_id = payload.get("id")
        name = payload.get("name")

        with get_connection(app.config["DATABASE_URL"]) as connection:
            if isinstance(row_id, int) and not isinstance(row_id, bool):
                cursor = connection.execute("DELETE FROM names WHERE id = %s", (row_id,))
            elif isinstance(name, str) and name.strip():
                cursor = connection.execute(
                    "DELETE FROM names WHERE id = (SELECT id FROM names WHERE name = %s ORDER BY id LIMIT 1)",
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
