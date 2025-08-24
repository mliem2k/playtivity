import 'dart:math';
import '../services/app_logger.dart';

class ApiRetryService {
  static Future<T> retryApiCall<T>(
    Future<T> Function() apiCall, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 50),
    String operation = 'API call',
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final result = await apiCall();
        if (attempt > 0) {
          AppLogger.info('$operation succeeded after ${attempt + 1} attempts');
        }
        return result;
      } catch (e) {
        if (attempt == maxRetries) {
          AppLogger.error('$operation failed after ${maxRetries + 1} attempts', e);
          rethrow;
        }
        
        final delay = Duration(
          milliseconds: initialDelay.inMilliseconds * pow(2, attempt).toInt(),
        );
        
        AppLogger.warning('$operation attempt ${attempt + 1} failed, retrying in ${delay.inMilliseconds}ms: $e');
        await Future.delayed(delay);
      }
    }
    
    throw Exception('Retry logic should not reach this point');
  }
}