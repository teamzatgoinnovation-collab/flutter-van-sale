# Go Van — Flutter client

**Status:** Runnable scaffold (mock route data + ERPNext password login)  
**Backend:** `zatgo_core.api.v1.go_van.*` (thin trips list/get)  
**SDK:** [`SharedSDK/dart_sdk`](../../../SharedSDK/dart_sdk/)

Van / route sales client: today’s route, offline orders, collections, customer visits (GPS stubs), and van stock transfers.

## Auth

Sign in with ERPNext **site URL + email/password** (cookie session via `ErpnextSessionStore`). Use **Continue offline** for mock data. Optional default site:

```bash
--dart-define=FRAPPE_BASE_URL=https://demo.zatgo.online
```

## Run

```bash
cd Clients/flutter/go_van
flutter pub get
flutter run
```

## App map

| Tab | Role |
|-----|------|
| Today | Route summary, GPS check-in / complete, offline sync flush |
| Orders | Offline-first van orders (queued → synced mock) |
| Cash | Collections against route customers |
| Visits | Visit list with lat/lng stubs |
| Stock | On-van inventory + transfer adjust |
| Link | ERPNext session status / sign out |

Feature pages stay on mock until Go Van hub APIs deepen beyond trips list/get.

## Dependency

```yaml
zatgo_dart_sdk:
  path: ../../../SharedSDK/dart_sdk
```
