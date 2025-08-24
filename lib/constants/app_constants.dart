/// Centralized application constants for dimensions, durations, and common values
class AppConstants {
  // Dimensions
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  
  static const double defaultBorderRadius = 8.0;
  static const double circularBorderRadius = 20.0;
  
  static const double avatarRadius = 20.0;
  static const double imageSize = 64.0;
  static const double iconSize = 24.0;
  
  // Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 300);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);
  
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration shortTimeout = Duration(seconds: 15);
  
  static const Duration cacheRefreshInterval = Duration(minutes: 1, seconds: 30);
  static const Duration retryInitialDelay = Duration(milliseconds: 50);
  
  // Retry configuration
  static const int defaultMaxRetries = 3;
  static const double retryBackoffMultiplier = 2.0;
  
  // Cache keys
  static const String trackDurationCacheKey = 'track_duration_cache';
  static const String artistDetailsCacheKey = 'artist_details_cache';
  
  // Default values
  static const String unknownArtist = 'Unknown Artist';
  static const String unknownAlbum = 'Unknown Album';
  static const String unknownTrack = 'Unknown Track';
  static const String defaultCountry = '';
  
  // Format patterns
  static const String timeFormatPattern = 'mm:ss';
  
  // Test data URLs (for development/testing)
  static const String testImageBaseUrl = 'https://picsum.photos';
  
  // Widget refresh intervals
  static const Duration widgetRefreshInterval = Duration(minutes: 15);
  
  // UI Constants
  static const int maxRecentActivities = 50;
  static const int maxTracksPerPlaylist = 100;
  
  // Spotify URI prefixes
  static const String spotifyTrackPrefix = 'spotify:track:';
  static const String spotifyArtistPrefix = 'spotify:artist:';
  static const String spotifyAlbumPrefix = 'spotify:album:';
  static const String spotifyPlaylistPrefix = 'spotify:playlist:';
  static const String spotifyUserPrefix = 'spotify:user:';
}