import pytest

from app import create_app


@pytest.fixture()
def client(tmp_path):
    app = create_app(str(tmp_path / "test.db"))
    app.config.update(TESTING=True)
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


@pytest.mark.parametrize("payload", [{}, {"name": ""}, {"name": "   "}, {"name": 42}])
def test_rejects_invalid_names(client, payload):
    response = client.post("/api/add_name", json=payload)
    assert response.status_code == 400


def test_returns_not_found_for_missing_row(client):
    response = client.delete("/api/remove_name", json={"id": 999})
    assert response.status_code == 404

