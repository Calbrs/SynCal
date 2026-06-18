import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../root/models/scheduled_message.dart';
import 'app_logger.dart';

const String _tag = 'ScheduledMessageStore';
const String _scheduleBoxName = 'scheduled_messages';

class ScheduledMessageStore extends ChangeNotifier {
  static final ScheduledMessageStore _instance = ScheduledMessageStore._();
  factory ScheduledMessageStore() => _instance;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  final List<ScheduledMessage> schedules = [];

  ScheduledMessageStore._() {
    _initHive();
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
    } catch (e) {
      AppLogger.error(_tag, 'Failed to load schedules: $e');
      _isLoaded = true;
      notifyListeners();
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

  Future<void> addSchedule(ScheduledMessage schedule) async {
    schedules.add(schedule);
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Added schedule: ${schedule.id}');
  }

  Future<void> updateSchedule(ScheduledMessage updated) async {
    final index = schedules.indexWhere((s) => s.id == updated.id);
    if (index != -1) {
      schedules[index] = updated;
      await _saveSchedules();
      notifyListeners();
      AppLogger.info(_tag, 'Updated schedule: ${updated.id}');
    }
  }

  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((s) => s.id == id);
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Deleted schedule: $id');
  }

  Future<void> toggleActive(String id) async {
    final schedule = schedules.firstWhere((s) => s.id == id);
    schedule.isActive = !schedule.isActive;
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Toggled active for schedule: $id');
  }

  /// Returns schedules that are due for sending (scheduled time <= now and active).
  List<ScheduledMessage> getDueSchedules() {
    final now = DateTime.now();
    return schedules.where((s) =>
        s.isActive && (s.scheduledTime.isBefore(now) || s.scheduledTime.isAtSameMomentAs(now))
    ).toList();
  }

  /// Called after sending a scheduled message to update next occurrence.
  Future<void> markAsSent(ScheduledMessage schedule) async {
    final index = schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;

    if (schedule.repetition == Repetition.none) {
      // One‑off: deactivate after sending.
      final updated = schedule.copyWith(
        isActive: false,
      );
      schedules[index] = updated;
    } else {
      // For repeating: set next time.
      final nextTime = schedule.nextOccurrence(DateTime.now());
      final updated = schedule.copyWith(
        scheduledTime: nextTime,
        sentCount: (schedule.sentCount ?? 0) + 1,
      );
      schedules[index] = updated;
    }
    
    await _saveSchedules();
    notifyListeners();
    AppLogger.info(_tag, 'Marked schedule as sent: ${schedule.id}');
  }

  /// Get a schedule by ID
  ScheduledMessage? getSchedule(String id) {
    try {
      return schedules.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}