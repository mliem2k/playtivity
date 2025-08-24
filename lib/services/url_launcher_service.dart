import 'package:url_launcher/url_launcher.dart';
import '../services/app_logger.dart';

class UrlLauncherService {
  static Future<bool> launchUrlWithFallback(
    String url, {
    String? fallbackUrl,
    LaunchMode mode = LaunchMode.externalApplication,
    String? successMessage,
    String? errorMessage,
    bool webOnlyWindow = false,
  }) async {
    try {
      final uri = Uri.parse(url);
      
      if (await canLaunchUrl(uri)) {
        final success = await launchUrl(
          uri,
          mode: mode,
          webOnlyWindowName: webOnlyWindow ? '_blank' : null,
        );
        
        if (success && successMessage != null) {
          AppLogger.info(successMessage);
        }
        
        return success;
      } else {
        throw Exception('Cannot launch URL: $url');
      }
    } catch (e) {
      AppLogger.error(errorMessage ?? 'Failed to launch URL: $url', e);
      
      // Try fallback URL if provided
      if (fallbackUrl != null) {
        return await _launchFallback(fallbackUrl, mode);
      }
      
      return false;
    }
  }
  
  static Future<bool> _launchFallback(String fallbackUrl, LaunchMode mode) async {
    try {
      final fallbackUri = Uri.parse(fallbackUrl);
      
      if (await canLaunchUrl(fallbackUri)) {
        final success = await launchUrl(fallbackUri, mode: mode);
        
        if (success) {
          AppLogger.info('Opened fallback URL successfully');
        }
        
        return success;
      }
    } catch (e) {
      AppLogger.error('Fallback URL also failed', e);
    }
    
    return false;
  }
  
  static Future<bool> launchSpotifyUrl(String spotifyUrl, {String? webFallbackUrl}) async {
    return launchUrlWithFallback(
      spotifyUrl,
      fallbackUrl: webFallbackUrl,
      successMessage: 'Opened Spotify app successfully',
      errorMessage: 'Failed to open Spotify URL',
    );
  }
  
  static Future<bool> launchWebUrl(String webUrl) async {
    return launchUrlWithFallback(
      webUrl,
      mode: LaunchMode.externalApplication,
      successMessage: 'Opened web URL successfully',
      errorMessage: 'Failed to open web URL',
    );
  }
}