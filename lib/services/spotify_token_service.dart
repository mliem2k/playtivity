import 'dart:convert' as convert;
import 'dart:io' as io;
import 'spotify_totp_helper.dart';
import 'app_logger.dart';

/// Fetches Spotify Bearer tokens from an sp_dc cookie without a WebView.
/// Used for silent token refresh on subsequent app sessions.
class SpotifyTokenService {
  static const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

  /// Fetches Spotify's server time via the HTTP Date header for TOTP sync.
  static Future<int> fetchServerTime() async {
    final client = io.HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('https://open.spotify.com/'));
      final response = await request.close();
      final dateStr = response.headers.value('date');
      if (dateStr != null) {
        return io.HttpDate.parse(dateStr).millisecondsSinceEpoch;
      }
    } catch (e) {
      AppLogger.error('Failed to fetch Spotify server time', e);
    } finally {
      client.close();
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Fetches a Bearer access token using a stored sp_dc cookie value.
  /// Returns null if the request fails or sp_dc has expired.
  static Future<String?> fetchBearerToken(String spDc) async {
    final client = io.HttpClient();
    try {
      AppLogger.auth('Fetching Bearer token from sp_dc...');
      final serverTime = await fetchServerTime();
      final totpParams = SpotifyTotpHelper.generateTotpParams(timestampMillis: serverTime);

      final tokenUrl = Uri.parse('https://open.spotify.com/api/token').replace(
        queryParameters: {
          'reason': 'transport',
          'productType': 'web-player',
          'totp': totpParams['totp']!,
          'totpServer': totpParams['totpServer']!,
          'totpVer': totpParams['totpVer']!,
        },
      );

      final request = await client.getUrl(tokenUrl);
      request.headers.set('Cookie', 'sp_dc=$spDc');
      request.headers.set('User-Agent', _ua);
      request.headers.set('Accept', 'application/json');
      request.headers.set('App-Platform', 'WebPlayer');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Referer', 'https://open.spotify.com/');
      request.headers.set('Origin', 'https://open.spotify.com');

      final response = await request.close();
      final body = await response.transform(convert.utf8.decoder).join();

      AppLogger.auth('Token endpoint status: ${response.statusCode}');

      if (response.statusCode == io.HttpStatus.ok) {
        final json = convert.jsonDecode(body);
        if (json is Map && json['accessToken'] != null) {
          AppLogger.auth('Silent token refresh succeeded');
          return json['accessToken'] as String;
        }
      }
      AppLogger.warning('Silent token refresh failed: HTTP ${response.statusCode}');
    } catch (e) {
      AppLogger.error('Silent token refresh error', e);
    } finally {
      client.close();
    }
    return null;
  }

  /// Extracts the sp_dc value from a Cookie header string.
  static String? extractSpDc(String cookieHeader) {
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('sp_dc=')) {
        return trimmed.substring('sp_dc='.length);
      }
    }
    return null;
  }

  /// Builds a minimal headers map from an sp_dc value for API calls.
  static Map<String, String> headersFromSpDc(String spDc) => {
    'Cookie': 'sp_dc=$spDc',
    'User-Agent': _ua,
    'Accept': 'application/json',
    'App-Platform': 'WebPlayer',
    'Referer': 'https://open.spotify.com/',
    'Origin': 'https://open.spotify.com',
  };
}
