# flutter-van-sale

Offline-first Flutter mobile app for van sales drivers, backed by `zatgo-core`. See `../CLAUDE.md` (Flutter category) and `../../.claude/rules/` for everything not specific to this repo.

## Do not casually rework the offline/sync architecture

This is deliberately built and tested, not a stub:

- **Local-first writes**: every create (order, return, collection, stock adjust/transfer) inserts into local SQLite *and* enqueues a durable sync-queue row in one transaction, before any network call (`lib/data/van_sale_repo.dart`).
- **Idempotency**: client-generated `client_id` (UUID) on every local record; `sync_queue` primary key is `sq_${entityType}_${entityId}_${op}` with a `UNIQUE(entity_type, entity_id, op)` constraint — double-enqueue is structurally impossible.
- **Auto-retry**: failed sync items retry automatically on staged exponential backoff (1m → 5m → 30m → 2h capped), gated by `next_retry_at` in `VanSaleDb.claimNext()`. Never gives up, never deletes a failed item — corrupted/unparseable rows are the one exception (quarantined with a far-future `next_retry_at`, still manually retryable from Sync Center).
- **Session persistence**: login persists to `flutter_secure_storage` (`VanSaleSession.persistSession`/`restoreSessionFromStorage`) so the app survives a restart while offline. `main.dart`'s `_afterAuth()` deliberately does **not** force logout when access can't be re-verified because of a restored-offline session (`restoredFromStorage` flag) — only an online "confirmed no access" response, or explicit sign-out, clears it. Don't "simplify" this back to logout-on-any-failure — that reintroduces the exact bug this was built to fix.

Run the *full* `flutter test` suite (not just the file touched) plus `flutter analyze` before considering a change to `lib/data/van_sale_db.dart`, `lib/services/sync_service.dart`, or `lib/services/session.dart` done — these are the money-path files.
