import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'root/models/contact.dart';
import 'root/models/sms_session.dart';
import 'root/app_routes.dart';
import 'services/app_logger.dart';
import 'services/sms_gateway_service.dart';
import 'services/sms_session_store.dart';
import 'core/api_config.dart';

const String appTitle = 'SynCal';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  // Register adapters
  Hive.registerAdapter(ContactAdapter());
  Hive.registerAdapter(SmsRecipientStatusAdapter());
  Hive.registerAdapter(SmsRecipientAdapter());
  Hive.registerAdapter(SmsSessionStateAdapter());
  Hive.registerAdapter(SmsSessionAdapter());

  // Open boxes
  await Hive.openBox<dynamic>(ApiConfig.syncalBoxKey);
  await Hive.openBox<Contact>('contacts');
  await Hive.openBox<SmsSession>('sms_sessions');

  // Open a settings box for authentication state
  await Hive.openBox('settings');

  await AppLogger.init();
  SmsGatewayService.init();

  AppLogger.info('main', 'App starting');

  runApp(
    ChangeNotifierProvider(
      create: (_) => SmsSessionStore(),
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