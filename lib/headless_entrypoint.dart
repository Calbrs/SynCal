import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'root/models/contact.dart';
import 'root/models/sms_session.dart';
import 'root/models/scheduled_message.dart';
import 'services/app_logger.dart';
import 'services/sms_gateway_service.dart';
import 'services/sms_session_store.dart';
import 'services/scheduled_message_store.dart';

const String _tag = 'HeadlessEntrypoint';
const String _headlessChannel = 'com.example.SynCal/headless';

/// Entry point invoked by ScheduleAlarmReceiver.kt inside a short-lived
/// headless FlutterEngine. This isolate has NO UI, no Activity, and does not
/// depend on MainActivity or the cached UI engine being alive — it works
/// even if the app was swiped away from recents or the device just rebooted.
///
/// CRITICAL: Every adapter registered in main.dart MUST also be registered
/// here. The headless isolate reads the same Hive binary files — any typeId
/// present in those files that is not registered here causes:
///   HiveError: Cannot read, unknown typeId: X
///
/// TypeId map (must match @HiveType annotations in model files):
///   ContactAdapter          → typeId: 0    (contact.dart)
///   SmsRecipientStatus      → typeId: 101  (sms_session.dart)
///   SmsRecipient            → typeId: 102  (sms_session.dart)
///   SmsSessionState         → typeId: 103  (sms_session.dart)
///   SmsSession              → typeId: 104  (sms_session.dart)
///   Repetition              → typeId: 105  (scheduled_message.dart)
///   ScheduleStatus          → typeId: 106  (scheduled_message.dart)
///   ScheduledMessage        → typeId: 107  (scheduled_message.dart)
@pragma('vm:entry-point')
Future<void> scheduledMessageCallbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();

  final channel = MethodChannel(_headlessChannel);

  try {
    await Hive.initFlutter();

    // Safe helper: registers adapter only if its typeId is not yet registered.
    // Uses adapter.typeId (from the @HiveType annotation) — never a hardcoded
    // integer — so this stays correct even if typeIds change in the model.
    void registerIfAbsent<T>(TypeAdapter<T> adapter) {
      if (!Hive.isAdapterRegistered(adapter.typeId)) {
        Hive.registerAdapter(adapter);
      }
    }

    // Must be the exact same set and order as main.dart
    registerIfAbsent(ContactAdapter());           // typeId: 0
    registerIfAbsent(SmsRecipientStatusAdapter()); // typeId: 101
    registerIfAbsent(SmsRecipientAdapter());       // typeId: 102
    registerIfAbsent(SmsSessionStateAdapter());    // typeId: 103
    registerIfAbsent(SmsSessionAdapter());         // typeId: 104
    registerIfAbsent(RepetitionAdapter());         // typeId: 105
    registerIfAbsent(ScheduleStatusAdapter());     // typeId: 106
    registerIfAbsent(ScheduledMessageAdapter());   // typeId: 107

    // Open boxes — same names as main.dart (no ApiConfig.syncalBoxKey or
    // 'settings' box needed here; headless only needs these three)
    await Hive.openBox<Contact>('contacts');
    await Hive.openBox<SmsSession>('sms_sessions');
    await Hive.openBox<ScheduledMessage>('scheduled_messages');

    await AppLogger.init();
    SmsGatewayService.init();

    AppLogger.info(_tag, 'Headless task started');

    final messageStore = ScheduledMessageStore();
    final sessionStore = SmsSessionStore();

    await messageStore.awaitLoaded();
    await sessionStore.awaitLoaded();

    await messageStore.processDueSchedules();

    AppLogger.info(_tag, 'Headless task finished processing due schedules');
  } catch (e, st) {
    AppLogger.error(_tag, 'Headless task failed: $e\n$st');
  } finally {
    try {
      await channel.invokeMethod('headlessTaskComplete');
    } catch (e) {
      AppLogger.error(_tag, 'Failed to signal completion to native side: $e');
      // Native side has a watchdog timeout as fallback if this call fails.
    }
  }
}