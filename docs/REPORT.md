# Homework #3 Report — 3-Tier Web Application

## 1. Project overview

This project implements a small three-tier application managed by Docker Compose. A user can enter a name, see every stored name, and remove an individual entry in a browser. The application is divided into frontend, backend, and database services so that each responsibility can be built and managed separately.

## 2. How the components work together

### Frontend

The frontend container uses Nginx. It serves `index.html`, `styles.css`, and `app.js` on port 80 inside the Compose network. Docker Compose maps host port 8080 to this container. The interface has three independent buttons: **Add name** sends the input to the add endpoint, **Get names** queries and renders the current rows, and **Delete name** removes the first database row matching the input. Add and delete do not automatically run a query, which makes each API operation easy to demonstrate separately.

Nginx also acts as a reverse proxy. Requests under `/api/` are forwarded to `backend:5000`. The hostname `backend` is resolved by Docker Compose's internal network. Using one browser origin avoids a separate CORS configuration.

### Backend

The backend container runs a Flask application with Gunicorn. It exposes these required endpoints:

- `POST /api/add_name` validates and inserts a name.
- `GET /api/get_names` returns all rows in ID order.
- `DELETE /api/remove_name` removes a row by numeric ID (or the first matching name for compatibility).

SQL parameters are used instead of string concatenation. Blank names and names longer than 100 characters are rejected. Responses use JSON and appropriate HTTP status codes. A `/health` endpoint lets Compose determine whether the API and database are ready.

### Database

The database container installs the SQLite command-line program and runs `init.sh`. The script enables WAL journal mode and creates a `names` table with `id`, `name`, and `created_at` columns. The database file is stored at `/data/names.db` on the named `sqlite_data` Docker volume.

SQLite is an embedded database and does not listen on a network port. Therefore, the database container owns initialization while the backend reads and writes the database through the shared volume. The database service remains a separate container as required by the assignment.

## 3. Docker Compose design

Docker Compose defines exactly three services: `database`, `backend`, and `frontend`. They share a private bridge network called `app_network`. Only the frontend publishes a host port. This prevents users from bypassing Nginx and keeps the database private.

Health checks control startup order. The backend waits for the initialized SQLite table, and the frontend waits until Flask responds successfully. The named volume preserves entries after `docker compose down` and normal container recreation.

## 4. Running and testing

The complete application starts with:

```bash
docker compose up --build
```

The interface is available at <http://localhost:8080>. `docker compose ps` shows the state and health of all services. `docker compose down` stops the application without deleting data. `docker compose down --volumes` performs an intentional full reset.

The Flask test suite checks a complete add/list/remove flow, invalid input, and removal of a missing row. It can be run from the backend directory with:

```bash
python -m pip install -r requirements-dev.txt
python -m pytest
```

## 5. Challenges and solutions

The largest challenge was setting up SQLite as a separate tier. Unlike MySQL or PostgreSQL, SQLite has no database server process for the backend to contact. This was handled with a dedicated initializer container and a named volume shared only with the backend. Therefore making API communication between database and backend hard to implement.

Another challenge was service startup timing. A started container is not necessarily ready to handle requests. Compose health checks and conditional dependencies ensure that the database is initialized before Flask starts and that Flask is healthy before Nginx starts. By switching the setup order, it will now be reasy whent the frontend UI is available.

Browser-to-container addressing can also be confusing. A browser cannot resolve Docker's internal `backend` hostname. The page instead sends requests to its own Nginx origin, and Nginx proxies them through the internal network.

Duplicate names were handled by assigning every row a unique numeric ID. The frontend deletes by ID, so removing one “Alice” does not accidentally remove all rows with the same name.

## 6. Conclusion

This project demonstrates separation of concerns in a containerized application. Nginx manages static content and browser-facing traffic, Flask owns validation and application logic, and SQLite provides persistent storage. Docker Compose connects the tiers, orders startup using health checks, and preserves data using a named volume.
