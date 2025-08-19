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

Environment file
----------------

Copy `env.example` to `.env` and adjust values, then `source .env` (or use your shell/env manager):

```bash
cp env.example .env
source .env
```

Configuration
-------------

- Core
  - MONGO_URL: MongoDB connection string. Example: `mongodb://localhost:27017/cafesmart`. If unset and `USE_TEST_STORE=true`, the in-memory store is used.
  - HMAC_SECRET: JWT HMAC signing secret used to sign tokens. Choose a long random string.
  - ADMIN_USERNAMES: Optional comma-separated list of admin emails. Matches users whose `email` is in this list OR users created with `isAdmin=true`.
  - USE_TEST_STORE: When `true`/`1`/`yes`, use the in-memory `TestableMongoStore` instead of MongoDB. In tests this is enabled by default.

- TLS (production only)
  - API_LOCAL_FULL_CHAIN: Path (relative to CWD) to your full chain certificate PEM. Used when `--env production`.
  - API_LOCAL_PRIV_KEY: Path (relative to CWD) to your private key PEM. Used when `--env production`.

- Metrics (optional)
  - CAFE_METRICS_COLLECTION: MongoDB collection name for metrics. Default: `cafe_metrics`.
  - CAFE_METRICS_FLUSH_SECONDS: Background flush interval in seconds. Default: `43200` (12h).
  - CAFE_METRICS_MAX_BATCH: Max records per batch write. Default: `512`.
  - CAFE_METRICS_MAX_WRITE_BYTES: Max bytes per write. Default: `10000000` (10MB).
  - CAFE_METRICS_MAX_WRITE_COUNT: Max documents per write. Default: `1000`.

- Data seeding (testing/dev only)
  - SEED_TEST_DATA: When `true`, seeds the in-memory store with rich dummy data.
  - DUMMY_DAYS_BACK: Number of historical days to generate for tests (default ~180).
  - DUMMY_BASE_ORDERS_MIN / DUMMY_BASE_ORDERS_MAX: Baseline order counts range per hour.
  - DUMMY_MAX_ITEMS_PER_ORDER: Max items per generated order.

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

