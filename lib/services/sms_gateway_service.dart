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

  static Future<bool> checkPermissions() async => await _channel.invokeMethod<bool>('checkSmsPermissions') ?? false;

  static Future<bool> requestPermissions() async => await _channel.invokeMethod<bool>('requestSmsPermissions') ?? false;

  static Future<List<SimCard>> getSimCards() async {
    final raw = await _channel.invokeListMethod('getSimCards');
    if (raw == null) return [];
    return raw.map((e) => SimCard.fromMap(e as Map<Object?, Object?>)).toList();
  }

  static Future<SmsResult> sendSms({required String to, required String message, int simSlot = -1}) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('sendSms', {'to': to, 'message': message, 'simSlot': simSlot});
    if (result == null) throw PlatformException(code: 'NULL_RESULT', message: 'sendSms returned null');
    return SmsResult.fromMap(result);
  }

  static Future<SmsResult> getSmsStatus(String msgId) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getSmsStatus', {'msgId': msgId});
    if (result == null) throw PlatformException(code: 'NULL_RESULT', message: 'getSmsStatus returned null');
    return SmsResult.fromMap(result);
  }

  static Future<void> startForegroundService() async => await _channel.invokeMethod('startForegroundService');

  static Future<void> stopForegroundService() async => await _channel.invokeMethod('stopForegroundService');
}