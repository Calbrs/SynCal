class ApiConfig {
  static const String baseUrl = 'https://syncal-web.onrender.com';

  static const String connectEndpoint = '/api/connect';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  static const String syncalBoxKey = 'syncal_session';
  static const String linkedUserKey = 'linked_user';
  static const String lastSyncKey = 'last_sync_timestamp';

  static String get connectUrl => '$baseUrl$connectEndpoint';
}