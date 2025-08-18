## CafeSmart API Guide

Base URL: http://localhost:8080  
All paths below are relative to `/api`.

### Authentication

Headers
- Use `Authorization: Bearer <JWT>` for protected endpoints.

Public
- POST `/auth/register`
  - Body: { email, password, name?, isAdmin: Bool }
  - Returns: UserPublic
- POST `/auth/login`
  - Body: { email, password }
  - Returns: { token, refreshToken, expiresAt, user }
- POST `/auth/refresh-token`
  - Header: Authorization: Bearer <JWT>
  - Returns: refreshed token bundle

Authenticated
- POST `/auth/logout`
- POST `/auth/update-password`
  - Body: { oldPassword, newPassword }
- DELETE `/auth/account`

Notes
- Admin authorization is enforced by `AdminMiddleware`. A user is admin if their `isAdmin` is true or their email is included in env `ADMIN_USERNAMES` (comma-separated).

### Menu

- GET `/menu` → MenuItemsWrapper
- GET `/menu/:id` → MenuItem
- POST `/menu` (admin) → MenuItemCreate → MenuItem
- PUT `/menu/:id` (admin) → MenuItemUpdate → MenuItem
- DELETE `/menu/:id` (admin)

### Orders

- GET `/orders` → OrdersWrapper
- POST `/orders` → OrderCreateRequest → Order
- GET `/orders/:id` → Order
- PATCH `/orders/:id/status` (admin) → { status } → Order
- DELETE `/orders/:id` (admin)

Notes
- Creating/updating orders emits domain metrics used for dataset exports.

### Reservations

- GET `/reservations` → ReservationsWrapper
- POST `/reservations` → { name, partySize, startTime, phone?, notes? } → Reservation
- GET `/reservations/:id` → Reservation
- DELETE `/reservations/:id` (admin)

### Inventory

- GET `/inventory` (admin) → InventoryItemsWrapper
- GET `/inventory/:id` (admin) → InventoryItem
- POST `/inventory` (admin) → InventoryItemCreate → InventoryItem
- PUT `/inventory/:id` (admin) → InventoryItemUpdate → InventoryItem
- DELETE `/inventory/:id` (admin)

### Loyalty

- GET `/loyalty/:id` → LoyaltyAccountPublic
- POST `/loyalty/enroll` (admin) → { userId } → LoyaltyAccountPublic
- POST `/loyalty/accrue` → { userId, points } → LoyaltyAccountPublic
- POST `/loyalty/redeem` → { userId, points } → LoyaltyAccountPublic

### Seating

Areas (admin)
- GET `/seating/areas` → SeatingAreasWrapper
- POST `/seating/areas` → { name, defaultTurnMinutes, active } → SeatingArea
- GET `/seating/areas/:id` → SeatingArea
- PUT `/seating/areas/:id` → partial update → SeatingArea
- DELETE `/seating/areas/:id`

Tables (admin)
- GET `/seating/tables` → TablesWrapper
- GET `/seating/areas/:id/tables` → TablesWrapper
- POST `/seating/tables` → { areaId, name, capacity, accessible, highTop?, outside?, active } → Table
- GET `/seating/tables/:id` → Table
- PUT `/seating/tables/:id` → partial update → Table
- DELETE `/seating/tables/:id`

### Business Config (admin)

- GET `/config` → BusinessConfig
- PUT `/config` → BusinessConfig → BusinessConfig

### Predictor (ML, admin)

Forecast persistence
- GET `/predictor/latest` → persisted forecast points
- POST `/predictor/generate` → { horizonDays } → PredictorResponse

Dataset export (CSV)
- GET `/predictor/export?dataset=...` → CSV download
  - Supported datasets:
    - `workloadhourly`: target `target_orders_total` (hourly)
    - `reservationshourly`: target `target_reservations_total` (hourly)
    - `restockdaily`: target `target_qty_<menuItemId>` (daily per menu item)
      - Optional: `menuItemId=<id>`
    - `ingredientdaily`: target `target_usage` (daily per SKU)
      - Optional: `sku=<sku>`
    - `reservationduration`: target `target_duration_minutes` (per reservation)
- Filenames:
  - workload: `workload_hourly.csv`
  - reservations: `reservations_hourly.csv`
  - restock: `inv_<menuItemId>_daily.csv` or `restock_daily.csv`
  - ingredient: `ingredient_<sku>_daily.csv` or `ingredient_all_daily.csv`
  - reservation duration: `reservation_duration.csv`

Model management
- POST `/predictor/models/upload` (Content-Type: application/octet-stream)
  - Query: `name?`, `runtime?` (onnx|coreml), `kind?` (`workloadHourly|reservationsHourly|restockDaily|reservationDuration`)
  - Returns: stored artifact metadata
- GET `/predictor/models` → list artifacts
- POST `/predictor/models/activate` → { id }
- POST `/predictor/models/delete` → { id }
- POST `/predictor/instantiate` → { kind }

Minimal forecast (testing helpers)
- POST `/predictor/forecast/workload-hourly` → { hoursAhead }
- POST `/predictor/forecast/reservations-hourly` → { hoursAhead }
- POST `/predictor/forecast/restock-daily` → { daysAhead }

Restock decision
- POST `/predictor/restock/decide` → { sku, daysAhead? } → {
  needRestock, reorderQty, reorderPoint, leadTimeDays, onHand, forecastSumNextLeadTime
}
- Logic: needRestock = onHand <= (safetyStock + sum(forecast next leadTimeDays))

### Realtime WebSockets

- Admin: `/api/ws/merchant`
- Customer: `/api/ws/customer`

### Create ML tips

- Deselect Date/Datetime columns (`date`/`datetime`) or pre-remove them before training.
- Use regression (numeric targets):
  - restockDaily: `target_qty_<menuItemId>`
  - ingredientDaily: `target_usage`
  - workload/reservations hourly: `target_...`
- Ensure enough rows (dozens to hundreds).

### Seeding and Test Data

In-memory test store:
- Enable test store: `USE_TEST_STORE=true`
- Seed data: `SEED_TEST_DATA=true` (must be literal "true")
- Volume controls (optional):
  - `DUMMY_DAYS_BACK`: default 180
  - `DUMMY_BASE_ORDERS_MIN`: default 4
  - `DUMMY_BASE_ORDERS_MAX`: default 10
  - `DUMMY_MAX_ITEMS_PER_ORDER`: default 3

Example run:
```bash
USE_TEST_STORE=true \
SEED_TEST_DATA=true \
DUMMY_DAYS_BACK=270 \
DUMMY_BASE_ORDERS_MIN=6 \
DUMMY_BASE_ORDERS_MAX=14 \
DUMMY_MAX_ITEMS_PER_ORDER=4 \
swift run
```

Admin env
- `ADMIN_USERNAMES="admin@cafesmart.test,other@domain.com"`