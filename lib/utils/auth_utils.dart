import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/spotify_webview_login.dart';

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
      print('🔄 Starting re-authentication flow...');
      
      // Clear old authentication data
      await authProvider.logout();
      
      // Show WebView login
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => SpotifyWebViewLogin(
            onAuthComplete: (bearerToken, headers) async {
              print('🔄 Re-authentication completed, processing...');
              try {
                await authProvider.handleAuthComplete(bearerToken, headers);
                print('✅ Re-authentication successful');
                
                // Pop the WebView
                if (context.mounted && Navigator.canPop(context)) {
                  Navigator.of(context).pop(true);
                }
              } catch (e) {
                print('❌ Error in re-authentication: $e');
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
      print('❌ Error during re-authentication flow: $e');
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
      print('⚠️ Authentication required');
      
      final shouldReAuth = await showReAuthDialog(context);
      if (shouldReAuth && context.mounted) {
        return await handleReAuthentication(context);
      }
      return false;
    }
    
    return true;
  }
} 