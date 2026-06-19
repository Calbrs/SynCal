import 'package:hive/hive.dart';

part 'sms_session.g.dart';

@HiveType(typeId: 101)
enum SmsRecipientStatus {
  @HiveField(0) pending,
  @HiveField(1) sent,
  @HiveField(2) failed,
  @HiveField(3) sentNotDelivered,
}

@HiveType(typeId: 102)
class SmsRecipient extends HiveObject {
  @HiveField(0) final String name;
  @HiveField(1) final String phone;
  @HiveField(2) SmsRecipientStatus status;
  @HiveField(3) String? error;
  @HiveField(4) String? msgId;
  @HiveField(5) int retryCount;
  @HiveField(6) int? deliveryRetryCount;

  SmsRecipient({
    required this.name,
    required this.phone,
    this.status = SmsRecipientStatus.pending,
    this.error,
    this.msgId,
    this.retryCount = 0,
    this.deliveryRetryCount = 0,
  });
}

@HiveType(typeId: 103)
enum SmsSessionState {
  @HiveField(0) running,
  @HiveField(1) retrying,
  @HiveField(2) done,
}

@HiveType(typeId: 104)
class SmsSession extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) final String message;
  @HiveField(2) final DateTime startedAt;
  @HiveField(3) final int simSlot;
  @HiveField(4) final String simLabel;
  @HiveField(5) final List<SmsRecipient> recipients;
  @HiveField(6) SmsSessionState state;
  @HiveField(7) int retryPass;
  @HiveField(8) DateTime? finishedAt;

  /// ID of the ScheduledMessage that triggered this session.
  /// Null for manual (non-scheduled) sends.
  /// Used by SmsSessionStore.sessionForSchedule() to detect duplicate
  /// sessions when both UI isolate and headless isolate race to create
  /// a session for the same scheduled message.
  @HiveField(9) String? scheduleId;

  static const int maxSendRetries = 3;
  static const int maxDeliveryRetries = 2;
  static int get maxRetries => maxSendRetries;

  SmsSession({
    required this.id,
    required this.message,
    required this.startedAt,
    required this.simSlot,
    required this.simLabel,
    required this.recipients,
    this.state = SmsSessionState.running,
    this.retryPass = 0,
    this.finishedAt,
    this.scheduleId,
  });

  int get totalCount => recipients.length;
  int get sentCount => recipients.where((r) => r.status == SmsRecipientStatus.sent).length;
  int get failedCount => recipients.where((r) => r.status == SmsRecipientStatus.failed).length;
  int get sentButNotDeliveredCount => recipients.where((r) => r.status == SmsRecipientStatus.sentNotDelivered).length;
  int get pendingCount => recipients.where((r) => r.status == SmsRecipientStatus.pending).length;

  List<SmsRecipient> get failedRecipients => recipients.where((r) => r.status == SmsRecipientStatus.failed).toList();

  bool get isComplete => state == SmsSessionState.done;

  double get progressFraction => totalCount == 0 ? 0.0 : (sentCount + failedCount + sentButNotDeliveredCount) / totalCount;
}