import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/spotify_webview_login.dart';
import '../services/app_logger.dart';

class AuthUtils {
  /// Shows a re-authentication dialog when authentication expires
  static Future<bool> showReAuthDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Authentication Expired'),
          content: const Text(
            'Your Spotify session has expired. Please login again to continue using the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Login Again'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  /// Handles re-authentication flow
  static Future<bool> handleReAuthentication(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
      try {
      AppLogger.auth('Starting re-authentication flow...');

      // Clear old authentication data
      await authProvider.logout();

      // Show WebView login
      if (!context.mounted) return false;
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => SpotifyWebViewLogin(
            onAuthComplete: (bearerToken, headers) async {
              AppLogger.auth('Re-authentication completed, processing...');
              try {
                await authProvider.loginComplete(bearerToken, headers);
                AppLogger.auth('Re-authentication successful');

                // Pop the WebView
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.of(context).pop(true);
                }              } catch (e) {
                AppLogger.error('Error in re-authentication', e);
                if (context.mounted) {
                  Navigator.of(context).pop(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Re-authentication failed: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            onCancel: () {
              Navigator.of(context).pop(false);
            },
          ),
        ),
      );
      return result == true;
    } catch (e) {
      AppLogger.error('Error during re-authentication flow', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Re-authentication failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Checks authentication and shows re-auth dialog if needed
  static Future<bool> ensureAuthenticated(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
      AppLogger.auth('Authentication required');

      final shouldReAuth = await showReAuthDialog(context);
      if (shouldReAuth && context.mounted) {
        return await handleReAuthentication(context);
      }
      return false;
    }

    return true;
  }

  /// Handles 401/403 errors.
  ///
  /// Tries silent token recovery first (stored sp_dc, then WebView cookie store).
  /// Only forces logout and shows the login screen when all silent paths fail.
  static Future<void> handleAuthenticationError(BuildContext context, {String? errorMessage}) async {
    AppLogger.auth('Auth error: ${errorMessage ?? "401/403"} — attempting silent recovery');

    if (!context.mounted) return;
    final authProvider = context.read<AuthProvider>();

    try {
      final recovered = await authProvider.tryRecoverFromExpiredToken();
      if (recovered) {
        AppLogger.auth('Silent recovery succeeded — reloading data');
        if (context.mounted) {
          final sp = context.read<SpotifyProvider>();
          sp.clearAuthError();
          sp.refreshData();
        }
        return;
      }
    } catch (e) {
      AppLogger.error('Silent recovery threw unexpectedly', e);
    }

    AppLogger.auth('Silent recovery failed — forcing re-login');
    try {
      await authProvider.logout();
      if (context.mounted && errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session expired: $errorMessage'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error handling authentication error', e);
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }
}
