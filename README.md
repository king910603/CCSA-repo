# Homework #3 — 3-Tier Web Application with Docker Compose

Due: 2026-10-04 23:59 (Asia/Taipei)

This project is a three-container web application for adding, querying, and removing names. The frontend presents three separate buttons—**Add name**, **Get names**, and **Delete name**—so each required operation can be demonstrated independently. Nginx serves the browser interface, Flask provides the API, and a dedicated SQLite container initializes the persistent database.

## Architecture

```text
Browser
   │ http://localhost:8080
   ▼
Nginx frontend ── /api/* ──► Flask backend ── shared volume ──► SQLite database
  container                         container                    container
```

SQLite is an embedded database rather than a network server. The `database` service initializes `/data/names.db`; the `backend` service accesses that file through the same named volume. Only Nginx is exposed to the host.

## Project structure

```text
.
├── backend/
│   ├── tests/test_api.py
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements-dev.txt
│   └── requirements.txt
├── database/
│   ├── Dockerfile
│   └── init.sh
├── frontend/
│   ├── app.js
│   ├── Dockerfile
│   ├── index.html
│   ├── nginx.conf
│   └── styles.css
├── docs/REPORT.md
├── docker-compose.yml
└── PLAN.md
```

## Run the application

Requirements: Docker Desktop with Docker Compose v2.

From this directory, run:

```bash
docker compose up --build
```

Open <http://localhost:8080>. To use a different port:

```bash
APP_PORT=8088 docker compose up --build
```

On PowerShell, use `$env:APP_PORT=8088` before the Compose command.

## Stop or reset

Stop the containers while retaining the stored names:

```bash
docker compose down
```

Delete the containers **and all stored names**:

```bash
docker compose down --volumes
```

## API contract

### Add a name

`POST /api/add_name`

```json
{ "name": "Alice" }
```

Returns HTTP `201` with the created row.

### List names

`GET /api/get_names`

```json
{
  "names": [
    { "id": 1, "name": "Alice", "created_at": "2026-09-29 12:00:00" }
  ]
}
```

### Remove a name

`DELETE /api/remove_name`

```json
{ "id": 1 }
```

The API also accepts `{ "name": "Alice" }` for assignment compatibility, but the UI deletes by ID so duplicate names remain independent.

## Verification

Check container status:

```bash
docker compose ps
```

Run backend tests locally from `backend/` after installing the development dependencies:

```bash
python -m pip install -r requirements-dev.txt
python -m pytest
```

Manual acceptance test:

1. Enter two names and select **Add name** for each one.
2. Select **Get names** and confirm both names appear.
3. Enter one of the names, select **Delete name**, then select **Get names** again and confirm only the other name remains.
4. Try adding or deleting with a blank input and confirm it is rejected.
5. Run `docker compose down`, then `docker compose up`, select **Get names**, and confirm saved names remain.

See [docs/REPORT.md](docs/REPORT.md) for the submission report and [PLAN.md](PLAN.md) for the implementation plan.
