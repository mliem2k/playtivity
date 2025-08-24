/// Centralized API constants for all external service endpoints
class ApiConstants {
  // Spotify API URLs
  static const String spotifyApiBaseUrl = 'https://api.spotify.com/v1';
  static const String spotifyAuthUrl = 'https://accounts.spotify.com';
  static const String spotifyWebUrl = 'https://open.spotify.com';
  static const String spotifyBuddyBaseUrl = 'https://guc-spclient.spotify.com';
  static const String spotifyPartnerApiUrl = 'https://api-partner.spotify.com/pathfinder/v2/query';
  
  // GitHub API URLs
  static const String githubReleasesApi = 'https://api.github.com/repos/mliem2k/playtivity/releases';
  static const String githubRawContentBase = 'https://github.com/mliem/playtivity/raw/main';
  
  // Endpoints
  static const String currentUserEndpoint = '/me';
  static const String currentlyPlayingEndpoint = '/me/player/currently-playing';
  static const String tracksEndpoint = '/tracks';
  static const String artistsEndpoint = '/artists';
  
  // Headers
  static const Map<String, String> spotifyWebHeaders = {
    'origin': 'https://open.spotify.com',
    'referer': 'https://open.spotify.com/',
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };
  
  static const Map<String, String> spotifyApiHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Encoding': 'gzip',
    'Connection': 'Keep-Alive',
    'Host': 'api.spotify.com',
    'User-Agent': 'okhttp/4.9.2',
  };
  
  // Common URLs builders
  static String spotifyTrackUrl(String trackId) => '$spotifyApiBaseUrl/tracks/$trackId';
  static String spotifyArtistUrl(String artistId) => '$spotifyApiBaseUrl/artists/$artistId';
  static String spotifyUserWebUrl(String userId) => '$spotifyWebUrl/user/$userId';
  static String githubNightlyApkUrl(String fileName) => '$githubRawContentBase/nightly/$fileName';
  static String githubReleaseApkUrl(String fileName) => '$githubRawContentBase/releases/$fileName';
}