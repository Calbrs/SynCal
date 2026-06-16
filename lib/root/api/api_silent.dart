import 'dart:developer';

import 'api_config.dart';

class ApiSilent {
  ApiSilent._();

  static Future<void> sendHeartbeat() async {
    // This is a non-blocking placeholder for silent background requests.
    log('Sending silent heartbeat to ${ApiConfig.baseUrl}');
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
