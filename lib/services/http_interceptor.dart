import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/auth_utils.dart';
import 'app_logger.dart';

/// HTTP interceptor that automatically handles 401/403 errors by redirecting to login
class HttpInterceptor {
  static BuildContext? _currentContext;
  
  /// Set the current context for navigation purposes
  static void setContext(BuildContext context) {
    _currentContext = context;
  }
  
  /// Clear the context when no longer needed
  static void clearContext() {
    _currentContext = null;
  }
  
  /// Intercepted GET request that handles 401/403 errors
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await http.get(url, headers: headers);
      await _handleResponse(response);
      return response;
    } catch (e) {
      rethrow;
    }
  }
  
  /// Intercepted POST request that handles 401/403 errors
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    try {
      final response = await http.post(
        url, 
        headers: headers, 
        body: body, 
        encoding: encoding,
      );
      await _handleResponse(response);
      return response;
    } catch (e) {
      rethrow;
    }
  }
    /// Handle response and check for authentication errors
  static Future<void> _handleResponse(http.Response response) async {
    if ((response.statusCode == 401 || response.statusCode == 403) && _currentContext != null) {
      AppLogger.http('HTTP ${response.statusCode} detected - redirecting to login');
      
      // Use the AuthUtils to handle the authentication error
      // This will log out the user and navigate to login screen
      await AuthUtils.handleAuthenticationError(
        _currentContext!,
        errorMessage: 'Session expired (${response.statusCode})',
      );
    }
  }
}
