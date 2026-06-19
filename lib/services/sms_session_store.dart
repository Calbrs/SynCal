import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  Completer<void>? _loadCompleter;

  /// True when this instance is running inside a headless FlutterEngine
  /// (AlarmManager callback or Workmanager task). In headless context,
  /// MethodChannel calls to MainActivity are unavailable — sendSms,
  /// startForegroundService, stopForegroundService, getSmsStatus, etc.
  /// will all throw MissingPluginException.
  ///
  /// We detect headless context by checking whether SmsGatewayService
  /// could successfully initialise its channel listener. If any channel
  /// call throws MissingPluginException we set this flag and skip all
  /// subsequent native calls.
  bool _isHeadlessContext = false;

  SmsSessionStore._() {
    _loadCompleter = Completer<void>();
    SmsGatewayService.statusUpdates.listen(_onNativeStatusUpdate);
    _initHive();
  }

  Future<void> awaitLoaded() {
    if (_isLoaded) return Future.value();
    return _loadCompleter?.future ?? Future.value();
  }

  Future<void> _initHive() async {
    try {
      final box = await Hive.openBox<SmsSession>(_sessionsBoxName);
      sessions.clear();
      sessions.addAll(
        box.values.toList()..sort((a, b) => b.startedAt.compareTo(a.startedAt)),
      );
      _isLoaded = true;
      notifyListeners();
      AppLogger.info(_tag, 'Loaded ${sessions.length} sessions from Hive');
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.complete();
      }
      // Only resume sessions from the UI isolate — headless context cannot
      // send SMS (no MainActivity MethodChannel handler). The UI isolate will
      // resume any interrupted session when the user opens the app, or the
      // next AlarmManager tick will handle new scheduled messages.
      if (!_isHeadlessContext) {
        _resumeSessions();
      }
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load sessions: $e');
      _isLoaded = true;
      notifyListeners();
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.complete();
      }
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

  // ---- Public helper ----

  /// Returns the first session associated with the given [scheduleId], or null
  /// if no such session exists. Used by ScheduledMessageStore to detect whether
  /// the other isolate already created a session for a given schedule so we
  /// don't create a duplicate.
  SmsSession? sessionForSchedule(String scheduleId) {
    return sessions.firstWhereOrNull((s) => s.scheduleId == scheduleId);
  }

  // ---- Native service helpers (safe to call from any context) ----

  /// Starts the foreground service. Silently skipped in headless context.
  Future<void> _startForegroundService() async {
    if (_isHeadlessContext) return;
    try {
      await SmsGatewayService.startForegroundService();
    } on MissingPluginException {
      _isHeadlessContext = true;
      AppLogger.info(_tag, 'startForegroundService: headless context detected — skipped.');
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'startForegroundService error: ${e.message}');
    }
  }

  /// Stops the foreground service. Silently skipped in headless context.
  Future<void> _stopForegroundService() async {
    if (_isHeadlessContext) return;
    try {
      await SmsGatewayService.stopForegroundService();
    } on MissingPluginException {
      _isHeadlessContext = true;
      AppLogger.info(_tag, 'stopForegroundService: headless context detected — skipped.');
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'stopForegroundService error: ${e.message}');
    }
  }

  /// Sends an SMS. Returns null and marks recipient as failed in headless context.
  Future<SmsResult?> _sendSms({
    required String to,
    required String message,
    required int simSlot,
  }) async {
    if (_isHeadlessContext) return null;
    try {
      return await SmsGatewayService.sendSms(
        to: to,
        message: message,
        simSlot: simSlot,
      );
    } on MissingPluginException {
      _isHeadlessContext = true;
      AppLogger.info(_tag, 'sendSms: headless context detected — cannot send SMS without MainActivity.');
      return null;
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'sendSms PlatformException: ${e.message}');
      rethrow;
    }
  }

  /// Gets SMS status. Returns null silently in headless context.
  Future<SmsResult?> _getSmsStatus(String msgId) async {
    if (_isHeadlessContext) return null;
    try {
      return await SmsGatewayService.getSmsStatus(msgId);
    } on MissingPluginException {
      _isHeadlessContext = true;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---- Public session management ----

  Future<void> startSession({
    required String message,
    required int simSlot,
    required String simLabel,
  }) async {
    // This is only called from the UI — should never be headless.
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

    await startSessionWithRecipients(
      message: message,
      simSlot: simSlot,
      simLabel: simLabel,
      recipients: recipients,
      // No scheduleId — this is a manual (non-scheduled) send.
    );
  }

  /// Start a session with a pre-built recipient list.
  ///
  /// [scheduleId] — when provided, the session is linked to a scheduled
  /// message. Before creating a new session we check whether a session for
  /// this [scheduleId] already exists (created by the sibling isolate).  If
  /// it does we log and return without creating a duplicate.
  ///
  /// Called both from UI (via ScheduledMessageStore.processDueSchedules)
  /// and from the headless alarm entrypoint. In headless context the session
  /// is saved to Hive but SMS sending is skipped — the UI isolate will resume
  /// it when the app is next opened, or AlarmManager will retry.
  Future<void> startSessionWithRecipients({
    required String message,
    required int simSlot,
    required String simLabel,
    required List<SmsRecipient> recipients,
    String? scheduleId,
  }) async {
    if (recipients.isEmpty) {
      AppLogger.warn(_tag, 'No recipients provided — session aborted.');
      return;
    }

    // FIX (Tatizo 1): If a scheduleId is provided, check whether a session
    // for this schedule already exists (created by the other isolate).
    // Both isolates share the same Hive box — the session written by the
    // first isolate will be in our in-memory list because awaitLoaded()
    // was called before reaching here.
    if (scheduleId != null) {
      final existing = sessionForSchedule(scheduleId);
      if (existing != null) {
        AppLogger.info(
          _tag,
          'startSessionWithRecipients: session ${existing.id} already exists '
          'for schedule $scheduleId — duplicate skipped.',
        );
        return;
      }
    }

    final session = SmsSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      startedAt: DateTime.now(),
      simSlot: simSlot,
      simLabel: simLabel,
      recipients: recipients,
      scheduleId: scheduleId, // store the link so sessionForSchedule() works
    );

    sessions.insert(0, session);
    await _saveSessions();
    notifyListeners();

    AppLogger.info(
      _tag,
      'Session ${session.id} started — ${recipients.length} recipients, '
      'SIM: $simLabel${scheduleId != null ? ', scheduleId: $scheduleId' : ''}',
    );

    if (_isHeadlessContext) {
      // Cannot send SMS in headless context — save session as pending so the
      // UI isolate resumes it when the app opens. The schedule is already
      // marked as sent by ScheduledMessageStore (session creation = delivery
      // attempt). The session itself will be retried by _resumeSessions().
      AppLogger.info(
        _tag,
        'Session ${session.id}: headless context — SMS deferred to UI isolate.',
      );
      return;
    }

    await _startForegroundService();
    await _runPass(session);
  }

  Future<void> retrySession(String sessionId) async {
    final session = sessions.firstWhereOrNull((s) => s.id == sessionId);
    if (session == null) {
      AppLogger.warn(_tag, 'Session $sessionId not found');
      return;
    }
    if (session.isComplete) {
      AppLogger.warn(_tag, 'Session $sessionId is already complete, cannot retry.');
      return;
    }

    bool hasTargets = false;
    for (final r in session.recipients) {
      if (r.status == SmsRecipientStatus.failed &&
          r.retryCount < SmsSession.maxSendRetries) {
        r.status = SmsRecipientStatus.pending;
        r.error = null;
        r.msgId = null;
        hasTargets = true;
      } else if (r.status == SmsRecipientStatus.sentNotDelivered &&
          (r.deliveryRetryCount ?? 0) < SmsSession.maxDeliveryRetries) {
        r.status = SmsRecipientStatus.pending;
        r.error = null;
        r.msgId = null;
        hasTargets = true;
      }
    }

    if (!hasTargets) {
      AppLogger.warn(_tag, 'No retriable recipients in session $sessionId');
      return;
    }

    await _saveSessions();
    notifyListeners();
    AppLogger.info(_tag, 'Retrying session $sessionId');

    await _startForegroundService();
    await _runPass(session);
  }

  Future<void> _runPass(SmsSession session) async {
    if (_isProcessing) return;
    if (_isHeadlessContext) {
      AppLogger.info(_tag, '_runPass: headless context — skipping SMS sending.');
      return;
    }
    _isProcessing = true;

    try {
      while (true) {
        List<SmsRecipient> targets;

        if (session.retryPass == 0) {
          targets = session.recipients
              .where((r) => r.status == SmsRecipientStatus.pending)
              .toList();
        } else {
          targets = session.recipients.where((r) {
            if (r.status == SmsRecipientStatus.failed &&
                r.retryCount < SmsSession.maxSendRetries) { return true; }
            if (r.status == SmsRecipientStatus.sentNotDelivered &&
                (r.deliveryRetryCount ?? 0) < SmsSession.maxDeliveryRetries) {
              return true;
            }
            return false;
          }).toList();
        }

        if (targets.isEmpty) {
          _closeSession(session);
          await _stopForegroundService();
          break;
        }

        AppLogger.info(
          _tag,
          'Session ${session.id} — pass ${session.retryPass}, sending to ${targets.length} recipients',
        );

        for (final r in targets) {
          if (r.status == SmsRecipientStatus.sentNotDelivered) {
            r.deliveryRetryCount = (r.deliveryRetryCount ?? 0) + 1;
          }
          r.status = SmsRecipientStatus.pending;
          r.error = null;
          r.msgId = null;
          notifyListeners();
          await _saveSessions();
        }

        for (final recipient in targets) {
          try {
            final result = await _sendSms(
              to: recipient.phone,
              message: session.message,
              simSlot: session.simSlot,
            );
            if (result != null) {
              recipient.msgId = result.msgId;
              AppLogger.info(
                _tag,
                'Queued → ${recipient.name} (${recipient.phone}) msgId:${result.msgId}',
              );
            } else if (_isHeadlessContext) {
              // sendSms returned null because we're headless — stop loop
              AppLogger.info(_tag, 'Headless detected mid-pass — aborting send loop.');
              return;
            }
          } catch (e) {
            recipient.status = SmsRecipientStatus.failed;
            recipient.error = e.toString();
            recipient.retryCount++;
            AppLogger.error(
              _tag,
              'Send error → ${recipient.name} (${recipient.phone}): $e',
            );
          }
          await _saveSessions();
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 1000));
        }

        await _waitForPendingResults(session, timeout: const Duration(seconds: 30));

        final anyFailed = session.recipients.any(
          (r) =>
              r.status == SmsRecipientStatus.failed &&
              r.retryCount < SmsSession.maxSendRetries,
        );
        final anyNotDelivered = session.recipients.any(
          (r) =>
              r.status == SmsRecipientStatus.sentNotDelivered &&
              (r.deliveryRetryCount ?? 0) < SmsSession.maxDeliveryRetries,
        );

        if (!anyFailed && !anyNotDelivered) {
          _closeSession(session);
          await _stopForegroundService();
          break;
        }

        session.retryPass++;
        session.state = SmsSessionState.retrying;
        await _saveSessions();
        notifyListeners();

        AppLogger.info(
          _tag,
          'Session ${session.id} — waiting 8s before retry pass ${session.retryPass}',
        );
        await Future.delayed(const Duration(seconds: 8));
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _waitForPendingResults(
    SmsSession session, {
    required Duration timeout,
  }) async {
    if (_isHeadlessContext) return;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final pending = session.recipients
          .where((r) => r.msgId != null && r.status == SmsRecipientStatus.pending)
          .toList();
      if (pending.isEmpty) break;

      for (final r in pending) {
        final status = await _getSmsStatus(r.msgId!);
        if (status == null) continue;
        if (status.sent == true) {
          r.status = status.delivered == true
              ? SmsRecipientStatus.sent
              : SmsRecipientStatus.sentNotDelivered;
        } else if (status.sent == false) {
          r.status = SmsRecipientStatus.failed;
          r.error = status.sentError ?? 'Send failed';
          r.retryCount++;
        }
      }
      await _saveSessions();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

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
      'Session ${session.id} complete — sent:${session.sentCount} '
      'failed:${session.failedCount} notDelivered:${session.sentButNotDeliveredCount}',
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