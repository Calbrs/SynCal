// lib/services/app_logger.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static IOSink? _sink;
  static File?   _logFile;
  static bool    _initialised = false;

  // ── Init ────────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    if (_initialised) return;
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final date = _dateStamp(DateTime.now());
      _logFile   = File('${dir.path}/synccal_$date.log');
      _sink      = _logFile!.openWrite(mode: FileMode.append);
      _initialised = true;
      info('AppLogger', 'Log file opened: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[AppLogger] Failed to open log file: $e');
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────
  static void info(String tag, String message)  => _write('INFO ', tag, message);
  static void warn(String tag, String message)  => _write('WARN ', tag, message);
  static void error(String tag, String message) => _write('ERROR', tag, message);

  static Future<String> readLog() async {
    try {
      if (_logFile != null && await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
    } catch (_) {}
    return '';
  }

  static Future<String?> logFilePath() async => _logFile?.path;

  static Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _initialised = false;
  }

  // ── Internal ────────────────────────────────────────────────────────────────
  static void _write(String level, String tag, String message) {
    final line = '[${_ts()}] [$level] [$tag] $message';
    debugPrint(line);
    _sink?.writeln(line);
  }

  static String _ts() {
    final n = DateTime.now();
    return '${n.year}-${_p(n.month)}-${_p(n.day)} '
           '${_p(n.hour)}:${_p(n.minute)}:${_p(n.second)}';
  }

  static String _dateStamp(DateTime d) =>
      '${d.year}${_p(d.month)}${_p(d.day)}';

  static String _p(int v) => v.toString().padLeft(2, '0');
}