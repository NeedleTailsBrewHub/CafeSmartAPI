CafeSmart API
=============

A production-ready Vapor (Swift) API for a cafe domain: orders, menu, inventory, reservations, recipes, loyalty, realtime websockets, metrics, and ML-driven predictions.

Requirements
------------

- Swift 6.0+
- macOS 14+ or Linux (Ubuntu Noble) for local builds
- MongoDB 6+ (local or remote)
- Docker (optional, for containerized build/run)

Quick Start (Local)
-------------------

1) Clone and enter the repo

```bash
git clone <your-fork-or-origin>
cd cafe-smart-api
```

2) Provide environment variables

```bash
export MONGO_URL="mongodb://localhost:27017/cafesmart"
export HMAC_SECRET="change-me-please"
# Optional: admin emails (comma-separated)
export ADMIN_USERNAMES="admin@example.com"
# Optional: force in-memory store (no Mongo) for dev
# export USE_TEST_STORE=true
```

3) Run the server

```bash
swift run cafe-smart-api serve --env development --hostname 0.0.0.0 --port 8080
```

The API listens on http://localhost:8080 by default.

Docker
------

Build and run with Docker:

```bash
docker build -t cafesmart-api:latest .
# Provide env at runtime
docker run --rm -p 8080:8080 \
  -e MONGO_URL="mongodb://host.docker.internal:27017/cafesmart" \
  -e HMAC_SECRET="change-me-please" \
  -e ADMIN_USERNAMES="admin@example.com" \
  cafesmart-api:latest
```

A sample `docker-compose.yml` is included; customize environment variables as needed.

Configuration
-------------

- MONGO_URL: MongoDB connection string. Omit or set `USE_TEST_STORE=true` to use the in-memory test store.
- HMAC_SECRET: JWT HMAC signing secret.
- ADMIN_USERNAMES: Optional comma-separated admin emails.
- TLS (prod): point `API_LOCAL_FULL_CHAIN` and `API_LOCAL_PRIV_KEY` to your cert/key paths if running with TLS in production mode.

Running Tests
-------------

```bash
swift test
```

Tests use the in-memory `TestableMongoStore` and synthetic data; no external services are required.

Endpoints (High-level)
----------------------

- Auth: register, login, refresh-token, logout, update-password
- Menu: CRUD
- Orders: CRUD (with status updates)
- Reservations: CRUD (delete)
- Inventory: CRUD (admin)
- Recipes: CRUD + list by menu item (admin)
- Predictor: generate/latest/export, model upload/list/activate/delete, forecast endpoints, instantiate
- Realtime: WebSockets at `/api/ws/merchant` (admin) and `/api/ws/customer`

Refer to `docs/Predictions.md` for ML endpoints and behavior.

ML Models
---------

- Models are stored on disk under `Models/<runtime>/<kind>/...` after upload.
- Metadata is tracked in MongoDB collection `ml_models` (or in-memory store in tests).

Development Tips
----------------

- Increase body size limits for model uploads is already configured.
- For local Mongo, install and run `mongod` or use Docker.
- Keep secrets out of the repo. Use environment variables or a secret manager.

.dockerignore suggestion
------------------------

Create a `.dockerignore` to avoid copying local secrets and build outputs into images:

```dockerignore
.env
*.pem
*.key
*.crt
**/*.mlmodelc
.build
.git
.gitignore
.DS_Store
.vscode
```

License
-------

MIT License. See `License.txt`.

