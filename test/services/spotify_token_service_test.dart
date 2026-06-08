import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/spotify_token_service.dart';

void main() {
  group('SpotifyTokenService.extractSpDc', () {
    test('extracts sp_dc from a cookie string with multiple cookies', () {
      const cookie =
          'sp_t=abc123; sp_dc=mySpDcValue; sp_key=xyz';
      expect(SpotifyTokenService.extractSpDc(cookie), 'mySpDcValue');
    });

    test('extracts sp_dc when it is the first cookie', () {
      expect(
        SpotifyTokenService.extractSpDc('sp_dc=firstValue; other=x'),
        'firstValue',
      );
    });

    test('extracts sp_dc when it is the only cookie', () {
      expect(SpotifyTokenService.extractSpDc('sp_dc=solo'), 'solo');
    });

    test('returns null when sp_dc is absent', () {
      expect(SpotifyTokenService.extractSpDc('sp_t=abc; sp_key=xyz'), isNull);
    });

    test('returns null for empty cookie string', () {
      expect(SpotifyTokenService.extractSpDc(''), isNull);
    });

    test('handles sp_dc value containing equals sign', () {
      // Base64-like values may contain =
      expect(
        SpotifyTokenService.extractSpDc('sp_dc=abc=def; other=x'),
        'abc=def',
      );
    });

    test('is not confused by a cookie whose name ends with sp_dc', () {
      // e.g. "not_sp_dc=value" should not match
      expect(
        SpotifyTokenService.extractSpDc('not_sp_dc=trap; other=x'),
        isNull,
      );
    });

    test('trims surrounding whitespace from cookie parts', () {
      // The cookie part "  sp_dc=trimmed  " is trimmed before matching,
      // so the extracted value is 'trimmed' (no surrounding spaces).
      expect(
        SpotifyTokenService.extractSpDc('  sp_dc=trimmed  ; other=y'),
        'trimmed',
      );
    });
  });

  group('SpotifyTokenService.headersFromSpDc', () {
    test('returns a map with Cookie containing only sp_dc', () {
      final headers = SpotifyTokenService.headersFromSpDc('mySpDc');
      expect(headers['Cookie'], 'sp_dc=mySpDc');
    });

    test('includes required Spotify headers', () {
      final headers = SpotifyTokenService.headersFromSpDc('x');
      expect(headers.containsKey('User-Agent'), isTrue);
      expect(headers.containsKey('App-Platform'), isTrue);
      expect(headers['App-Platform'], 'WebPlayer');
      expect(headers['Origin'], 'https://open.spotify.com');
    });
  });
}
