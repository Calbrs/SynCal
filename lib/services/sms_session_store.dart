import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:collection/collection.dart';

import '../root/models/contact.dart';
import '../root/models/contact_group.dart';
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

  /// True when the SMS MethodChannel itself is unavailable (i.e. neither
  /// MainActivity nor a headless engine with the SMS channel registered is
  /// present). Only set to true when sendSms() throws MissingPluginException.
  ///
  /// NOTE: This is intentionally separate from _canStartForegroundService.
  /// The ScheduleAlarmReceiver headless engine DOES register the SMS channel,
  /// so SMS sending is possible in that context even though the foreground
  /// service channel is not available.
  bool _isSmsChannelUnavailable = false;

  /// True when the foreground service channel is unavailable (expected in any
  /// headless context). Does NOT block SMS sending.
  bool _canStartForegroundService = true;

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
      // Only resume sessions from the UI isolate — the headless engine will
      // handle its own scheduled sends. The UI isolate resumes any session that
      // was saved-but-not-sent (e.g. from a previous headless SMS failure).
      if (!_isSmsChannelUnavailable) {
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
  /// if no such session exists.
  ///
  /// IMPORTANT: This checks the Hive box on disk directly (not the in-memory
  /// list) to ensure cross-isolate visibility. Both the UI isolate and the
  /// headless alarm isolate share the same Hive files on disk. If the headless
  /// isolate wrote a session and the UI isolate's in-memory list hasn't
  /// reloaded yet, this will still find it — preventing duplicate sessions.
  SmsSession? sessionForSchedule(String scheduleId) {
    // Check disk first for cross-isolate safety
    try {
      final box = Hive.box<SmsSession>(_sessionsBoxName);
      final fromDisk = box.values.firstWhereOrNull((s) => s.scheduleId == scheduleId);
      if (fromDisk != null) return fromDisk;
    } catch (_) {
      // Box not open yet — fall through to in-memory check
    }
    return sessions.firstWhereOrNull((s) => s.scheduleId == scheduleId);
  }

  // ---- Native service helpers (safe to call from any context) ----

  /// Starts the foreground service. Silently skipped when foreground service
  /// channel is unavailable (headless context). Does NOT affect SMS sending.
  Future<void> _startForegroundService() async {
    if (!_canStartForegroundService) return;
    try {
      await SmsGatewayService.startForegroundService();
    } on MissingPluginException {
      // Expected in headless context — foreground service channel not registered.
      // SMS channel is still available; only skip foreground service.
      _canStartForegroundService = false;
      AppLogger.info(_tag, 'startForegroundService: not available in this context — skipped (SMS will still be sent).');
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'startForegroundService error: ${e.message}');
    }
  }

  /// Stops the foreground service. Silently skipped when unavailable.
  Future<void> _stopForegroundService() async {
    if (!_canStartForegroundService) return;
    try {
      await SmsGatewayService.stopForegroundService();
    } on MissingPluginException {
      _canStartForegroundService = false;
      AppLogger.info(_tag, 'stopForegroundService: not available in this context — skipped.');
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'stopForegroundService error: ${e.message}');
    }
  }

  /// Sends an SMS via the native channel. Returns null only if the SMS channel
  /// itself is unavailable (extremely rare — only if neither MainActivity nor
  /// the headless engine channel is active in this process).
  Future<SmsResult?> _sendSms({
    required String to,
    required String message,
    required int simSlot,
  }) async {
    if (_isSmsChannelUnavailable) return null;
    try {
      return await SmsGatewayService.sendSms(
        to: to,
        message: message,
        simSlot: simSlot,
      );
    } on MissingPluginException {
      // The SMS channel itself is not registered in this context.
      // This should not happen in normal or headless-alarm contexts, but
      // could happen in a Workmanager isolate where no channel is set up.
      _isSmsChannelUnavailable = true;
      AppLogger.warn(_tag, 'sendSms: SMS channel unavailable in this context — session deferred.');
      return null;
    } on PlatformException catch (e) {
      AppLogger.error(_tag, 'sendSms PlatformException: ${e.message}');
      rethrow;
    }
  }

  /// Gets SMS status. Returns null silently if unavailable.
  Future<SmsResult?> _getSmsStatus(String msgId) async {
    if (_isSmsChannelUnavailable) return null;
    try {
      return await SmsGatewayService.getSmsStatus(msgId);
    } on MissingPluginException {
      _isSmsChannelUnavailable = true;
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
    List<String>? contactKeys,
    String? groupId,
  }) async {
    // This is only called from the UI — should never be headless.
    final box = Hive.box<Contact>('contacts');
    final recipients = <SmsRecipient>[];

    // Deduplicate by contact name: if the same name appears with multiple
    // phone numbers, only the FIRST number is used. This prevents a contact
    // with two stored numbers from receiving the same SMS twice.
    final seenNames = <String>{};

    // Determine which contacts to iterate over based on audience scope
    Iterable<Contact> targetContacts;
    if (contactKeys != null && contactKeys.isNotEmpty) {
      // Specific individuals selected
      targetContacts = contactKeys.map((k) {
        final idx = box.keys.toList().indexWhere((key) => key.toString() == k);
        return idx != -1 ? box.getAt(idx) : null;
      }).whereType<Contact>();
    } else if (groupId != null) {
      // A group selected — resolve its member keys
      final groupBox = Hive.box<ContactGroup>('contact_groups');
      final group = groupBox.values.cast<ContactGroup?>().firstWhere(
        (g) => g?.id == groupId, orElse: () => null);
      if (group == null) {
        AppLogger.warn(_tag, 'Group $groupId not found — session aborted.');
        return;
      }
      targetContacts = group.contactKeys.map((k) {
        final idx = box.keys.toList().indexWhere((key) => key.toString() == k);
        return idx != -1 ? box.getAt(idx) : null;
      }).whereType<Contact>();
    } else {
      // Default: all contacts
      targetContacts = box.values;
    }

    for (final contact in targetContacts) {
      if (contact.phones.isEmpty) continue;
      final normalizedName = contact.name.trim().toLowerCase();
      if (seenNames.contains(normalizedName)) {
        AppLogger.info(
          _tag,
          'startSession: skipping duplicate name "${contact.name}" '
          '(already added first number for this contact).',
        );
        continue;
      }
      seenNames.add(normalizedName);
      // Use only the first phone number for this contact name.
      recipients.add(SmsRecipient(name: contact.name, phone: contact.phones[0]));
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
  /// this [scheduleId] already exists (created by the sibling isolate). If
  /// it does we log and return without creating a duplicate.
  ///
  /// Called both from UI (via ScheduledMessageStore.processDueSchedules)
  /// and from the headless alarm entrypoint. In headless context the SMS
  /// channel IS available (registered by ScheduleAlarmReceiver), so sending
  /// proceeds normally. The foreground service is skipped in headless context
  /// but that does not affect SMS delivery.
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

    // If a scheduleId is provided, check whether a session for this schedule
    // already exists (created by the other isolate). Both isolates share the
    // same Hive box — the session written by the first isolate will be in our
    // in-memory list because awaitLoaded() was called before reaching here.
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
      scheduleId: scheduleId,
    );

    sessions.insert(0, session);
    await _saveSessions();
    notifyListeners();

    AppLogger.info(
      _tag,
      'Session ${session.id} started — ${recipients.length} recipients, '
      'SIM: $simLabel${scheduleId != null ? ', scheduleId: $scheduleId' : ''}',
    );

    // Start the foreground service if available (UI context).
    // If unavailable (headless context), this is silently skipped and SMS
    // sending continues normally via the headless engine's SMS channel.
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
      // Only retry hard send failures — NOT sentNotDelivered.
      // sentNotDelivered means the SMS reached the carrier; retrying it
      // would cause a duplicate message (especially on Samsung/AOSP where
      // delivery receipts are often never sent).
      if (r.status == SmsRecipientStatus.failed &&
          r.retryCount < SmsSession.maxSendRetries) {
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
    if (_isSmsChannelUnavailable) {
      // SMS channel is not available in this isolate context. Save the session
      // as-is so the UI isolate can resume it when the app opens.
      AppLogger.info(_tag, '_runPass: SMS channel unavailable — session ${session.id} deferred to UI isolate.');
      return;
    }
    _isProcessing = true;

    try {
      while (true) {
        List<SmsRecipient> targets;

        // Do NOT include sentNotDelivered in retry targets.
        // Delivery receipts are optional — many SMS apps (Samsung Messages,
        // AOSP Messaging) never send them. If the OS confirmed the message
        // was handed to the carrier (sent=true), the SMS went out. Retrying
        // based on missing delivery reports causes 4-6 duplicate messages.
        if (session.retryPass == 0) {
          targets = session.recipients
              .where((r) => r.status == SmsRecipientStatus.pending)
              .toList();
        } else {
          targets = session.recipients.where((r) {
            // Only retry hard send failures (OS rejected the send call).
            if (r.status == SmsRecipientStatus.failed &&
                r.retryCount < SmsSession.maxSendRetries) { return true; }
            // sentNotDelivered = SMS reached the carrier; do NOT retry.
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
            } else if (_isSmsChannelUnavailable) {
              // SMS channel became unavailable mid-pass — stop and defer.
              AppLogger.info(_tag, 'SMS channel unavailable mid-pass — aborting send loop, session deferred.');
              await _saveSessions();
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

        await _waitForPendingResults(session, timeout: const Duration(seconds: 15));

        // Only retry on hard send failures. sentNotDelivered is treated as
        // success — the SMS was handed to the carrier.
        final anyFailed = session.recipients.any(
          (r) =>
              r.status == SmsRecipientStatus.failed &&
              r.retryCount < SmsSession.maxSendRetries,
        );

        if (!anyFailed) {
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
    if (_isSmsChannelUnavailable) return;

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
          // OS confirmed the SMS was handed to the carrier.
          // Mark as sent if delivery receipt arrived, sentNotDelivered otherwise.
          // sentNotDelivered is treated as success — delivery receipts are
          // optional and many SMS apps (Samsung, AOSP) never fire them.
          r.status = status.delivered == true
              ? SmsRecipientStatus.sent
              : SmsRecipientStatus.sentNotDelivered;
        } else if (status.sent == false) {
          // OS explicitly rejected the send (e.g. no signal, no SIM).
          // This is a true failure — eligible for 1 retry.
          r.status = SmsRecipientStatus.failed;
          r.error = status.sentError ?? 'Send failed';
          r.retryCount++;
        }
        // If status.sent == null the broadcast hasn't arrived yet — keep waiting.
      }
      await _saveSessions();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    // Timeout reached. Classify remaining pending recipients:
    //   • Has msgId  → OS accepted the send call; treat as sentNotDelivered
    //                   (success) — the carrier just didn't confirm delivery.
    //                   This prevents false "failed" on Samsung/AOSP where
    //                   the delivery broadcast never fires.
    //   • No msgId   → OS call never returned; this is a genuine failure.
    for (final r in session.recipients) {
      if (r.status != SmsRecipientStatus.pending) continue;
      if (r.msgId != null) {
        // SMS was handed to the OS — assume it went out.
        r.status = SmsRecipientStatus.sentNotDelivered;
        r.error = null;
        AppLogger.info(
          _tag,
          'Timeout: ${r.name} has msgId — treating as sentNotDelivered (sent, no delivery receipt).',
        );
      } else {
        // OS never accepted the call — mark as failed (1 retry allowed).
        r.status = SmsRecipientStatus.failed;
        r.error = 'No send confirmation received';
        r.retryCount++;
        AppLogger.warn(_tag, 'Timeout: ${r.name} has no msgId — marking failed.');
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