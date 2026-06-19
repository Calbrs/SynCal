import 'dart:ui'; // Required for PluginUtilities
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'root/models/contact.dart';
import 'root/models/sms_session.dart';
import 'root/models/scheduled_message.dart';
import 'root/app_routes.dart';
import 'services/app_logger.dart';
import 'services/sms_gateway_service.dart';
import 'services/sms_session_store.dart';
import 'services/scheduled_message_store.dart';
import 'services/background_service.dart';
import 'core/api_config.dart';
import 'headless_entrypoint.dart';

const String appTitle = 'SynCal';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------
  // Hive: initialize and register ALL adapters.
  //
  // RULE: Any adapter registered here MUST also be registered in
  // headless_entrypoint.dart — the headless isolate reads the same
  // binary box files and will crash with "unknown typeId" if any
  // adapter is missing there.
  //
  // TypeId map:
  //   ContactAdapter          → typeId: 0
  //   SmsRecipientStatus      → typeId: 101
  //   SmsRecipient            → typeId: 102
  //   SmsSessionState         → typeId: 103
  //   SmsSession              → typeId: 104
  //   Repetition              → typeId: 105
  //   ScheduleStatus          → typeId: 106
  //   ScheduledMessage        → typeId: 107
  // ---------------------------------------------------------------
  await Hive.initFlutter();

  Hive.registerAdapter(ContactAdapter());           // typeId: 0
  Hive.registerAdapter(SmsRecipientStatusAdapter()); // typeId: 101
  Hive.registerAdapter(SmsRecipientAdapter());       // typeId: 102
  Hive.registerAdapter(SmsSessionStateAdapter());    // typeId: 103
  Hive.registerAdapter(SmsSessionAdapter());         // typeId: 104
  Hive.registerAdapter(RepetitionAdapter());         // typeId: 105
  Hive.registerAdapter(ScheduleStatusAdapter());     // typeId: 106
  Hive.registerAdapter(ScheduledMessageAdapter());   // typeId: 107

  // Open all required Hive boxes
  await Hive.openBox<dynamic>(ApiConfig.syncalBoxKey);
  await Hive.openBox<Contact>('contacts');
  await Hive.openBox<SmsSession>('sms_sessions');
  await Hive.openBox<ScheduledMessage>('scheduled_messages');
  await Hive.openBox('settings');

  // Initialize core services
  await AppLogger.init();
  SmsGatewayService.init();

  // 1. Headless Callback Registration
  // Registers the Dart callback handle for scheduledMessageCallbackDispatcher
  // and persists it natively so AlarmManager can find and invoke it later via
  // a headless FlutterEngine — even after this process has been killed.
  // MUST run every time the app starts (handle can change after hot restart
  // or app update).
  final callbackHandle = PluginUtilities.getCallbackHandle(
    scheduledMessageCallbackDispatcher,
  );
  if (callbackHandle != null) {
    await SmsGatewayService.saveHeadlessCallbackHandle(
      callbackHandle.toRawHandle(),
    );
    AppLogger.info('main', 'Headless callback handle registered.');
  } else {
    AppLogger.error(
      'main',
      'Failed to obtain callback handle for headless dispatcher — '
      'scheduled messages will not survive app kill/reboot until this is fixed.',
    );
  }

  // 2. Foreground Service
  // Keeps the app process alive after being swiped away so the Dart-side
  // timer in BackgroundService can keep firing.
  await SmsGatewayService.startForegroundService();

  // 3. Background Service / Polling
  // Registers the Workmanager safety-net, starts the due-schedule polling
  // loop, and immediately checks for any due schedules.
  await BackgroundService.init();

  AppLogger.info('main', 'App starting');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SmsSessionStore()),
        ChangeNotifierProvider(create: (_) => ScheduledMessageStore()),
      ],
      child: const SynCalApp(),
    ),
  );
}

class SynCalApp extends StatelessWidget {
  const SynCalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: AppRoutes.router,
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
    );
  }
}