// lib/core/api_client.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'api_config.dart';

/// Holds the linked user data returned after a successful login.
class LinkedUser {
  final int id;
  final String username;
  final String syncalId;

  const LinkedUser({
    required this.id,
    required this.username,
    required this.syncalId,
  });

  factory LinkedUser.fromJson(Map<String, dynamic> json) => LinkedUser(
        id: json['id'] as int,
        username: json['username'] as String,
        syncalId: json['syncal_id'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'syncal_id': syncalId,
      };
}

/// Represents a synced student contact from the server.
class SyncedContact {
  final int studentId;
  final String name;
  final List<String> phones;

  const SyncedContact({
    required this.studentId,
    required this.name,
    required this.phones,
  });

  factory SyncedContact.fromJson(Map<String, dynamic> json) => SyncedContact(
        studentId: json['student_id'] as int,
        name: json['student_name'] as String,
        phones: List<String>.from(json['phones'] as List),
      );
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _box = Hive.box<dynamic>(ApiConfig.syncalBoxKey);

  // Local storage key for the session token issued by `authenticate`.
  // This isn't part of ApiConfig (that file wasn't shared when this was
  // written) — feel free to move it there alongside the other keys, just
  // make sure the string doesn't collide with an existing one.
  static const _sessionTokenKey = 'syncal_session_token';

  // ── Persistence helpers ───────────────────────────────────────

  LinkedUser? get linkedUser {
    final raw = _box.get(ApiConfig.linkedUserKey);
    if (raw == null) return null;
    return LinkedUser.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<void> _saveLinkedUser(LinkedUser user) async {
    await _box.put(ApiConfig.linkedUserKey, user.toJson());
  }

  Future<void> _clearLinkedUser() async {
    await _box.delete(ApiConfig.linkedUserKey);
    await _box.delete(ApiConfig.lastSyncKey);
    await _box.delete(_sessionTokenKey);
  }

  /// The signed session token returned by the server on successful login.
  /// This — not `syncal_id`/`cr_id` — is what now proves identity to `sync`.
  String? get _sessionToken => _box.get(_sessionTokenKey) as String?;

  Future<void> _saveSessionToken(String token) async {
    await _box.put(_sessionTokenKey, token);
  }

  DateTime? get lastSync {
    final raw = _box.get(ApiConfig.lastSyncKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw as String);
  }

  Future<void> _saveLastSync() async {
    await _box.put(ApiConfig.lastSyncKey, DateTime.now().toIso8601String());
  }

  // ── Step 1: Lookup by SynCal ID ──────────────────────────────

  /// Returns the username if found, throws [ApiException] otherwise.
  Future<String> lookupSyncalId(String syncalId) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'lookup',
            'syncal_id': syncalId.trim(),
          }),
        )
        .timeout(ApiConfig.connectTimeout);

    if (response.statusCode == 200) {
      final body = _decode(response);
      final username = body['username'] as String?;
      if (username != null && username.isNotEmpty) {
        return username;
      }
      throw ApiException('Invalid response from server');
    } else if (response.statusCode == 404) {
      final body = _decode(response);
      throw ApiException(body['message'] as String? ?? 'No account found with that SynCal ID');
    } else {
      final body = _decode(response);
      throw ApiException(body['message'] as String? ?? 'Lookup failed');
    }
  }

  // ── Step 2: Authenticate with password (using syncal_id) ─────

  /// Returns [LinkedUser] on success, throws [ApiException] on failure.
  Future<LinkedUser> authenticate(String syncalId, String password) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'authenticate',
            'syncal_id': syncalId.trim(),
            'password': password.trim(),
          }),
        )
        .timeout(ApiConfig.connectTimeout);

    final body = _decode(response);
    if (response.statusCode == 200) {
      final userData = body['user'] as Map<String, dynamic>;
      final user = LinkedUser.fromJson(userData);
      final token = body['token'] as String?;
      if (token == null || token.isEmpty) {
        // Server should always return a token on 200 now — treat a missing
        // one as a hard failure rather than silently linking without auth.
        throw ApiException('Server did not return a session token');
      }
      await _saveLinkedUser(user);
      await _saveSessionToken(token);
      return user;
    } else if (response.statusCode == 401) {
      throw ApiException(body['message'] as String? ?? 'Invalid credentials');
    }
    throw ApiException(body['message'] as String? ?? 'Authentication failed');
  }

  // ── Step 2 Alternative: Authenticate with username ───────────

  /// Returns [LinkedUser] on success using username (from lookup), throws [ApiException] on failure.
  Future<LinkedUser> authenticateWithUsername(String username, String password) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'authenticate',
            'username': username.trim(),
            'password': password.trim(),
          }),
        )
        .timeout(ApiConfig.connectTimeout);

    final body = _decode(response);
    if (response.statusCode == 200) {
      final userData = body['user'] as Map<String, dynamic>;
      final user = LinkedUser.fromJson(userData);
      final token = body['token'] as String?;
      if (token == null || token.isEmpty) {
        throw ApiException('Server did not return a session token');
      }
      await _saveLinkedUser(user);
      await _saveSessionToken(token);
      return user;
    } else if (response.statusCode == 401) {
      throw ApiException(body['message'] as String? ?? 'Invalid credentials');
    }
    throw ApiException(body['message'] as String? ?? 'Authentication failed');
  }

  // ── Unlink ────────────────────────────────────────────────────

  Future<void> unlink() async {
    await _clearLinkedUser();
  }

  // ── Contact sync ─────────────────────────────────────────────

  /// Fetches all students for the linked CR and returns them.
  /// Also updates [lastSync] on success.
  Future<List<SyncedContact>> syncContacts() async {
    final user = linkedUser;
    final token = _sessionToken;
    if (user == null || token == null) {
      throw ApiException('No linked account');
    }

    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'sync',
            'token': token,
          }),
        )
        .timeout(ApiConfig.receiveTimeout);

    final body = _decode(response);
    if (response.statusCode == 200) {
      await _saveLastSync();
      final list = body['students'] as List;
      return list.map((e) => SyncedContact.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      // Token missing, expired, invalid, or the account no longer exists.
      // Drop the stale link entirely so periodic auto-sync stops retrying
      // with a dead token and the UI correctly prompts to relink.
      await _clearLinkedUser();
      throw ApiException(body['message'] as String? ?? 'Unauthorized - Please relink your account');
    }
    throw ApiException(body['message'] as String? ?? 'Sync failed');
  }

  // ── Internal ─────────────────────────────────────────────────

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      throw ApiException('Empty response from server');
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('Invalid server response format');
    }
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}