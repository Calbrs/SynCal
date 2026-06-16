import 'dart:async';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

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
      slotIndex:      (map['slotIndex']      as int?) ?? 0,
      subscriptionId: (map['subscriptionId'] as int?) ?? -1,
      displayName:    (map['displayName']    as String?) ?? 'SIM',
      carrierName:    (map['carrierName']    as String?) ?? 'Unknown',
      number:         (map['number']         as String?) ?? '',
      simSlotIndex:   (map['simSlotIndex']   as int?) ?? 0,
      countryIso:     (map['countryIso']     as String?) ?? '',
    );
  }

  @override
  String toString() => '$displayName ($carrierName)';
}

class SmsResult {
  /// Unique message ID assigned by the native layer.
  final String msgId;

  /// 'queued' immediately after calling sendSms.
  /// Updates to true/false once the sent broadcast fires.
  final bool? sent;

  /// true once delivery receipt arrives (may never arrive for some carriers).
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
      msgId:         (map['msgId']         as String?) ?? '',
      sent:          map['sent']           as bool?,
      delivered:     map['delivered']      as bool?,
      sentError:     map['sentError']      as String?,
      deliveryError: map['deliveryError']  as String?,
    );
  }

  bool get isSuccess => sent == true;
  bool get isPending => sent == null;
  bool get isFailed  => sent == false;

  @override
  String toString() =>
      'SmsResult(id=$msgId, sent=$sent, delivered=$delivered, '
      'sentErr=$sentError, delivErr=$deliveryError)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class SmsGatewayService {
  static const _channel = MethodChannel('com.example.synccal/sms');

  /// Stream of status updates pushed from the native delivery receiver.
  /// Listen to this in your UI to get real-time delivered confirmations.
  static Stream<SmsResult> get statusUpdates => _statusController.stream;
  static final _statusController =
      StreamController<SmsResult>.broadcast();

  static bool _listenerRegistered = false;

  /// Call once during app startup (e.g. in main() or initState of root widget).
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

  // ── Permissions ────────────────────────────────────────────────────────────

  /// Returns true if SMS permissions are already granted.
  static Future<bool> checkPermissions() async {
    return await _channel.invokeMethod<bool>('checkSmsPermissions') ?? false;
  }

  /// Shows the system permission dialog if needed.
  /// Returns true when all required permissions are granted.
  static Future<bool> requestPermissions() async {
    return await _channel.invokeMethod<bool>('requestSmsPermissions') ?? false;
  }

  // ── SIM cards ──────────────────────────────────────────────────────────────

  /// Returns the list of active SIM cards on the device.
  /// Empty list if only one SIM or READ_PHONE_STATE not granted.
  static Future<List<SimCard>> getSimCards() async {
    final raw = await _channel.invokeListMethod('getSimCards');
    if (raw == null) return [];
    return raw
        .map((e) => SimCard.fromMap(e as Map<Object?, Object?>))
        .toList();
  }

  // ── Send SMS ───────────────────────────────────────────────────────────────

  /// Sends an SMS to [to] with [message].
  ///
  /// [simSlot] is the 0-based index from [getSimCards].
  /// Pass -1 (default) to let the OS choose the default SIM.
  ///
  /// Returns a [SmsResult] with the assigned [msgId] and initial status.
  /// Subscribe to [statusUpdates] for delivery confirmation.
  static Future<SmsResult> sendSms({
    required String to,
    required String message,
    int simSlot = -1,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('sendSms', {
      'to':      to,
      'message': message,
      'simSlot': simSlot,
    });
    if (result == null) {
      throw PlatformException(code: 'NULL_RESULT', message: 'sendSms returned null');
    }
    return SmsResult.fromMap(result);
  }

  // ── Status polling ─────────────────────────────────────────────────────────

  /// Polls the current status of a previously sent message.
  static Future<SmsResult> getSmsStatus(String msgId) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getSmsStatus', {'msgId': msgId});
    if (result == null) {
      throw PlatformException(code: 'NULL_RESULT', message: 'getSmsStatus returned null');
    }
    return SmsResult.fromMap(result);
  }

  /// Dispose when no longer needed (e.g. app shutdown).
  static void dispose() {
    _statusController.close();
  }
}