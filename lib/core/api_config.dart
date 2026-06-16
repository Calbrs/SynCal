// lib/core/api_config.dart

class ApiConfig {
  // ── Base URL ─────────────────────────────────────────────────
  // Change this to your production URL when deploying.
  static const String baseUrl = 'https://syncal-web.onrender.com';

  // ── Endpoints ────────────────────────────────────────────────
  static const String connectEndpoint = '/api/connect';

  // ── Timeouts ─────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // ── Hive box keys ────────────────────────────────────────────
  static const String syncalBoxKey = 'syncal_session';
  static const String linkedUserKey = 'linked_user';
  static const String lastSyncKey = 'last_sync_timestamp';

  // ── Full endpoint helpers ─────────────────────────────────────
  static String get connectUrl => '$baseUrl$connectEndpoint';
}