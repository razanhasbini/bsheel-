import 'dart:developer' as dev;

/// Simple app logger wrapping dart:developer.
class AppLogger {
  static void info(String message) => dev.log(message, name: 'INFO');
  static void warning(String message) => dev.log(message, name: 'WARNING');
  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      dev.log(message, name: 'ERROR', error: error, stackTrace: stackTrace);
}
