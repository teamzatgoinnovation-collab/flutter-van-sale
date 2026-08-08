import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fixed central directory server. Overridable via --dart-define for
/// dev/testing (e.g. a local zatgo_hub instance) — not user-editable.
const String kHubBaseUrl = String.fromEnvironment(
  'HUB_BASE_URL',
  defaultValue: 'https://hub.zatgo.online',
);

class HubLookupResult {
  const HubLookupResult.found(this.siteUrl) : error = null;
  const HubLookupResult.notFound(this.error) : siteUrl = null;

  final String? siteUrl;
  final String? error;

  bool get ok => siteUrl != null;
}

/// Resolves which ERPNext site an email belongs to via the central
/// zatgo_hub directory, before any credentials are sent anywhere.
Future<HubLookupResult> lookupSiteForEmail(String email) async {
  final uri = Uri.parse(
    '$kHubBaseUrl/api/method/zatgo_hub.api.v1.lookup.lookup_site',
  ).replace(queryParameters: {'email': email});

  try {
    final res = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      return HubLookupResult.notFound('Could not reach account server (HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    final envelope = decoded is Map && decoded['message'] is Map
        ? Map<String, dynamic>.from(decoded['message'] as Map)
        : <String, dynamic>{};

    if (envelope['success'] != true) {
      final error = envelope['error'];
      final message = error is Map ? error['message']?.toString() : null;
      return HubLookupResult.notFound(message ?? 'Account not recognized');
    }

    final data = envelope['data'];
    final siteUrl = data is Map ? data['site_url']?.toString() : null;
    if (siteUrl == null || siteUrl.isEmpty) {
      return const HubLookupResult.notFound('Account not recognized');
    }
    return HubLookupResult.found(siteUrl);
  } catch (e) {
    return HubLookupResult.notFound('Could not reach account server: $e');
  }
}
