import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../root/models/contact.dart';
import '../root/models/scheduled_message.dart';
import '../root/models/sms_session.dart';
import 'app_logger.dart';
import 'sms_session_store.dart';
import 'background_service.dart';

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

  /// Schedules the next native alarm. Safe to call from both the UI isolate
  /// and the headless isolate — MissingPluginException is caught and ignored
  /// silently in the headless context where no MethodChannel handler is
  /// registered (the headless engine has no MainActivity backing it).
  Future<void> _scheduleNextAlarm() async {
    final pendingActive = schedules.where(
      (s) => s.isActive && s.status == ScheduleStatus.pending,
    ).toList();

    try {
      if (pendingActive.isEmpty) {
        await BackgroundService.cancelAlarm();
        return;
      }
      pendingActive.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      final next = pendingActive.first.scheduledTime;
      await BackgroundService.scheduleAt(next);
    } on MissingPluginException {
      // Running inside a headless FlutterEngine — MethodChannel handlers
      // are not registered here. This is expected and safe to ignore;
      // the alarm was already set by the UI isolate before the app was killed,
      // and the headless task itself was triggered by that alarm.
      AppLogger.info(
        _tag,
        '_scheduleNextAlarm: skipped in headless context (MissingPluginException — expected).',
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
    await _scheduleNextAlarm();
  }

  Future<void> updateSchedule(ScheduledMessage updated) async {
    final index = schedules.indexWhere((s) => s.id == updated.id);
    if (index != -1) {
      schedules[index] = updated;
      await _saveSchedules();
      notifyListeners();
      AppLogger.info(_tag, 'Updated schedule: ${updated.id}');
      await _scheduleNextAlarm();
    }
  }

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((s) => s.id == id);
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Deleted schedule: $id');
    await _scheduleNextAlarm();
  }

  Future<void> toggleActive(String id) async {
    final schedule = schedules.firstWhere((s) => s.id == id);
    schedule.isActive = !schedule.isActive;
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Toggled active for schedule: $id');
    await _scheduleNextAlarm();
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

  /// Called by the UI (manual refresh), by the headless alarm entrypoint,
  /// and by the foreground Dart timer fallback.
  ///
  /// FIX (Tatizo 1 & 2): Before starting a new session or calling markAsSent,
  /// we now:
  ///   1. Re-read the schedule's current status from the in-memory list
  ///      (which was reloaded from Hive at startup). If status is no longer
  ///      `pending` the other isolate already processed it — skip entirely.
  ///   2. Acquire a per-schedule-ID in-flight lock so that if both isolates
  ///      reach this point simultaneously, only one proceeds.
  ///   3. Pass the `scheduleId` to `startSessionWithRecipients` so that
  ///      SmsSessionStore can detect and skip duplicate sessions for the same
  ///      schedule ID (see SmsSessionStore fix).
  Future<void> processDueSchedules() async {
    if (_isProcessingDue) return;
    _isProcessingDue = true;
    try {
      // Re-open box in case we are in the headless isolate and it wasn't open
      // yet (openBox is a no-op if already open).
      await Hive.openBox<ScheduledMessage>(_scheduleBoxName);

      // Reload schedules from Hive so we see changes made by the other isolate
      // (e.g. UI isolate already marked a schedule as `sent` between the alarm
      // firing and this code running).
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

      AppLogger.info(_tag, 'Processing ${due.length} due schedules');

      final sessionStore = SmsSessionStore();
      await sessionStore.awaitLoaded();

      for (final schedule in due) {
        // --- Per-schedule duplicate guard ---
        // If another isolate is already handling this schedule ID, skip it.
        if (_inFlightScheduleIds.contains(schedule.id)) {
          AppLogger.info(
            _tag,
            'processDueSchedules: schedule ${schedule.id} already in-flight — skipped.',
          );
          continue;
        }

        // Re-check live status from the in-memory list (already reloaded above).
        // If the other isolate finished and saved `sent` to Hive between our
        // reload and this loop iteration, the status won't be `pending` anymore.
        final live = schedules.firstWhere(
          (s) => s.id == schedule.id,
          orElse: () => schedule,
        );
        if (live.status != ScheduleStatus.pending || !live.isActive) {
          AppLogger.info(
            _tag,
            'processDueSchedules: schedule ${schedule.id} is ${live.status} — skipped (already handled).',
          );
          continue;
        }

        _inFlightScheduleIds.add(schedule.id);
        try {
          // FIX (Tatizo 1): Check whether SmsSessionStore already has a
          // session for this schedule (created by the other isolate). If so,
          // only call markAsSent — do NOT create a duplicate session.
          final existingSession = sessionStore.sessionForSchedule(schedule.id);

          if (existingSession == null) {
            final recipients = await _buildRecipients(schedule.recipientIds);
            if (recipients.isEmpty) {
              await markAsFailed(schedule, reason: 'No valid recipients found');
              continue;
            }

            // Pass scheduleId so SmsSessionStore can deduplicate on its side.
            await sessionStore.startSessionWithRecipients(
              message: schedule.message,
              simSlot: schedule.simSlot,
              simLabel: schedule.simLabel,
              recipients: recipients,
              scheduleId: schedule.id,
            );
          } else {
            AppLogger.info(
              _tag,
              'processDueSchedules: session ${existingSession.id} already exists '
              'for schedule ${schedule.id} — skipping startSessionWithRecipients.',
            );
          }

          await markAsSent(schedule);
        } catch (e) {
          await markAsFailed(schedule, reason: e.toString());
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
        result.add(SmsRecipient(
          name: contact.name,
          phone: contact.phones[0],
        ));
      }
    }
    return result;
  }
}