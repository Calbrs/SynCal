import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import '../root/models/contact.dart';
import '../root/models/sms_session.dart';
import '../root/models/scheduled_message.dart';
import 'app_logger.dart';
import 'scheduled_message_store.dart';
import 'sms_gateway_service.dart';

const String _tag = 'BackgroundService';
const String backgroundTaskName = 'syncScheduledMessages';
const String oneOffTaskName = 'syncOneOffScheduledMessages';

/// Workmanager callback — runs in a SEPARATE isolate with NO access to the
/// main isolate's singletons. We therefore boot Hive ourselves (same pattern
/// as the headless AlarmManager entrypoint) and process due schedules
/// directly.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundTaskName && task != oneOffTaskName) return false;

    AppLogger.info(_tag, 'Workmanager safety-net fired — processing due schedules.');

    try {
      await Hive.initFlutter();

      // Register all adapters (same set as main.dart and headless_entrypoint.dart)
      void registerIfAbsent<T>(TypeAdapter<T> adapter) {
        if (!Hive.isAdapterRegistered(adapter.typeId)) {
          Hive.registerAdapter(adapter);
        }
      }

      registerIfAbsent(ContactAdapter());
      registerIfAbsent(SmsRecipientStatusAdapter());
      registerIfAbsent(SmsRecipientAdapter());
      registerIfAbsent(SmsSessionStateAdapter());
      registerIfAbsent(SmsSessionAdapter());
      registerIfAbsent(RepetitionAdapter());
      registerIfAbsent(ScheduleStatusAdapter());
      registerIfAbsent(ScheduledMessageAdapter());

      await Hive.openBox<Contact>('contacts');
      await Hive.openBox<SmsSession>('sms_sessions');
      await Hive.openBox<ScheduledMessage>('scheduled_messages');

      SmsGatewayService.init();

      final store = ScheduledMessageStore();
      await store.awaitLoaded();
      await store.processDueSchedules();

      AppLogger.info(_tag, 'Workmanager safety-net finished processing.');
      return true;
    } catch (e) {
      AppLogger.error(_tag, 'Workmanager safety-net error: $e');
      return false;
    }
  });
}

class BackgroundService {
  static Timer? _pollTimer;
  static bool _isPolling = false;

  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundTaskName,
      backgroundTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
      ),
    );
    AppLogger.info(_tag, 'Workmanager safety-net initialized (15 min minimum interval).');

    _startMainIsolatePolling();

    // Process anything already due on cold start / resume after task-kill.
    unawaited(processNow());
  }

  /// Convenience polling while the UI isolate is alive. Not relied on for
  /// correctness — AlarmManager + headless engine is the primary path.
  static void _startMainIsolatePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(processNow());
    });
    AppLogger.info(_tag, 'Foreground convenience polling started (every 60s, UI-isolate only).');
  }

  /// Registers a native AlarmManager wake-up for [scheduledTime].
  /// Primary delivery path — schedules a one-off WorkManager task to run when due.
  static Future<void> scheduleAt(DateTime scheduledTime) async {
    final delay = scheduledTime.difference(DateTime.now());
    final delayDuration = delay.isNegative ? Duration.zero : delay;
    try {
      await Workmanager().registerOneOffTask(
        oneOffTaskName,
        oneOffTaskName,
        initialDelay: delayDuration,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresBatteryNotLow: false,
        ),
        outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
      AppLogger.info(_tag, 'Workmanager one-off task registered for $scheduledTime (delay: $delayDuration)');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to schedule Workmanager one-off task: $e');
    }
  }

  static Future<void> cancelAlarm() async {
    try {
      await Workmanager().cancelByUniqueName(oneOffTaskName);
      AppLogger.info(_tag, 'Workmanager one-off task cancelled');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to cancel Workmanager one-off task: $e');
    }
  }

  /// Safe to call repeatedly/concurrently — guarded against overlapping runs.
  static Future<void> processNow() async {
    if (_isPolling) return;
    _isPolling = true;
    try {
      await ScheduledMessageStore().processDueSchedules();
    } catch (e) {
      AppLogger.error(_tag, 'processNow failed: $e');
    } finally {
      _isPolling = false;
    }
  }

  // ---- Permission helpers (called from UI/onboarding) ----

  /// Since we shifted to WorkManager and removed restricted permissions to comply with PlayStore policies,
  /// all checks return true to bypass warning/blocking states, while maintaining support for OEM autostart.
  static Future<BackgroundPermissionStatus> checkPermissions() async {
    return const BackgroundPermissionStatus(
      canScheduleExactAlarms: true,
      isIgnoringBatteryOptimizations: true,
    );
  }

  static void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

/// Snapshot of background-execution permission state (stubbed to bypass PlayStore exact alarm and battery opt check).
class BackgroundPermissionStatus {
  final bool canScheduleExactAlarms;
  final bool isIgnoringBatteryOptimizations;

  const BackgroundPermissionStatus({
    required this.canScheduleExactAlarms,
    required this.isIgnoringBatteryOptimizations,
  });

  /// Always returns true since background scheduling is now exact-alarm-free.
  bool get allGranted => true;

  @override
  String toString() =>
      'BackgroundPermissionStatus(exactAlarm: $canScheduleExactAlarms, '
      'batteryOptimization: $isIgnoringBatteryOptimizations)';
}