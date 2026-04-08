import 'package:flutter/foundation.dart';

/// Log levels in increasing severity.
enum LogLevel { debug, info, warn, error }

/// Simple leveled logger for Hearth.
///
/// Set [level] to control which messages are shown. Messages below the
/// current level are silently dropped. Defaults to [LogLevel.info] in
/// release mode and [LogLevel.debug] in debug mode.
///
/// Usage:
///   Log.d('HA', 'entity parse details...');  // debug — verbose, hidden by default
///   Log.i('HA', 'connected');                 // info — normal operations
///   Log.w('HA', 'reconnecting in 5s');        // warn — recoverable issues
///   Log.e('HA', 'auth failed: $msg');         // error — something broke
class Log {
  static LogLevel level = kReleaseMode ? LogLevel.info : LogLevel.debug;

  static void d(String tag, String message) => _log(LogLevel.debug, tag, message);
  static void i(String tag, String message) => _log(LogLevel.info, tag, message);
  static void w(String tag, String message) => _log(LogLevel.warn, tag, message);
  static void e(String tag, String message) => _log(LogLevel.error, tag, message);

  static void _log(LogLevel msgLevel, String tag, String message) {
    if (msgLevel.index < level.index) return;
    final prefix = switch (msgLevel) {
      LogLevel.debug => 'D',
      LogLevel.info => 'I',
      LogLevel.warn => 'W',
      LogLevel.error => 'E',
    };
    debugPrint('[$prefix/$tag] $message');
  }
}
