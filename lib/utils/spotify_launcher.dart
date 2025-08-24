import '../services/app_logger.dart';
import '../services/url_launcher_service.dart';

class SpotifyLauncher {
  /// Launch a Spotify URI in the Spotify app with play action
  /// This will attempt to start playing the content immediately
  static Future<bool> launchSpotifyUriAndPlay(String uri) async {
    AppLogger.spotify('Attempting to PLAY: $uri');
    
    // Try Spotify app first with native URI
    final success = await UrlLauncherService.launchSpotifyUrl(
      uri, 
      webFallbackUrl: _convertUriToWebUrl(uri),
    );
    
    if (success) {
      AppLogger.spotify('Successfully launched and played Spotify URI: $uri');
    }
    
    return success;
  }

  /// Launch a Spotify URI for navigation/browsing (without auto-play)
  /// Uses web URLs to avoid auto-play behavior in the Spotify app
  static Future<bool> launchSpotifyUri(String uri) async {
    AppLogger.spotify('Attempting to NAVIGATE to: $uri');
    
    // For navigation, prefer web URLs to avoid auto-play behavior
    final webUrl = _convertUriToWebUrl(uri);
    if (webUrl != null) {
      final success = await UrlLauncherService.launchWebUrl(webUrl);
      if (success) {
        AppLogger.spotify('Successfully navigated to Spotify web URL: $webUrl');
        return success;
      }
    }
    
    // Fallback to native Spotify URI
    final success = await UrlLauncherService.launchSpotifyUrl(uri);
    if (success) {
      AppLogger.spotify('Successfully navigated to Spotify URI: $uri');
    }
    
    return success;
  }
  
  /// Launch a track in Spotify
  static Future<bool> launchTrack(String trackId) async {
    return await launchSpotifyUri('spotify:track:$trackId');
  }
  
  /// Launch an artist in Spotify
  static Future<bool> launchArtist(String artistId) async {
    return await launchSpotifyUri('spotify:artist:$artistId');
  }
  
  /// Launch an album in Spotify
  static Future<bool> launchAlbum(String albumId) async {
    return await launchSpotifyUri('spotify:album:$albumId');
  }
  
  /// Launch a playlist in Spotify
  static Future<bool> launchPlaylist(String playlistId) async {
    return await launchSpotifyUri('spotify:playlist:$playlistId');
  }
  
  /// Launch a user profile in Spotify
  static Future<bool> launchUser(String userId) async {
    return await launchSpotifyUri('spotify:user:$userId');
  }
  
  /// Convert Spotify URI to web URL for fallback
  static String? _convertUriToWebUrl(String uri) {
    if (uri.startsWith('spotify:')) {
      final parts = uri.split(':');
      if (parts.length >= 3) {
        final type = parts[1]; // track, artist, album, etc.
        final id = parts[2];
        return 'https://open.spotify.com/$type/$id';
      }
    }
    return null;
  }
}