# VanSale — Flutter client

**Status:** Offline-first van sales (SQLite cache + sync outbox)  
**Backend:** ZatGo Core van APIs  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)

## Auth

Sign in with **site URL + email/password**.

```bash
--dart-define=FRAPPE_BASE_URL=https://erp.zatgo.online
```

## Run

```bash
cd Clients/flutter/van_sale
flutter pub get
flutter run
```

## App map

| Mode | Tabs |
|------|------|
| **VanSale User** | Today · Sell · Cash · Stock |
| **VanSale Admin** | Overview · Routes · Sales · Cash (read/monitor + filters) |

**Drawer:** Settings (site URL, warehouse, company), Sync, Sign out. Admins with both roles can switch **My van** / **All vans**.

## Desk setup (roles + vans)

1. Create field users → assign role **VanSale User**.
2. Create supervisor(s) → assign role **VanSale Admin** (optionally also User for dual mode).
3. For each van user, create **ZG Van Sale Profile**: `user`, `warehouse`, optional `vehicle` / `route_title`.
4. Assign **ZG Trip** rows with matching `sales_user` / warehouse (or backfill from profile).

Default site: `https://erp.zatgo.online` (or demo). Hard-refresh Desk after migrate.

## Offline + sync

- SQLite caches pulls and queues writes with a stable `client_id`
- Flush waits for server ack before dropping outbox rows
- **Customers** are offline-first: local SQLite → server sync
- **Products** are pulled from the catalog; optional offline create is supported
- Customer/product outbox flushes **before** sales/collections so names resolve on the server
