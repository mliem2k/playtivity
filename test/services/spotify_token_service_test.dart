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

  // ---------------------------------------------------------------------------
  // parseTokenResponse — response parsing for the /api/token endpoint
  // ---------------------------------------------------------------------------

  group('SpotifyTokenService.parseTokenResponse', () {
    test('returns accessToken from a valid 200 response', () {
      const body = '{"accessToken":"Bearer.abc.123","isAnonymous":false}';
      expect(SpotifyTokenService.parseTokenResponse(200, body), 'Bearer.abc.123');
    });

    test('returns null for 401 regardless of body', () {
      const body = '{"accessToken":"should-be-ignored"}';
      expect(SpotifyTokenService.parseTokenResponse(401, body), isNull);
    });

    test('returns null for 400', () {
      expect(SpotifyTokenService.parseTokenResponse(400, '{}'), isNull);
    });

    test('returns null for 403', () {
      expect(SpotifyTokenService.parseTokenResponse(403, '{"error":"forbidden"}'), isNull);
    });

    test('returns null when 200 body has only AnonymousToken (sp_dc expired)', () {
      // AnonymousToken means Spotify rejected the sp_dc — the correct
      // response is null so the caller can fall back to re-authentication.
      const body = '{"AnonymousToken":"anon-tok","isAnonymous":true}';
      expect(SpotifyTokenService.parseTokenResponse(200, body), isNull);
    });

    test('returns null when 200 body has no accessToken field', () {
      const body = '{"someOtherField":"value"}';
      expect(SpotifyTokenService.parseTokenResponse(200, body), isNull);
    });

    test('returns null for empty body', () {
      expect(SpotifyTokenService.parseTokenResponse(200, ''), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(SpotifyTokenService.parseTokenResponse(200, 'not-json{{{'), isNull);
    });

    test('returns null when accessToken is null in JSON', () {
      const body = '{"accessToken":null}';
      expect(SpotifyTokenService.parseTokenResponse(200, body), isNull);
    });

    test('returns null when accessToken is empty string', () {
      const body = '{"accessToken":""}';
      expect(SpotifyTokenService.parseTokenResponse(200, body), isNull);
    });

    test('returns null for 500 server error', () {
      expect(SpotifyTokenService.parseTokenResponse(500, '{"error":"server error"}'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // buildTokenUrl — URL construction for the /api/token endpoint
  // ---------------------------------------------------------------------------

  group('SpotifyTokenService.buildTokenUrl', () {
    final sampleParams = {
      'totp': '123456',
      'totpServer': '654321',
      'totpVer': '14',
    };

    test('targets the correct Spotify /api/token endpoint', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.host, 'open.spotify.com');
      expect(url.path, '/api/token');
    });

    test('includes reason=transport query parameter', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.queryParameters['reason'], 'transport');
    });

    test('includes productType=web-player query parameter', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.queryParameters['productType'], 'web-player');
    });

    test('includes totp parameter from provided params', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.queryParameters['totp'], '123456');
    });

    test('includes totpServer parameter from provided params', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.queryParameters['totpServer'], '654321');
    });

    test('includes totpVer parameter from provided params', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.queryParameters['totpVer'], '14');
    });

    test('uses HTTPS scheme', () {
      final url = SpotifyTokenService.buildTokenUrl(sampleParams);
      expect(url.scheme, 'https');
    });
  });
}
