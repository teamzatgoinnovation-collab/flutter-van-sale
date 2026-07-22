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

| Tab | Role |
|-----|------|
| Today | Route stops, visit status, sync |
| Sell | Sales from van stock |
| Cash | Collections |
| Stock | Van warehouse balances |

**Drawer:** Settings (site URL, warehouse, company), Sync, Sign out

## Offline + sync

- SQLite caches pulls and queues writes with a stable `client_id`
- Flush waits for server ack before dropping outbox rows
- **Customers** are offline-first: local SQLite → server sync
- **Products** are pulled from the catalog; optional offline create is supported
- Customer/product outbox flushes **before** sales/collections so names resolve on the server
