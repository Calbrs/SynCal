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
  });

  /// Returns the next occurrence time based on repetition.
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

  /// Whether this schedule should be considered "done" (no more repetitions).
  bool get isComplete {
    if (repetition == Repetition.none) {
      return DateTime.now().isAfter(scheduledTime);
    }
    // For repeating, it's never complete; we keep it active until user deactivates.
    return false;
  }

  /// Create a copy of this schedule with updated fields.
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
    );
  }
}