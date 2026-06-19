import 'package:hive/hive.dart';

part 'scheduled_message.g.dart';

@HiveType(typeId: 105)
enum Repetition {
  @HiveField(0) none,
  @HiveField(1) daily,
  @HiveField(2) weekly,
  @HiveField(3) monthly,
}

@HiveType(typeId: 106)
enum ScheduleStatus {
  @HiveField(0) pending,
  @HiveField(1) sent,
  @HiveField(2) failed,
}

@HiveType(typeId: 107)
class ScheduledMessage extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String message;
  @HiveField(2)
  DateTime scheduledTime;
  @HiveField(3)
  final Repetition repetition;
  @HiveField(4)
  final List<String> recipientIds;
  @HiveField(5)
  final int simSlot;
  @HiveField(6)
  final String simLabel;
  @HiveField(7)
  bool isActive;
  @HiveField(8)
  final DateTime createdAt;
  @HiveField(9)
  int? sentCount;
  @HiveField(10)
  ScheduleStatus status;           // pending, sent, failed
  @HiveField(11)
  DateTime? completedAt;           // when it was sent or failed

  ScheduledMessage({
    required this.id,
    required this.message,
    required this.scheduledTime,
    this.repetition = Repetition.none,
    required this.recipientIds,
    required this.simSlot,
    required this.simLabel,
    this.isActive = true,
    required this.createdAt,
    this.sentCount,
    this.status = ScheduleStatus.pending,
    this.completedAt,
  });

  DateTime nextOccurrence(DateTime from) {
    switch (repetition) {
      case Repetition.none:
        return scheduledTime;
      case Repetition.daily:
        return from.add(const Duration(days: 1));
      case Repetition.weekly:
        return from.add(const Duration(days: 7));
      case Repetition.monthly:
        return DateTime(from.year, from.month + 1, from.day, from.hour, from.minute);
    }
  }

  bool get isComplete {
    if (repetition == Repetition.none) {
      return status != ScheduleStatus.pending;
    }
    return false;
  }

  /// Auto‑delete after 24 hours from scheduled time (for one‑off) or from completion?
  bool get shouldAutoDelete {
    if (repetition != Repetition.none) return false; // only one‑off
    if (status == ScheduleStatus.pending) return false;
    final endTime = completedAt ?? scheduledTime;
    return DateTime.now().difference(endTime) > const Duration(hours: 24);
  }

  ScheduledMessage copyWith({
    String? id,
    String? message,
    DateTime? scheduledTime,
    Repetition? repetition,
    List<String>? recipientIds,
    int? simSlot,
    String? simLabel,
    bool? isActive,
    DateTime? createdAt,
    int? sentCount,
    ScheduleStatus? status,
    DateTime? completedAt,
  }) {
    return ScheduledMessage(
      id: id ?? this.id,
      message: message ?? this.message,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      repetition: repetition ?? this.repetition,
      recipientIds: recipientIds ?? this.recipientIds,
      simSlot: simSlot ?? this.simSlot,
      simLabel: simLabel ?? this.simLabel,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      sentCount: sentCount ?? this.sentCount,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}