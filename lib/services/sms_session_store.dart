// lib/services/sms_session_store.dart
// Updated version with persistence, delete, clear, and isLoaded support

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../root/models/contact.dart';
import '../root/models/sms_session.dart';
import 'sms_gateway_service.dart';
import 'app_logger.dart';

const String _tag = 'SmsSessionStore';
const String _sessionsBoxName = 'sms_sessions';

class SmsSessionStore extends ChangeNotifier {
  // Singleton
  static final SmsSessionStore _instance = SmsSessionStore._();
  factory SmsSessionStore() => _instance;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final List<SmsSession> sessions = [];

  SmsSessionStore._() {
    // Listen for delivery confirmations from the native layer
    SmsGatewayService.statusUpdates.listen(_onNativeStatusUpdate);
    _initHive();
  }

  Future<void> _initHive() async {
    try {
      // Ensure Hive is ready (already initialized elsewhere)
      final box = await Hive.openBox<SmsSession>(_sessionsBoxName);
      
      // Load existing sessions (newest first)
      sessions.clear();
      sessions.addAll(box.values.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt)));
      
      _isLoaded = true;
      notifyListeners();
      
      AppLogger.info(_tag, 'Loaded ${sessions.length} sessions from Hive');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load sessions: $e');
      _isLoaded = true; // Still mark as loaded to unblock UI
      notifyListeners();
    }
  }

  Future<void> _saveSessions() async {
    try {
      final box = Hive.box<SmsSession>(_sessionsBoxName);
      await box.clear();
      await box.addAll(sessions);
    } catch (e) {
      AppLogger.error(_tag, 'Failed to save sessions: $e');
    }
  }

  // ── Create & start a new session ──────────────────────────────────────────
  Future<void> startSession({
    required String message,
    required int simSlot,
    required String simLabel,
  }) async {
    // Build recipient list from every contact in Hive (all their phone numbers)
    final box = Hive.box<Contact>('contacts');
    final recipients = <SmsRecipient>[];

    for (final contact in box.values) {
      for (final phone in contact.phones) {
        recipients.add(SmsRecipient(name: contact.name, phone: phone));
      }
    }

    if (recipients.isEmpty) {
      AppLogger.warn(_tag, 'No contacts to send to — session aborted.');
      return;
    }

    final session = SmsSession(
      id:         DateTime.now().millisecondsSinceEpoch.toString(),
      message:    message,
      startedAt:  DateTime.now(),
      simSlot:    simSlot,
      simLabel:   simLabel,
      recipients: recipients,
    );

    sessions.insert(0, session);
    await _saveSessions();
    notifyListeners();

    AppLogger.info(_tag,
        'Session ${session.id} started — '
        '${recipients.length} recipients, SIM: $simLabel');

    await _runPass(session);
  }

  // ── Execute one send pass (initial or retry) ──────────────────────────────
  Future<void> _runPass(SmsSession session) async {
    final targets = session.retryPass == 0
        ? session.recipients                  // first pass: everyone
        : session.failedRecipients;           // retry: only failed ones

    AppLogger.info(_tag,
        'Session ${session.id} — pass ${session.retryPass}, '
        'sending to ${targets.length} recipients');

    for (final recipient in targets) {
      recipient.status   = SmsRecipientStatus.pending;
      recipient.error    = null;
      notifyListeners();
      await _saveSessions(); // Save progress

      try {
        final result = await SmsGatewayService.sendSms(
          to:      recipient.phone,
          message: session.message,
          simSlot: session.simSlot,
        );
        recipient.msgId = result.msgId;

        AppLogger.info(_tag,
            'Queued → ${recipient.name} (${recipient.phone}) '
            'msgId:${result.msgId}');
      } catch (e) {
        recipient.status = SmsRecipientStatus.failed;
        recipient.error  = e.toString();
        recipient.retryCount++;
        AppLogger.error(_tag,
            'Send error → ${recipient.name} (${recipient.phone}): $e');
        notifyListeners();
        await _saveSessions();
      }

      // Small gap between sends to avoid overwhelming the SIM
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Wait for native sent-broadcasts to resolve (up to 10 s)
    await _waitForPendingResults(session, timeout: const Duration(seconds: 10));

    AppLogger.info(_tag,
        'Session ${session.id} pass ${session.retryPass} done — '
        'sent:${session.sentCount} failed:${session.failedCount}');

    // ── Retry logic ──────────────────────────────────────────────────────────
    if (session.failedCount > 0 &&
        session.retryPass < SmsSession.maxRetries) {
      session.retryPass++;
      session.state = SmsSessionState.retrying;
      await _saveSessions();
      notifyListeners();

      AppLogger.info(_tag,
          'Session ${session.id} — waiting 3 s before retry '
          'pass ${session.retryPass}');

      await Future.delayed(const Duration(seconds: 3));

      await _runPass(session);
    } else {
      _closeSession(session);
    }
  }

  // ── Poll until no recipients are left pending (or timeout) ───────────────
  Future<void> _waitForPendingResults(
    SmsSession session, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pending = session.recipients
          .where((r) => r.msgId != null && r.status == SmsRecipientStatus.pending)
          .toList();
      if (pending.isEmpty) break;

      // Poll each pending message
      for (final r in pending) {
        try {
          final status = await SmsGatewayService.getSmsStatus(r.msgId!);
          if (status.sent == true) {
            r.status = SmsRecipientStatus.sent;
            AppLogger.info(_tag, 'Sent confirmed → ${r.name} (${r.phone})');
          } else if (status.sent == false) {
            r.status = SmsRecipientStatus.failed;
            r.error  = status.sentError ?? 'Send failed';
            r.retryCount++;
            AppLogger.warn(_tag,
                'Send failed → ${r.name} (${r.phone}): ${r.error}');
          }
        } catch (_) {}
      }
      await _saveSessions();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 800));
    }

    // Any still-pending after timeout → mark failed
    for (final r in session.recipients) {
      if (r.status == SmsRecipientStatus.pending && r.msgId != null) {
        r.status = SmsRecipientStatus.failed;
        r.error  = 'Timeout waiting for confirmation';
        r.retryCount++;
        AppLogger.warn(_tag, 'Timeout → ${r.name} (${r.phone})');
      }
    }
    await _saveSessions();
    notifyListeners();
  }

  // ── Handle delivery receipts pushed from native layer ─────────────────────
  void _onNativeStatusUpdate(SmsResult result) {
    bool updated = false;
    for (final session in sessions) {
      for (final r in session.recipients) {
        if (r.msgId == result.msgId) {
          if (result.delivered == true) {
            AppLogger.info(_tag,
                'Delivery receipt → ${r.name} (${r.phone}) msgId:${r.msgId}');
          }
          updated = true;
          break;
        }
      }
      if (updated) break;
    }
    if (updated) {
      _saveSessions();
      notifyListeners();
    }
  }

  // ── Finalise session ──────────────────────────────────────────────────────
  void _closeSession(SmsSession session) {
    session.state      = SmsSessionState.done;
    session.finishedAt = DateTime.now();
    _saveSessions();
    notifyListeners();

    AppLogger.info(_tag,
        'Session ${session.id} complete — '
        'sent:${session.sentCount}/${session.totalCount} '
        'failed:${session.failedCount} '
        'retries:${session.retryPass}');
  }

  // ── Delete single session ─────────────────────────────────────────────────
  Future<void> deleteSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;

    sessions.removeAt(index);
    await _saveSessions();
    notifyListeners();
    AppLogger.info(_tag, 'Session $id deleted');
  }

  // ── Clear all sessions ────────────────────────────────────────────────────
  Future<void> clearAllSessions() async {
    sessions.clear();
    try {
      final box = Hive.box<SmsSession>(_sessionsBoxName);
      await box.clear();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to clear sessions box: $e');
    }
    notifyListeners();
    AppLogger.info(_tag, 'All sessions cleared');
  }
}