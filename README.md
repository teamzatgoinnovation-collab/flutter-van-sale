# VanSale — Flutter client

**Status:** Local-first van sales with SQLite + idempotent outbox sync  
**Backend pull:** `zatgo_core.api.v1.go_van.*` (trips list/get when signed in)  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)

Real-world van / route sales: today’s route, sell from van stock, cash collections, visit check-in, durable offline queue with `client_id` so orders are not duplicated or lost.

## Auth

Sign in with ERPNext **site URL + email/password**, or **Continue offline** to work against SQLite seed data. Optional default site:

```bash
--dart-define=FRAPPE_BASE_URL=https://demo.zatgo.online
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
| Today | Route, visit actions, sync counts, Sell/Collect shortcuts |
| Sell | Stock-pick van order → SQLite + outbox (`client_id`) |
| Cash | Collections with sync badges |
| Stock | Load / issue on-van inventory |
| Link | Session / offline status, ping, sign out |

## Offline + sync

- SQLite is source of truth (`van_sale.db`)
- Every sale/collection is saved with a stable UUID `client_id` and an outbox row in the same transaction
- Sync never drops a row without ERP ack; missing write APIs mark **Awaiting ERP** and keep the outbox

## Dependency

```yaml
zatgo_dart_sdk:
  path: ../../../SharedSDK/dart_sdk
```
