// test/services/spotify_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/spotify_service.dart';
import 'package:playtivity/constants/api_constants.dart';

void main() {
  group('SpotifyService.getAuthorizationUrl', () {
    test('returns the Spotify accounts URL', () {
      final service = SpotifyService();
      final url = service.getAuthorizationUrl();
      expect(url, 'https://accounts.spotify.com');
      expect(url, ApiConstants.spotifyAuthUrl);
    });
  });

  group('ApiConstants URL builders', () {
    test('spotifyTrackUrl builds correct URL', () {
      expect(
        ApiConstants.spotifyTrackUrl('4iV5W9uYEdYUVa79Axb7Rh'),
        'https://api.spotify.com/v1/tracks/4iV5W9uYEdYUVa79Axb7Rh',
      );
    });

    test('spotifyArtistUrl builds correct URL', () {
      expect(
        ApiConstants.spotifyArtistUrl('0OdUWJ0sBjDrqHygGUXeCF'),
        'https://api.spotify.com/v1/artists/0OdUWJ0sBjDrqHygGUXeCF',
      );
    });

    test('spotifyUserWebUrl builds correct URL', () {
      expect(
        ApiConstants.spotifyUserWebUrl('user123'),
        'https://open.spotify.com/user/user123',
      );
    });

    test('spotifyApiBaseUrl ends without trailing slash', () {
      expect(ApiConstants.spotifyApiBaseUrl.endsWith('/'), isFalse);
    });

    test('currentUserEndpoint starts with slash', () {
      expect(ApiConstants.currentUserEndpoint.startsWith('/'), isTrue);
    });

    test('combined baseUrl + endpoint produces valid URL', () {
      final url = ApiConstants.spotifyApiBaseUrl + ApiConstants.currentUserEndpoint;
      expect(url, 'https://api.spotify.com/v1/me');
    });
  });
}
