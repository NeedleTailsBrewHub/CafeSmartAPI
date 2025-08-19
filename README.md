## CafeSmart API

Vapor (Swift) API for cafe operations: orders, menu, inventory, reservations, recipes, loyalty, realtime, metrics, and ML predictions.

### Prerequisites

- Swift 6.0+
- macOS 14+ or Ubuntu Noble
- MongoDB 6+
- Docker (optional)

### Setup in 60 seconds

1) Clone
```bash
git clone <your-repo>
cd cafe-smart-api
```
2) Configure env
```bash
cp env.example .env
source .env
```
3) Run
```bash
swift run cafe-smart-api serve --env development --hostname 0.0.0.0 --port 8080
```
Server: http://localhost:8080

### Environment variables

- Core
  - MONGO_URL: MongoDB URI, e.g. `mongodb://localhost:27017/cafesmart`. If unset and `USE_TEST_STORE=true`, uses in-memory store.
  - HMAC_SECRET: JWT HMAC signing secret (long random string).
  - ADMIN_USERNAMES: Comma-separated admin emails.
  - USE_TEST_STORE: `true/1/yes` to use in-memory store.

- TLS (production)
  - API_LOCAL_FULL_CHAIN: Full chain cert PEM path (relative to CWD).
  - API_LOCAL_PRIV_KEY: Private key PEM path (relative to CWD).

- Metrics
  - CAFE_METRICS_COLLECTION: Default `cafe_metrics`.
  - CAFE_METRICS_FLUSH_SECONDS: Default `43200`.
  - CAFE_METRICS_MAX_BATCH: Default `512`.
  - CAFE_METRICS_MAX_WRITE_BYTES: Default `10000000`.
  - CAFE_METRICS_MAX_WRITE_COUNT: Default `1000`.

- Test data (in-memory store)
  - SEED_TEST_DATA: `true` to seed rich dummy data.
  - DUMMY_DAYS_BACK, DUMMY_BASE_ORDERS_MIN, DUMMY_BASE_ORDERS_MAX, DUMMY_MAX_ITEMS_PER_ORDER.

### Docker

Build and run:
```bash
docker build -t cafesmart-api:latest .
docker run --rm -p 8080:8080 \
  -e MONGO_URL="mongodb://host.docker.internal:27017/cafesmart" \
  -e HMAC_SECRET="change-me" \
  -e ADMIN_USERNAMES="admin@example.com" \
  cafesmart-api:latest
```

### Tests

```bash
swift test
```

### Endpoints (overview)

- Auth, Menu, Orders, Reservations, Inventory, Recipes
- Predictor: generate/latest/export, model upload/list/activate/delete, forecast, instantiate
- WebSockets: `/api/ws/merchant` (admin), `/api/ws/customer`

See `docs/Predictions.md` for ML details.

### ML models

- Stored on disk under `Models/<runtime>/<kind>/...` after upload
- Tracked in MongoDB `ml_models` (or in-memory in tests)

### License

MIT — see `License.txt`.

