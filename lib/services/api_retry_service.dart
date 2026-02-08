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

        // Check if this is a rate limit error (429)
        final errorStr = e.toString().toLowerCase();
        final isRateLimitError = errorStr.contains('429') || errorStr.contains('rate limit');

        Duration delay;
        if (isRateLimitError) {
          // Use longer exponential backoff for rate limit errors: 5s, 10s, 20s
          delay = Duration(
            milliseconds: 5000 * pow(2, attempt).toInt(),
          );
          AppLogger.warning('$operation attempt ${attempt + 1} failed with rate limit (429), backing off for ${delay.inSeconds}s');
        } else {
          // Use standard exponential backoff for other errors
          delay = Duration(
            milliseconds: initialDelay.inMilliseconds * pow(2, attempt).toInt(),
          );
          AppLogger.warning('$operation attempt ${attempt + 1} failed, retrying in ${delay.inMilliseconds}ms: $e');
        }

        await Future.delayed(delay);
      }
    }

    throw Exception('Retry logic should not reach this point');
  }
}