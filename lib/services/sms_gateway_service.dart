import 'dart:async';
import 'package:flutter/services.dart';

class SimCard {
  final int slotIndex;
  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final String number;
  final int simSlotIndex;
  final String countryIso;

  const SimCard({
    required this.slotIndex,
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    required this.number,
    required this.simSlotIndex,
    required this.countryIso,
  });

  factory SimCard.fromMap(Map<Object?, Object?> map) {
    return SimCard(
      slotIndex: (map['slotIndex'] as int?) ?? 0,
      subscriptionId: (map['subscriptionId'] as int?) ?? -1,
      displayName: (map['displayName'] as String?) ?? 'SIM',
      carrierName: (map['carrierName'] as String?) ?? 'Unknown',
      number: (map['number'] as String?) ?? '',
      simSlotIndex: (map['simSlotIndex'] as int?) ?? 0,
      countryIso: (map['countryIso'] as String?) ?? '',
    );
  }

  @override
  String toString() => '$displayName ($carrierName)';
}

class SmsResult {
  final String msgId;
  final bool? sent;
  final bool? delivered;
  final String? sentError;
  final String? deliveryError;

  const SmsResult({
    required this.msgId,
    this.sent,
    this.delivered,
    this.sentError,
    this.deliveryError,
  });

  factory SmsResult.fromMap(Map<Object?, Object?> map) {
    return SmsResult(
      msgId: (map['msgId'] as String?) ?? '',
      sent: map['sent'] as bool?,
      delivered: map['delivered'] as bool?,
      sentError: map['sentError'] as String?,
      deliveryError: map['deliveryError'] as String?,
    );
  }
}

class SmsGatewayService {
  static const _channel = MethodChannel('com.example.SynCal/sms');

  static Stream<SmsResult> get statusUpdates => _statusController.stream;
  static final _statusController = StreamController<SmsResult>.broadcast();

  static bool _listenerRegistered = false;

  static void init() {
    if (_listenerRegistered) return;
    _listenerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsStatusUpdate') {
        final map = call.arguments as Map<Object?, Object?>;
        _statusController.add(SmsResult.fromMap(map));
      }
    });
  }

  static Future<bool> checkPermissions() async =>
      await _channel.invokeMethod<bool>('checkSmsPermissions') ?? false;

  static Future<bool> requestPermissions() async =>
      await _channel.invokeMethod<bool>('requestSmsPermissions') ?? false;

  static Future<List<SimCard>> getSimCards() async {
    final raw = await _channel.invokeListMethod('getSimCards');
    if (raw == null) return [];
    return raw.map((e) => SimCard.fromMap(e as Map<Object?, Object?>)).toList();
  }

  static Future<SmsResult> sendSms({
    required String to,
    required String message,
    int simSlot = -1,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'sendSms',
      {'to': to, 'message': message, 'simSlot': simSlot},
    );
    if (result == null) {
      throw PlatformException(code: 'NULL_RESULT', message: 'sendSms returned null');
    }
    return SmsResult.fromMap(result);
  }

  static Future<SmsResult> getSmsStatus(String msgId) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getSmsStatus',
      {'msgId': msgId},
    );
    if (result == null) {
      throw PlatformException(code: 'NULL_RESULT', message: 'getSmsStatus returned null');
    }
    return SmsResult.fromMap(result);
  }

  // ---- Foreground service ----
  static Future<void> startForegroundService() async =>
      await _channel.invokeMethod('startForegroundService');

  static Future<void> stopForegroundService() async =>
      await _channel.invokeMethod('stopForegroundService');

  // ---- Install permission ----
  static Future<bool> canInstallPackages() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  static Future<bool> requestInstallPermission() async =>
      await _channel.invokeMethod<bool>('requestInstallPermission') ?? false;

  static Future<void> installApk(String filePath) async =>
      await _channel.invokeMethod('installApk', {'filePath': filePath});

  // ---- Alarm-based scheduled-message wake-up ----

  /// Schedules (or reschedules) a native AlarmManager wake-up at [triggerAt].
  /// Survives the app being swiped away — backed by AlarmManager + a headless
  /// FlutterEngine, not by anything running inside the UI process.
  static Future<void> scheduleAlarm(DateTime triggerAt) async =>
      await _channel.invokeMethod('scheduleAlarm', {
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
      });

  static Future<void> cancelAlarm() async =>
      await _channel.invokeMethod('cancelAlarm');

  static Future<bool> canScheduleExactAlarms() async =>
      await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? false;

  /// Opens system settings for exact-alarm permission.
  /// Returns immediately — re-check with canScheduleExactAlarms() after resume.
  static Future<void> requestExactAlarmPermission() async =>
      await _channel.invokeMethod('requestExactAlarmPermission');

  /// Persists the Dart callback handle so ScheduleAlarmReceiver.kt can look
  /// it up even when the app process has been killed.
  static Future<void> saveHeadlessCallbackHandle(int handle) async =>
      await _channel.invokeMethod('saveHeadlessCallbackHandle', {'handle': handle});

  // ---- Battery Optimization ----

  /// Returns true if this app is already whitelisted from battery
  /// optimizations (i.e. the OS will not defer or kill background tasks).
  /// On XOS/Transsion devices this is a hard requirement for AlarmManager
  /// to fire reliably when the app has been swiped away.
  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;

  /// Opens the system "Ignore battery optimizations" dialog for this app.
  /// Returns true if already granted, false if the dialog was opened (the
  /// user must tap Allow — re-check with isIgnoringBatteryOptimizations()
  /// after the user returns to the app).
  ///
  /// Requires in AndroidManifest.xml:
  ///   <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
  static Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;

  // ---- OEM Autostart (Transsion XOS / Xiaomi / Huawei / Oppo / Vivo etc.) ----

  /// Attempts to open the OEM-specific "Autostart" settings screen.
  /// This is required on Transsion (Infinix/Tecno/Itel), Xiaomi, Huawei,
  /// Oppo, Vivo and similar devices — without it the OS silently blocks
  /// BroadcastReceivers from starting a new process when the app is not
  /// already running.
  ///
  /// Returns true if a vendor-specific screen was opened, false if only the
  /// generic App Info screen was available as a fallback.
  ///
  /// This cannot be checked programmatically — always show the user a prompt
  /// explaining what to do on the settings screen that opens.
  static Future<bool> openAutostartSettings() async =>
      await _channel.invokeMethod<bool>('openAutostartSettings') ?? false;
}