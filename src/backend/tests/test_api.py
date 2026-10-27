import os

import pytest

# The API now talks to PostgreSQL, so the tests need a real server, e.g.
#   docker run --rm -d -p 5432:5432 -e POSTGRES_PASSWORD=test postgres:17-alpine
#   TEST_DATABASE_URL=postgresql://postgres:test@localhost:5432/postgres pytest
TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")
if not TEST_DATABASE_URL:
    pytest.skip("TEST_DATABASE_URL is not set", allow_module_level=True)

# app.py builds a module-level app on import, so point it at the test database.
os.environ["DATABASE_URL"] = TEST_DATABASE_URL

from app import create_app, get_connection  # noqa: E402


@pytest.fixture()
def client():
    app = create_app(TEST_DATABASE_URL)
    app.config.update(TESTING=True)
    with get_connection(TEST_DATABASE_URL) as connection:
        connection.execute("TRUNCATE names RESTART IDENTITY")
    return app.test_client()


def test_add_list_and_remove_name(client):
    add_response = client.post("/api/add_name", json={"name": "Alice"})
    assert add_response.status_code == 201
    added = add_response.get_json()
    assert added["name"] == "Alice"

    list_response = client.get("/api/get_names")
    assert list_response.status_code == 200
    assert list_response.get_json()["names"][0]["name"] == "Alice"

    delete_response = client.delete("/api/remove_name", json={"id": added["id"]})
    assert delete_response.status_code == 200
    assert client.get("/api/get_names").get_json() == {"names": []}


def test_remove_by_name_deletes_only_first_match(client):
    client.post("/api/add_name", json={"name": "Bob"})
    client.post("/api/add_name", json={"name": "Bob"})

    assert client.delete("/api/remove_name", json={"name": "Bob"}).status_code == 200
    assert len(client.get("/api/get_names").get_json()["names"]) == 1


@pytest.mark.parametrize("payload", [{}, {"name": ""}, {"name": "   "}, {"name": 42}])
def test_rejects_invalid_names(client, payload):
    response = client.post("/api/add_name", json=payload)
    assert response.status_code == 400


def test_returns_not_found_for_missing_row(client):
    response = client.delete("/api/remove_name", json={"id": 999})
    assert response.status_code == 404


def test_health_reports_database_ready(client):
    assert client.get("/health").get_json() == {"status": "healthy"}
