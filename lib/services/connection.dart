import 'session.dart';

class ConnectionResult {
  const ConnectionResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Ping ERPNext; commercial docs sync via VanSale outbox + client_id.
Future<ConnectionResult> testConnection(VanSaleSession session) async {
  final result = await session.ping();
  return ConnectionResult(ok: result.ok, message: result.message);
}
