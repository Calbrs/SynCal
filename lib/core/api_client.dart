import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'api_config.dart';

class LinkedUser {
  final int id;
  final String username;
  final String syncalId;
  const LinkedUser({required this.id, required this.username, required this.syncalId});
  factory LinkedUser.fromJson(Map<String, dynamic> json) => LinkedUser(
        id: json['id'] as int,
        username: json['username'] as String,
        syncalId: json['syncal_id'] as String,
      );
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'syncal_id': syncalId};
}

class SyncedContact {
  final int studentId;
  final String name;
  final List<String> phones;
  final bool isDeleted;
  const SyncedContact({
    required this.studentId,
    required this.name,
    required this.phones,
    this.isDeleted = false,
  });
  factory SyncedContact.fromJson(Map<String, dynamic> json) => SyncedContact(
        studentId: json['student_id'] as int,
        name: json['student_name'] as String,
        phones: List<String>.from(json['phones'] as List),
        isDeleted: json['is_deleted'] as bool? ?? false,
      );
}

class PendingReport {
  final String syncalId;
  final String description;
  final DateTime createdAt;
  const PendingReport({required this.syncalId, required this.description, required this.createdAt});
  factory PendingReport.fromJson(Map<String, dynamic> json) => PendingReport(
        syncalId: json['syncalId'] as String,
        description: json['description'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
  Map<String, dynamic> toJson() => {'syncalId': syncalId, 'description': description, 'createdAt': createdAt.toIso8601String()};
}

class ActiveLink {
  final String linkToken;
  final String linkType;
  final String expiresAt;
  final int crId;
  final String syncalId;
  const ActiveLink({required this.linkToken, required this.linkType, required this.expiresAt, required this.crId, required this.syncalId});
  factory ActiveLink.fromJson(Map<String, dynamic> json) => ActiveLink(
        linkToken: json['link_token'] as String,
        linkType: json['link_type'] as String,
        expiresAt: json['expires_at'] as String,
        crId: json['cr_id'] as int,
        syncalId: json['syncal_id'] as String,
      );
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _box = Hive.box<dynamic>(ApiConfig.syncalBoxKey);
  static const _sessionTokenKey = 'syncal_session_token';
  static const _pendingReportsKey = 'pending_reports';

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

  String? get _sessionToken => _box.get(_sessionTokenKey) as String?;
  String? get sessionToken => _sessionToken;

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

  List<PendingReport> get _pendingReports {
    final raw = _box.get(_pendingReportsKey);
    if (raw == null) return [];
    return (raw as List).map((e) => PendingReport.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> _savePendingReports(List<PendingReport> reports) async {
    await _box.put(_pendingReportsKey, reports.map((r) => r.toJson()).toList());
  }

  Future<void> _addPendingReport(String description) async {
    final user = linkedUser;
    if (user == null) return;
    final reports = _pendingReports;
    reports.add(PendingReport(syncalId: user.syncalId, description: description, createdAt: DateTime.now()));
    await _savePendingReports(reports);
  }

  Future<void> _clearPendingReports() async {
    await _box.delete(_pendingReportsKey);
  }

  Future<LinkedUser> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'authenticate', 'username': username.trim(), 'password': password.trim()}),
        )
        .timeout(ApiConfig.connectTimeout);
    final body = _decode(response);
    if (response.statusCode == 200) {
      final token = body['token'] as String?;
      final userData = body['user'] as Map<String, dynamic>?;
      if (token == null || token.isEmpty || userData == null) throw ApiException('Invalid server response: missing token or user');
      final user = LinkedUser.fromJson(userData);
      await _saveLinkedUser(user);
      await _saveSessionToken(token);
      return user;
    } else if (response.statusCode == 401) {
      throw ApiException(body['message'] as String? ?? 'Invalid credentials');
    }
    throw ApiException(body['message'] as String? ?? 'Login failed');
  }

  Future<LinkedUser> register({required String username, required String password, required String gender, required String className}) async {
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'register',
            'username': username.trim(),
            'password': password.trim(),
            'gender': gender,
            'class_name': className.trim(),
          }),
        )
        .timeout(ApiConfig.connectTimeout);
    final body = _decode(response);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final token = body['token'] as String?;
      final userData = body['user'] as Map<String, dynamic>?;
      if (token == null || token.isEmpty || userData == null) throw ApiException('Invalid server response: missing token or user');
      final user = LinkedUser.fromJson(userData);
      await _saveLinkedUser(user);
      await _saveSessionToken(token);
      return user;
    } else if (response.statusCode == 409) {
      throw ApiException(body['message'] as String? ?? 'Username already taken');
    }
    throw ApiException(body['message'] as String? ?? 'Registration failed');
  }

  Future<void> unlink() async {
    await _clearLinkedUser();
    await _clearPendingReports();
  }

  Future<List<SyncedContact>> syncContacts() async {
    final user = linkedUser;
    final token = _sessionToken;
    if (user == null || token == null) throw ApiException('No linked account or missing token');
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'sync', 'token': token}),
        )
        .timeout(ApiConfig.receiveTimeout);
    final body = _decode(response);
    if (response.statusCode == 200) {
      await _saveLastSync();
      final list = body['students'] as List? ?? [];
      return list.map((e) => SyncedContact.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await _clearLinkedUser();
      throw ApiException(body['message'] as String? ?? 'Unauthorized - Please relink your account');
    }
    throw ApiException(body['message'] as String? ?? 'Sync failed');
  }

  Future<bool> reportProblem(String description) async {
    final user = linkedUser;
    if (user == null) throw ApiException('No linked account');
    final trimmedDesc = description.trim();
    if (trimmedDesc.isEmpty) throw ApiException('Description cannot be empty');
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.connectUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': 'report_problem', 'syncal_id': user.syncalId, 'description': trimmedDesc}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return true;
      } else {
        await _addPendingReport(trimmedDesc);
        return false;
      }
    } catch (e) {
      await _addPendingReport(trimmedDesc);
      return false;
    }
  }

  Future<void> retryPendingReports() async {
    final reports = _pendingReports;
    if (reports.isEmpty) return;
    final remaining = <PendingReport>[];
    for (final report in reports) {
      try {
        final response = await http
            .post(
              Uri.parse(ApiConfig.connectUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'action': 'report_problem', 'syncal_id': report.syncalId, 'description': report.description}),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) remaining.add(report);
      } catch (_) {
        remaining.add(report);
      }
    }
    await _savePendingReports(remaining);
  }

  Future<void> deleteStudent(int studentId) async {
    final token = _sessionToken;
    if (token == null) throw ApiException('No session token. Please log in again.');
    final response = await http
        .post(
          Uri.parse(ApiConfig.connectUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'delete_student',
            'token': token,
            'student_id': studentId,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final body = _decode(response);
      throw ApiException(body['message'] as String? ?? 'Failed to delete student');
    }
  }

  Future<ActiveLink?> getActiveLink() async {
    final user = linkedUser;
    if (user == null) return null;
    final url = Uri.parse('${ApiConfig.baseUrl}/api/links?cr_id=${user.id}');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = _decode(response);
        final linkData = body['activeLink'] as Map<String, dynamic>?;
        if (linkData != null) {
          return ActiveLink(
            linkToken: linkData['link_token'] as String,
            linkType: linkData['link_type'] as String,
            expiresAt: linkData['expires_at'] as String,
            crId: linkData['cr_id'] as int,
            syncalId: linkData['syncal_id'] as String,
          );
        }
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<ActiveLink> generateLink(String linkType) async {
    final user = linkedUser;
    if (user == null) throw ApiException('No linked account');
    final url = Uri.parse('${ApiConfig.baseUrl}/api/links');
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cr_id': user.id,
            'syncal_id': user.syncalId,
            'link_type': linkType,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final body = _decode(response);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final token = body['link_token'] as String?;
      final expiresAt = body['expires_at'] as String?;
      if (token == null || expiresAt == null) {
        throw ApiException('Invalid response from server');
      }
      return ActiveLink(
        linkToken: token,
        linkType: linkType,
        expiresAt: expiresAt,
        crId: user.id,
        syncalId: user.syncalId,
      );
    } else {
      throw ApiException(body['message'] as String? ?? 'Failed to generate link');
    }
  }

  Future<void> deleteLink(String linkToken) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/links?token=$linkToken');
    final response = await http.delete(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final body = _decode(response);
      throw ApiException(body['message'] as String? ?? 'Failed to delete link');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return {};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}