import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_logger.dart';

class FriendProfileLauncher {
  static const MethodChannel _channel = MethodChannel('playtivity_widget');

  /// Open a friend's Spotify profile
  static Future<bool> openFriendProfile(String userId, {String? friendName}) async {
    try {
      AppLogger.spotify('Opening friend profile: $friendName (ID: $userId)');
      
      // Try using the native Android method first (for better integration)
      try {
        await _channel.invokeMethod('openFriendProfile', {
          'userId': userId,
          'friendName': friendName,
        });
        AppLogger.spotify('Opened friend profile via native Android method');
        return true;
      } catch (e) {
        AppLogger.warning('Native method failed, falling back to direct URL launch: $e');
      }
      
      // Fallback to direct URL launching
      return await _launchSpotifyProfile(userId);
    } catch (e) {
      AppLogger.error('Error opening friend profile', e);
      return false;
    }
  }

  /// Direct method to launch Spotify profile using URL launcher
  static Future<bool> _launchSpotifyProfile(String userId) async {
    try {
      // Try Spotify app URI first
      final spotifyUri = Uri.parse('spotify:user:$userId');
      if (await canLaunchUrl(spotifyUri)) {
        final success = await launchUrl(
          spotifyUri,
          mode: LaunchMode.externalApplication,
        );
        if (success) {
          AppLogger.spotify('Successfully opened Spotify profile via app: $userId');
          return true;
        }
      }
      
      // Fallback to web URL
      final webUrl = Uri.parse('https://open.spotify.com/user/$userId');
      if (await canLaunchUrl(webUrl)) {
        final success = await launchUrl(
          webUrl,
          mode: LaunchMode.externalApplication,
        );
        if (success) {
          AppLogger.spotify('Successfully opened Spotify profile via web: $userId');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      AppLogger.error('Error launching Spotify profile directly', e);
      return false;
    }
  }
} 