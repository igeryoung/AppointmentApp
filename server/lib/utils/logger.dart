import 'dart:convert';

/// Centralized logging utility for the application
/// Provides consistent, colorful, and structured logging across all components
class Logger {
  final String component;

  Logger(this.component);

  /// Log levels
  static const String _info = '📘';
  static const String _success = '✅';
  static const String _warning = '⚠️';
  static const String _error = '❌';
  static const String _debug = '🔍';

  /// ANSI color codes
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _blue = '\x1B[34m';
  static const String _gray = '\x1B[90m';

  String _timestamp() => DateTime.now().toIso8601String();

  void info(String message, {Map<String, dynamic>? data}) {
    print('$_blue$_info [$component] $_reset$message');
    if (data != null) _printData(data);
  }

  void success(String message, {Map<String, dynamic>? data}) {
    print('$_green$_success [$component] $_reset$message');
    if (data != null) _printData(data);
  }

  void warning(String message, {Map<String, dynamic>? data}) {
    print('$_yellow$_warning [$component] $_reset$message');
    if (data != null) _printData(data);
  }

  void error(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    print('$_red$_error [$component] $_reset$message');
    if (error != null) {
      print('$_gray   Error: $error$_reset');
    }
    if (data != null) _printData(data);
    if (stackTrace != null) {
      print('$_gray   Stack trace:$_reset');
      final lines = stackTrace.toString().split('\n');
      for (var i = 0; i < lines.length && i < 10; i++) {
        print('$_gray   ${lines[i]}$_reset');
      }
    }
  }

  void debug(String message, {Map<String, dynamic>? data}) {
    print('$_gray$_debug [$component] $message$_reset');
    if (data != null) _printData(data);
  }

  void _printData(Map<String, dynamic> data) {
    try {
      final encoder = JsonEncoder.withIndent('  ');
      final jsonStr = encoder.convert(data);
      print('$_gray   Data: $jsonStr$_reset');
    } catch (e) {
      print('$_gray   Data: $data$_reset');
    }
  }

  /// Create a request logger with request context
  RequestLogger request(String method, String path) {
    return RequestLogger(this, method, path);
  }
}

/// Request-specific logger for tracking HTTP requests
class RequestLogger {
  final Logger _logger;
  final String method;
  final String path;
  final DateTime _startTime;

  RequestLogger(this._logger, this.method, this.path) : _startTime = DateTime.now();

  void start({Map<String, dynamic>? params}) {
    _logger.debug('$method $path - Started', data: params);
  }

  void complete(int statusCode, {Map<String, dynamic>? data}) {
    final duration = DateTime.now().difference(_startTime);
    final emoji = statusCode >= 200 && statusCode < 300 ? '✅' : '❌';
    _logger.info(
      '$emoji $method $path - $statusCode (${duration.inMilliseconds}ms)',
      data: data,
    );
  }

  void fail(Object error, {StackTrace? stackTrace}) {
    final duration = DateTime.now().difference(_startTime);
    _logger.error(
      '❌ $method $path - Failed (${duration.inMilliseconds}ms)',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
