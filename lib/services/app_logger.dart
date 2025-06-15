import 'package:logger/logger.dart';

/// Centralized logging service for the application
/// Replaces print() statements with structured logging
class AppLogger {
  static Logger? _logger;
  
  /// Initialize the logger with appropriate configuration
  static Logger get logger {
    _logger ??= Logger(
      filter: ProductionFilter(), // Only show errors/warnings in production
      printer: PrettyPrinter(
        methodCount: 2,        // Number of method calls to be displayed
        errorMethodCount: 8,   // Number of method calls if error/warning occurred
        lineLength: 120,       // Width of the output
        colors: true,          // Colorful log messages
        printEmojis: true,     // Print emoji for each log level
        printTime: false,      // Should each log print contain a timestamp
      ),
      output: ConsoleOutput(),
    );
    return _logger!;
  }
  
  /// Debug level logging - for detailed information during development
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.d(message, error: error, stackTrace: stackTrace);
  }
  
  /// Info level logging - for general information
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.i(message, error: error, stackTrace: stackTrace);
  }
  
  /// Warning level logging - for potentially harmful situations
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.w(message, error: error, stackTrace: stackTrace);
  }
  
  /// Error level logging - for error events
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.e(message, error: error, stackTrace: stackTrace);
  }
  
  /// Fatal level logging - for very severe error events
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.f(message, error: error, stackTrace: stackTrace);
  }
  
  /// Verbose level logging - for extremely detailed information
  static void verbose(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.t(message, error: error, stackTrace: stackTrace);
  }
  
  /// HTTP request/response logging
  static void http(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.d('🌐 HTTP: $message', error: error, stackTrace: stackTrace);
  }
  
  /// Authentication related logging
  static void auth(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.i('🔐 AUTH: $message', error: error, stackTrace: stackTrace);
  }
  
  /// Widget/UI related logging
  static void widget(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.d('📱 WIDGET: $message', error: error, stackTrace: stackTrace);
  }
  
  /// Background service logging
  static void background(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.i('🔄 BACKGROUND: $message', error: error, stackTrace: stackTrace);
  }
  
  /// Spotify API related logging
  static void spotify(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.d('🎵 SPOTIFY: $message', error: error, stackTrace: stackTrace);
  }
}
