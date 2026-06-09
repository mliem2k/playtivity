import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/auth_utils.dart';
import '../utils/navigator_key.dart';
import 'app_logger.dart';

/// HTTP interceptor that automatically handles 401/403 errors by redirecting to login.
/// Uses the app-wide [navigatorKey] to obtain a context without holding a reference
/// to a specific [BuildContext], which avoids stale-context bugs.
class HttpInterceptor {
  /// Override the HTTP client used for all requests — set in tests only.
  @visibleForTesting
  static http.Client? testClient;

  static http.Client get _client => testClient ?? http.Client();

  /// Check if the URL should be excluded from automatic login redirection
  static bool _shouldExcludeFromLoginRedirect(Uri url) {
    return url.toString().contains('api-partner.spotify.com/pathfinder/v2/query');
  }

  /// Intercepted GET request that handles 401/403 errors
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(url, headers: headers);
    await _handleResponse(response, url);
    return response;
  }

  /// Intercepted POST request that handles 401/403 errors
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await _client.post(
      url,
      headers: headers,
      body: body,
      encoding: encoding,
    );
    await _handleResponse(response, url);
    return response;
  }

  static Future<void> _handleResponse(http.Response response, Uri url) async {
    if (response.statusCode != 401 && response.statusCode != 403) return;

    AppLogger.http('HTTP ${response.statusCode} detected - authentication error');

    if (_shouldExcludeFromLoginRedirect(url)) {
      AppLogger.http('Skipping login redirect for excluded endpoint: ${url.path}');
      return;
    }

    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      AppLogger.http('Context available - redirecting to login');
      await AuthUtils.handleAuthenticationError(
        context,
        errorMessage: 'Session expired (${response.statusCode})',
      );
    } else {
      AppLogger.http('No context available - throwing authentication error');
      throw Exception('Authentication failed: HTTP ${response.statusCode}');
    }
  }
}
