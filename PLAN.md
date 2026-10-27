# Execution Plan

## 1. Confirm the architecture and API contract

- Define the request and response JSON for all three endpoints.
- Use a stable row ID for deletion so duplicate names can be handled correctly.
- Route browser API calls through Nginx (`/api/`) to avoid CORS problems.
- Store the SQLite file in a named Docker volume so data survives container recreation.

Deliverable: documented API contract and final directory layout.

## 2. Build the SQLite database service

- Create the database container and initialization script.
- Create a `names` table with at least `id`, `name`, and `created_at` columns.
- Mount a named volume at the shared database path.
- Add a health check that confirms the database file/table is ready.

Deliverable: an independently testable database service.

## 3. Build the Flask backend

- Add dependencies and a backend Dockerfile.
- Open the SQLite file from the shared volume.
- Implement:
  - `POST /api/add_name`
  - `GET /api/get_names`
  - `DELETE /api/remove_name`
- Validate blank or malformed names and return consistent JSON/status codes.
- Add a backend health endpoint for Docker Compose readiness checks.

Deliverable: API requests work from inside the Compose network.

## 4. Build the Nginx frontend

- Create a simple responsive HTML/CSS/JavaScript interface.
- Add one name input with separate add, query, and delete buttons.
- Render the stored names only when the query button is selected.
- Show useful loading, success, and error states.
- Configure Nginx to serve static files and reverse-proxy `/api/` to Flask.

Deliverable: the entire application is usable from one browser URL.

## 5. Integrate with Docker Compose

- Define exactly three services: `database`, `backend`, and `frontend`.
- Put services on a private Compose network.
- Use health checks and `depends_on` conditions where supported.
- Publish only the frontend port to the host unless backend exposure is needed for debugging.
- Verify clean build and startup with `docker compose up --build`.

Deliverable: one command starts the complete application.

## 6. Test and verify

- Add one valid name and verify it appears.
- Add multiple names and verify ordering/list refresh.
- Reject an empty name.
- Remove one row and verify only that row is removed.
- Restart/recreate the stack and verify database persistence.
- Inspect logs and verify all three containers are healthy/running.

Deliverable: completed test checklist with observed results.

## 7. Finish the report and submission

- Explain how browser → Nginx → Flask → SQLite requests flow.
- Document Docker networking and persistent storage.
- Record challenges faced and how they were solved.
- Include setup, run, stop, reset, and test instructions.
- Exclude generated database files, caches, and local secrets.
- Compress the complete project folder and perform one final clean-machine-style test.

Deliverable: submission-ready ZIP and brief report.

## Acceptance criteria

- Three separate containers run under Docker Compose.
- The UI provides separate buttons that can add, query, and remove names.
- The three required API endpoint paths and HTTP methods are present.
- SQLite data persists across normal container restarts/recreation.
- Invalid input produces a clear error and does not alter the database.
- A new user can run the project by following the README.
- The report explains all three tiers and lists real implementation challenges.

## Key implementation risks

- **SQLite is not a network database:** the database and backend must deliberately share the database file through a Docker volume while remaining separate services.
- **Startup race:** the backend must not assume the database is initialized merely because its container has started.
- **File locking/permissions:** both relevant containers need compatible paths and permissions on the shared volume.
- **Duplicate names:** deletion should target a numeric row ID instead of deleting every matching name.
- **Browser networking:** frontend JavaScript should call a same-origin `/api/` URL; Nginx handles service discovery internally.
