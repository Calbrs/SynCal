import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../root/models/contact.dart';
import '../root/models/scheduled_message.dart';
import '../root/models/sms_session.dart';
import 'app_logger.dart';
import 'sms_session_store.dart';
import 'sms_gateway_service.dart';

const String _tag = 'ScheduledMessageStore';
const String _scheduleBoxName = 'scheduled_messages';

class ScheduledMessageStore extends ChangeNotifier {
  static final ScheduledMessageStore _instance = ScheduledMessageStore._();
  factory ScheduledMessageStore() => _instance;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final List<ScheduledMessage> schedules = [];

  Completer<void>? _loadCompleter;
  bool _isProcessingDue = false;

  /// Per-schedule-ID lock set. Prevents markAsSent from being called twice
  /// for the same schedule ID when both UI isolate and headless isolate race
  /// to call processDueSchedules at the same time.
  final Set<String> _inFlightScheduleIds = {};

  ScheduledMessageStore._() {
    _loadCompleter = Completer<void>();
    _initHive();
  }

  Future<void> awaitLoaded() {
    if (_isLoaded) return Future.value();
    return _loadCompleter?.future ?? Future.value();
  }

  Future<void> _initHive() async {
    try {
      final box = await Hive.openBox<ScheduledMessage>(_scheduleBoxName);
      schedules.clear();
      schedules.addAll(box.values.toList()
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime)));
      _isLoaded = true;
      notifyListeners();
      AppLogger.info(_tag, 'Loaded ${schedules.length} scheduled messages');
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.complete();
      }
      // Sync any schedules that the native Kotlin layer sent while app was closed.
      await _syncNativeState();
      await _autoDeleteExpired();
      await _scheduleNextAlarm();
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load schedules: $e');
      _isLoaded = true;
      notifyListeners();
      if (_loadCompleter != null && !_loadCompleter!.isCompleted) {
        _loadCompleter!.complete();
      }
    }
  }

  /// Reads any schedules marked sent/failed by the native Kotlin layer
  /// (while the app was closed) and updates Hive to match.
  Future<void> _syncNativeState() async {
    try {
      final nativeStates = await SmsGatewayService.getSyncState();
      if (nativeStates.isEmpty) return;
      bool changed = false;
      for (final state in nativeStates) {
        final id = state['scheduleId'] ?? '';
        final status = state['status'] ?? '';
        if (id.isEmpty) continue;
        final idx = schedules.indexWhere((s) => s.id == id);
        if (idx == -1) continue;
        final s = schedules[idx];
        // Treat 'processing' as 'sent': if the app was killed while Kotlin was
        // mid-send the SMS was already handed to the Android telephony stack.
        if ((status == 'sent' || status == 'processing') && s.status == ScheduleStatus.pending) {
          // Native layer sent this while app was closed — mark as sent in Hive.
          schedules[idx] = s.copyWith(
            status: ScheduleStatus.sent,
            completedAt: DateTime.now(),
            isActive: false,
          );
          AppLogger.info(_tag, '_syncNativeState: marked ${s.id} as sent (sent by Kotlin natively)');
          // Clean up native store entry now that Hive is updated.
          await SmsGatewayService.deleteScheduleFromNative(id);
          changed = true;
        } else if (status == 'failed' && s.status == ScheduleStatus.pending) {
          schedules[idx] = s.copyWith(
            status: ScheduleStatus.failed,
            completedAt: DateTime.now(),
            isActive: false,
          );
          AppLogger.info(_tag, '_syncNativeState: marked ${s.id} as failed (native Kotlin reported failure)');
          await SmsGatewayService.deleteScheduleFromNative(id);
          changed = true;
        }
      }
      if (changed) {
        await _saveSchedules();
        notifyListeners();
      }
    } on MissingPluginException {
      // Running in headless context — native sync channel not available, skip.
    } catch (e) {
      AppLogger.error(_tag, '_syncNativeState error: $e');
    }
  }

  Future<void> _saveSchedules() async {
    try {
      final box = Hive.box<ScheduledMessage>(_scheduleBoxName);
      await box.clear();
      await box.addAll(schedules);
    } catch (e) {
      AppLogger.error(_tag, 'Failed to save schedules: $e');
    }
  }

  Future<void> _autoDeleteExpired() async {
    final toRemove = schedules.where((s) => s.shouldAutoDelete).toList();
    if (toRemove.isNotEmpty) {
      schedules.removeWhere((s) => s.shouldAutoDelete);
      await _saveSchedules();
      notifyListeners();
      AppLogger.info(_tag, 'Auto‑deleted ${toRemove.length} expired schedules');
    }
  }

  /// Schedules the next native AlarmManager alarm for the earliest pending
  /// scheduled message. Uses setExactAndAllowWhileIdle so the alarm fires at
  /// the scheduled time even in doze/battery-saver mode.
  ///
  /// Safe to call from both the UI isolate and the headless isolate.
  /// In the headless isolate context, re-arming the next alarm may throw
  /// MissingPluginException — this is silently ignored because the alarm
  /// that triggered this headless run was already set by the UI isolate, and
  /// after processing the Dart side will re-arm the alarm the next time the
  /// UI isolate runs (or the 15-min WorkManager safety-net will catch it).
  Future<void> _scheduleNextAlarm() async {
    final pendingActive = schedules.where(
      (s) => s.isActive && s.status == ScheduleStatus.pending,
    ).toList();

    try {
      if (pendingActive.isEmpty) {
        // No more pending schedules — cancel the native alarm.
        await SmsGatewayService.cancelAlarm();
        return;
      }
      pendingActive.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      final next = pendingActive.first.scheduledTime;
      // Use the native AlarmManager path (setExactAndAllowWhileIdle) for
      // reliable exact-time delivery. WorkManager is only the 15-min safety-net.
      await SmsGatewayService.scheduleAlarm(next);
      AppLogger.info(_tag, '_scheduleNextAlarm: native alarm set for $next');
    } on MissingPluginException {
      // Running inside a headless FlutterEngine where only the SMS channel is
      // registered — the alarm scheduling channel (MainActivity) is not active.
      // This is expected and safe: the UI isolate will re-arm the alarm the
      // next time the app opens, and the 15-min safety-net covers the gap.
      AppLogger.info(
        _tag,
        '_scheduleNextAlarm: skipped in headless context (expected) — '
        'UI isolate will re-arm alarm on next open.',
      );
    } on PlatformException catch (e) {
      AppLogger.error(_tag, '_scheduleNextAlarm platform error: ${e.message}');
    } catch (e) {
      AppLogger.error(_tag, '_scheduleNextAlarm unexpected error: $e');
    }
  }

  Future<void> addSchedule(ScheduledMessage schedule) async {
    schedules.add(schedule);
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Added schedule: ${schedule.id}');
    // Persist to native store so Kotlin can send SMS without booting Flutter.
    await _persistToNative(schedule);
    await _scheduleNextAlarm();
  }

  Future<void> updateSchedule(ScheduledMessage updated) async {
    final index = schedules.indexWhere((s) => s.id == updated.id);
    if (index != -1) {
      schedules[index] = updated;
      await _saveSchedules();
      notifyListeners();
      AppLogger.info(_tag, 'Updated schedule: ${updated.id}');
      // Re-persist with updated data.
      if (updated.isActive && updated.status == ScheduleStatus.pending) {
        await _persistToNative(updated);
      } else {
        await SmsGatewayService.deleteScheduleFromNative(updated.id);
      }
      await _scheduleNextAlarm();
    }
  }

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((s) => s.id == id);
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Deleted schedule: $id');
    // Remove from native store so alarm doesn't fire for deleted schedule.
    await SmsGatewayService.deleteScheduleFromNative(id);
    await _scheduleNextAlarm();
  }

  Future<void> toggleActive(String id) async {
    final schedule = schedules.firstWhere((s) => s.id == id);
    schedule.isActive = !schedule.isActive;
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Toggled active for schedule: $id');
    if (schedule.isActive && schedule.status == ScheduleStatus.pending) {
      await _persistToNative(schedule);
    } else {
      // Disabled — remove from native store so it won't send.
      await SmsGatewayService.deleteScheduleFromNative(id);
    }
    await _scheduleNextAlarm();
  }

  /// Persists a schedule's data to the native Kotlin store so
  /// ScheduleAlarmReceiver can send the SMS without booting a Flutter engine.
  Future<void> _persistToNative(ScheduledMessage schedule) async {
    try {
      // Build recipients list from contacts box.
      final contactBox = Hive.box<Contact>('contacts');
      final recipients = <Map<String, String>>[];
      for (final id in schedule.recipientIds) {
        Contact? contact;
        for (final c in contactBox.values) {
          if (c.studentId != null && c.studentId.toString() == id) {
            contact = c; break;
          }
        }
        if (contact == null) {
          final idx = contactBox.keys.toList().indexWhere((k) => k.toString() == id);
          if (idx != -1) contact = contactBox.getAt(idx);
        }
        if (contact != null && contact.phones.isNotEmpty) {
          recipients.add({'name': contact.name, 'phone': contact.phones[0]});
        }
      }
      if (recipients.isEmpty) return;
      await SmsGatewayService.persistScheduleForAlarm(
        scheduleId: schedule.id,
        message: schedule.message,
        triggerAt: schedule.scheduledTime,
        simSlot: schedule.simSlot,
        recipients: recipients,
      );
      AppLogger.info(_tag, '_persistToNative: persisted ${schedule.id} with ${recipients.length} recipients');
    } on MissingPluginException {
      // Expected in headless context.
    } catch (e) {
      AppLogger.error(_tag, '_persistToNative error: $e');
    }
  }

  List<ScheduledMessage> getDueSchedules() {
    final now = DateTime.now();
    return schedules.where((s) =>
        s.isActive &&
        s.status == ScheduleStatus.pending &&
        (s.scheduledTime.isBefore(now) ||
            s.scheduledTime.isAtSameMomentAs(now))).toList();
  }

  Future<void> markAsSent(ScheduledMessage schedule) async {
    final index = schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;

    // FIX (Tatizo 2): Guard against double markAsSent from racing isolates.
    // If the current in-memory status is no longer `pending`, a sibling isolate
    // already marked it — skip silently to avoid double-advancing repeating
    // schedules or overwriting a `sent` status back to `pending`.
    final current = schedules[index];
    if (current.status != ScheduleStatus.pending) {
      AppLogger.warn(
        _tag,
        'markAsSent: schedule ${schedule.id} is already ${current.status} — skipped (duplicate call).',
      );
      return;
    }

    if (schedule.repetition == Repetition.none) {
      final updated = schedule.copyWith(
        status: ScheduleStatus.sent,
        completedAt: DateTime.now(),
        isActive: false,
      );
      schedules[index] = updated;
    } else {
      final nextTime = schedule.nextOccurrence(DateTime.now());
      final updated = schedule.copyWith(
        scheduledTime: nextTime,
        sentCount: (schedule.sentCount ?? 0) + 1,
        status: ScheduleStatus.pending,
        completedAt: null,
      );
      schedules[index] = updated;
    }

    await _saveSchedules();
    await _autoDeleteExpired();
    notifyListeners();
    await _scheduleNextAlarm();
    AppLogger.info(_tag, 'Marked schedule as sent: ${schedule.id}');
  }

  Future<void> markAsFailed(ScheduledMessage schedule, {String? reason}) async {
    final index = schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;

    final updated = schedule.copyWith(
      status: ScheduleStatus.failed,
      completedAt: DateTime.now(),
      isActive: false,
    );
    schedules[index] = updated;
    await _saveSchedules();
    await _autoDeleteExpired();
    notifyListeners();
    await _scheduleNextAlarm();
    AppLogger.error(_tag, 'Schedule failed: ${schedule.id}, reason: $reason');
  }

  ScheduledMessage? getSchedule(String id) {
    try {
      return schedules.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Whether this store is running in the headless (alarm) isolate.
  /// Set to true by [setHeadlessMode] before calling [processDueSchedules]
  /// from the headless entrypoint.
  bool _isHeadless = false;

  /// Called once from [headless_entrypoint.dart] to switch this store into
  /// headless mode. In headless mode [processDueSchedules] is the SOLE sender
  /// of scheduled SMS. The UI isolate's [processDueSchedules] will only mark
  /// schedules as sent if a headless session is already in Hive — it will
  /// never create a new session itself.
  void setHeadlessMode() => _isHeadless = true;

  /// Called by the UI (manual refresh), by the headless alarm entrypoint,
  /// and by the foreground Dart timer fallback.
  ///
  /// SINGLE-PATH RULE:
  ///   • Headless isolate  → creates session + sends SMS + marks as sent
  ///   • UI isolate        → marks as sent ONLY if headless already created a
  ///                         session in Hive; never creates a new session
  ///
  /// This eliminates the race condition where both isolates create duplicate
  /// sessions for the same schedule.
  Future<void> processDueSchedules() async {
    if (_isProcessingDue) return;
    _isProcessingDue = true;
    try {
      // Re-open box in case we are in the headless isolate and it wasn't open
      // yet (openBox is a no-op if already open).
      await Hive.openBox<ScheduledMessage>(_scheduleBoxName);

      // Reload schedules from Hive so we see changes made by the other isolate
      // (e.g. headless isolate already marked a schedule as `sent` between the
      // alarm firing and this code running).
      final box = Hive.box<ScheduledMessage>(_scheduleBoxName);
      schedules.clear();
      schedules.addAll(box.values.toList()
        ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime)));

      final due = getDueSchedules();
      if (due.isEmpty) {
        AppLogger.info(_tag, 'processDueSchedules: no due schedules after Hive reload — skipping.');
        await _scheduleNextAlarm();
        return;
      }

      AppLogger.info(_tag, 'Processing ${due.length} due schedules${_isHeadless ? " [headless]" : " [UI]"}');

      final sessionStore = SmsSessionStore();
      await sessionStore.awaitLoaded();

      for (final schedule in due) {
        // --- Per-schedule duplicate guard ---
        if (_inFlightScheduleIds.contains(schedule.id)) {
          AppLogger.info(_tag, 'processDueSchedules: schedule ${schedule.id} already in-flight — skipped.');
          continue;
        }

        // Re-check live status from Hive.
        final live = schedules.firstWhere(
          (s) => s.id == schedule.id,
          orElse: () => schedule,
        );
        if (live.status != ScheduleStatus.pending || !live.isActive) {
          AppLogger.info(_tag, 'processDueSchedules: schedule ${schedule.id} is ${live.status} — skipped.');
          continue;
        }

        _inFlightScheduleIds.add(schedule.id);
        try {
          // Check whether a session for this schedule ALREADY exists in Hive
          // (written by the other isolate). sessionForSchedule() checks the
          // Hive box on disk — cross-isolate safe.
          final existingSession = sessionStore.sessionForSchedule(schedule.id);

          if (_isHeadless) {
            // ── HEADLESS PATH ──────────────────────────────────────────────
            // Headless isolate is the sole authority for Dart-side sending.
            // However, the Kotlin native path (SmsForegroundService) may have
            // already claimed or sent this schedule via NativeScheduleStore.
            // We must check + atomically claim it before creating a session.

            if (existingSession != null) {
              // UI isolate beat us to it — just mark as sent without re-sending.
              AppLogger.info(_tag,
                'processDueSchedules [headless]: session ${existingSession.id} already '
                'exists for schedule ${schedule.id} — skipping send, only marking sent.');
            } else {
              // ── Native dedup gate ─────────────────────────────────────────
              // Check whether the Kotlin native path has already sent or claimed
              // this schedule in SQLite (status='sent'|'processing'|'failed').
              // If so, skip sending — the native path already owns this message.
              String? nativeStatus;
              try {
                nativeStatus = await SmsGatewayService.getNativeScheduleStatus(schedule.id);
              } on MissingPluginException {
                nativeStatus = null; // channel not available in this context
              } catch (_) {
                nativeStatus = null;
              }

              if (nativeStatus == 'sent' || nativeStatus == 'failed') {
                // Native path already finished — just sync Hive state and move on.
                AppLogger.info(_tag,
                  'processDueSchedules [headless]: native status=$nativeStatus for '
                  '${schedule.id} — skipping Dart send, updating Hive only.');
              } else if (nativeStatus == 'processing') {
                // Native path is mid-send right now — do not interfere.
                AppLogger.info(_tag,
                  'processDueSchedules [headless]: native is processing ${schedule.id} '
                  '— skipping Dart send to avoid duplicate.');
                _inFlightScheduleIds.remove(schedule.id);
                continue;
              } else {
                // Native status is 'pending' or null (not in native store at all).
                // Try to atomically claim it so the native path cannot also send.
                bool claimed = true;
                if (nativeStatus == 'pending') {
                  try {
                    claimed = await SmsGatewayService.claimNativeSchedule(schedule.id);
                  } on MissingPluginException {
                    claimed = true; // channel not available — proceed as sole sender
                  } catch (_) {
                    claimed = true;
                  }
                }

                if (!claimed) {
                  // Another path (native Kotlin) beat us to the claim — skip.
                  AppLogger.info(_tag,
                    'processDueSchedules [headless]: native claimed ${schedule.id} '
                    'before us — skipping Dart send.');
                  _inFlightScheduleIds.remove(schedule.id);
                  continue;
                }

                // We hold the exclusive claim — proceed to create session and send.
                final recipients = await _buildRecipients(schedule.recipientIds);
                if (recipients.isEmpty) {
                  await markAsFailed(schedule, reason: 'No valid recipients found');
                  continue;
                }
                await sessionStore.startSessionWithRecipients(
                  message: schedule.message,
                  simSlot: schedule.simSlot,
                  simLabel: schedule.simLabel,
                  recipients: recipients,
                  scheduleId: schedule.id,
                );
              }
            }
            await markAsSent(schedule);

          } else {
            // ── UI PATH ───────────────────────────────────────────────────
            // UI isolate NEVER creates sessions for scheduled sends.
            // It only marks as sent after the headless session is done.
            if (existingSession != null && existingSession.isComplete) {
              AppLogger.info(_tag,
                'processDueSchedules [UI]: headless session ${existingSession.id} complete '
                '— marking schedule ${schedule.id} as sent.');
              await markAsSent(schedule);
            } else if (existingSession != null) {
              AppLogger.info(_tag,
                'processDueSchedules [UI]: headless session ${existingSession.id} still '
                'in-progress for schedule ${schedule.id} — no action from UI.');
            } else {
              // No session at all yet — headless will handle it when the alarm fires.
              AppLogger.info(_tag,
                'processDueSchedules [UI]: no session yet for schedule ${schedule.id} '
                '— headless will send when alarm fires. No action from UI.');
            }
          }
        } catch (e) {
          if (_isHeadless) {
            await markAsFailed(schedule, reason: e.toString());
          }
        } finally {
          _inFlightScheduleIds.remove(schedule.id);
        }
      }

      await _autoDeleteExpired();
      await _scheduleNextAlarm();
    } finally {
      _isProcessingDue = false;
    }
  }

  Future<List<SmsRecipient>> _buildRecipients(List<String> recipientIds) async {
    final contactBox = Hive.box<Contact>('contacts');
    final List<SmsRecipient> result = [];
    // Guard against contacts that share the same name (e.g. same person
    // stored twice with different phone numbers). One SMS per unique name.
    final seenNames = <String>{};

    for (final id in recipientIds) {
      Contact? contact;

      for (final c in contactBox.values) {
        if (c.studentId != null && c.studentId.toString() == id) {
          contact = c;
          break;
        }
      }

      if (contact == null) {
        final index = contactBox.keys
            .toList()
            .indexWhere((key) => key.toString() == id);
        if (index != -1) {
          contact = contactBox.getAt(index);
        }
      }

      if (contact != null && contact.phones.isNotEmpty) {
        final normalizedName = contact.name.trim().toLowerCase();
        if (seenNames.contains(normalizedName)) {
          AppLogger.info(_tag,
            '_buildRecipients: skipping duplicate name "${contact.name}" — '
            'first number already added for this contact.');
          continue;
        }
        seenNames.add(normalizedName);
        result.add(SmsRecipient(
          name: contact.name,
          phone: contact.phones[0],
        ));
      }
    }
    return result;
  }
}