import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:collection/collection.dart';

import '../root/models/contact.dart';
import '../root/models/sms_session.dart';
import 'sms_gateway_service.dart';
import 'app_logger.dart';

const String _tag = 'SmsSessionStore';
const String _sessionsBoxName = 'sms_sessions';

class SmsSessionStore extends ChangeNotifier {
  static final SmsSessionStore _instance = SmsSessionStore._();
  factory SmsSessionStore() => _instance;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final List<SmsSession> sessions = [];
  bool _isProcessing = false;

  SmsSessionStore._() {
    SmsGatewayService.statusUpdates.listen(_onNativeStatusUpdate);
    _initHive();
  }

  Future<void> _initHive() async {
    try {
      final box = await Hive.openBox<SmsSession>(_sessionsBoxName);
      sessions.clear();
      sessions.addAll(box.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)));
      _isLoaded = true;
      notifyListeners();
      AppLogger.info(_tag, 'Loaded ${sessions.length} sessions from Hive');
      _resumeSessions();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load sessions: $e');
      _isLoaded = true;
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

  Future<void> _resumeSessions() async {
    if (_isProcessing) return;
    final running = sessions.firstWhereOrNull(
      (s) => s.state != SmsSessionState.done,
    );
    if (running != null) {
      AppLogger.info(_tag, 'Resuming session ${running.id}');
      await _runPass(running);
    }
  }

  Future<void> startSession({required String message, required int simSlot, required String simLabel}) async {
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
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      startedAt: DateTime.now(),
      simSlot: simSlot,
      simLabel: simLabel,
      recipients: recipients,
    );

    sessions.insert(0, session);
    await _saveSessions();
    notifyListeners();

    AppLogger.info(_tag, 'Session ${session.id} started — ${recipients.length} recipients, SIM: $simLabel');

    await SmsGatewayService.startForegroundService();
    await _runPass(session);
  }

  // Loop-based retry logic – no recursion
  Future<void> _runPass(SmsSession session) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        // Determine targets for this pass
        List<SmsRecipient> targets;

        if (session.retryPass == 0) {
          // First pass: send to all pending recipients
          targets = session.recipients.where((r) => r.status == SmsRecipientStatus.pending).toList();
        } else {
          // Retry passes: failed or sentNotDelivered with retries left
          targets = session.recipients.where((r) {
            if (r.status == SmsRecipientStatus.failed && r.retryCount < SmsSession.maxSendRetries) return true;
            if (r.status == SmsRecipientStatus.sentNotDelivered &&
                (r.deliveryRetryCount ?? 0) < SmsSession.maxDeliveryRetries) return true;
            return false;
          }).toList();
        }

        if (targets.isEmpty) {
          // No more recipients to process – session done
          _closeSession(session);
          await SmsGatewayService.stopForegroundService();
          break;
        }

        AppLogger.info(_tag, 'Session ${session.id} — pass ${session.retryPass}, sending to ${targets.length} recipients');

        // For retry passes, increment retry counters before sending
        for (final r in targets) {
          if (r.status == SmsRecipientStatus.sentNotDelivered) {
            r.deliveryRetryCount = (r.deliveryRetryCount ?? 0) + 1;
          }
          // For failed, retryCount already incremented; we don't increment again here
          r.status = SmsRecipientStatus.pending;
          r.error = null;
          r.msgId = null;
          notifyListeners();
          await _saveSessions();
        }

        // Send SMS for each target
        for (final recipient in targets) {
          try {
            final result = await SmsGatewayService.sendSms(
              to: recipient.phone,
              message: session.message,
              simSlot: session.simSlot,
            );
            recipient.msgId = result.msgId;
            AppLogger.info(_tag, 'Queued → ${recipient.name} (${recipient.phone}) msgId:${result.msgId}');
          } catch (e) {
            recipient.status = SmsRecipientStatus.failed;
            recipient.error = e.toString();
            recipient.retryCount++;
            AppLogger.error(_tag, 'Send error → ${recipient.name} (${recipient.phone}): $e');
          }
          await _saveSessions();
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 1000));
        }

        // Wait for delivery status updates
        await _waitForPendingResults(session, timeout: const Duration(seconds: 30));

        // Check if we need another retry pass
        final anyFailed = session.recipients.any(
          (r) => r.status == SmsRecipientStatus.failed && r.retryCount < SmsSession.maxSendRetries,
        );
        final anyNotDelivered = session.recipients.any(
          (r) => r.status == SmsRecipientStatus.sentNotDelivered &&
              (r.deliveryRetryCount ?? 0) < SmsSession.maxDeliveryRetries,
        );

        if (!anyFailed && !anyNotDelivered) {
          // All recipients are done or out of retries
          _closeSession(session);
          await SmsGatewayService.stopForegroundService();
          break;
        }

        // Need another retry pass
        session.retryPass++;
        session.state = SmsSessionState.retrying;
        await _saveSessions();
        notifyListeners();

        AppLogger.info(_tag, 'Session ${session.id} — waiting 8s before retry pass ${session.retryPass}');
        await Future.delayed(const Duration(seconds: 8));
        // Continue loop for next pass
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _waitForPendingResults(SmsSession session, {required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pending = session.recipients.where((r) => r.msgId != null && r.status == SmsRecipientStatus.pending).toList();
      if (pending.isEmpty) break;

      for (final r in pending) {
        try {
          final status = await SmsGatewayService.getSmsStatus(r.msgId!);
          if (status.sent == true) {
            if (status.delivered == true) {
              r.status = SmsRecipientStatus.sent;
            } else {
              r.status = SmsRecipientStatus.sentNotDelivered;
            }
          } else if (status.sent == false) {
            r.status = SmsRecipientStatus.failed;
            r.error = status.sentError ?? 'Send failed';
            r.retryCount++;
          }
        } catch (_) {}
      }
      await _saveSessions();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    // Timeout: mark remaining pending as failed
    for (final r in session.recipients) {
      if (r.status == SmsRecipientStatus.pending && r.msgId != null) {
        r.status = SmsRecipientStatus.failed;
        r.error = 'Timeout waiting for confirmation';
        r.retryCount++;
      }
    }
    await _saveSessions();
    notifyListeners();
  }

  void _onNativeStatusUpdate(SmsResult result) {
    for (final session in sessions) {
      for (final r in session.recipients) {
        if (r.msgId == result.msgId) {
          if (result.delivered == true) {
            r.status = SmsRecipientStatus.sent;
            AppLogger.info(_tag, 'Delivery receipt → ${r.name} (${r.phone})');
          } else if (result.delivered == false) {
            r.status = SmsRecipientStatus.sentNotDelivered;
          }
          _saveSessions();
          notifyListeners();
          return;
        }
      }
    }
  }

  void _closeSession(SmsSession session) {
    session.state = SmsSessionState.done;
    session.finishedAt = DateTime.now();
    _saveSessions();
    notifyListeners();
    AppLogger.info(
      _tag,
      'Session ${session.id} complete — sent:${session.sentCount} failed:${session.failedCount} notDelivered:${session.sentButNotDeliveredCount}',
    );
  }

  Future<void> deleteSession(String id) async {
    sessions.removeWhere((s) => s.id == id);
    await _saveSessions();
    notifyListeners();
  }

  Future<void> clearAllSessions() async {
    sessions.clear();
    try {
      final box = Hive.box<SmsSession>(_sessionsBoxName);
      await box.clear();
    } catch (_) {}
    notifyListeners();
  }
}