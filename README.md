# VanSale — Flutter client

**Status:** ERPNext-backed van sales (SQLite cache + idempotent outbox)  
**Backend:** `zatgo_core.api.v1.go_van.*` → Sales Invoice / Payment Entry / Stock Entry / ZG Trip  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)

## Auth

Sign in with ERPNext **site URL + email/password**. No offline mock mode.

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

| Tab | Role |
|-----|------|
| Today | ZG Trip route, visit status, sync |
| Sell | Sales Invoice from van stock |
| Cash | Payment Entry collections |
| Stock | Bin balances for van warehouse |

**Drawer:** Settings (site URL, warehouse, company), Sync, Sign out

## Offline + sync

- SQLite caches ERP pulls and queues writes with stable `client_id`
- Flush requires ERP ack (`erp_name`) before dropping outbox rows
- **Customers** are offline-first: local SQLite → `accounting.customers.sync`
  creates Customer + Contact + Address + attachments (idempotent `zatgo_client_id`)
- **Products** are normally pulled from ERPNext Item; optional offline create →
  `warehouse.items.sync` (Item + barcode/price/opening stock/images)
- Customer/product outbox flushes **before** sales/collections so names resolve in ERPNext
