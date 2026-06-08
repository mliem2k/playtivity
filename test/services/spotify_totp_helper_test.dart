// test/services/spotify_totp_helper_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/services/spotify_totp_helper.dart';

void main() {
  group('SpotifyTotpHelper.generateTotp', () {
    test('returns a 6-digit string', () {
      final totp = SpotifyTotpHelper.generateTotp(
        timestampMillis: 1700000000000,
      );
      expect(totp.length, 6);
      expect(RegExp(r'^\d{6}$').hasMatch(totp), isTrue);
    });

    test('is deterministic for the same timestamp within the same 30-second window', () {
      const ts = 1700000000000;
      final totp1 = SpotifyTotpHelper.generateTotp(timestampMillis: ts);
      final totp2 = SpotifyTotpHelper.generateTotp(timestampMillis: ts + 5000); // +5s, same window
      expect(totp1, totp2);
    });

    test('produces different code for different 30-second windows', () {
      const ts = 1700000000000;
      final totp1 = SpotifyTotpHelper.generateTotp(timestampMillis: ts);
      final totp2 = SpotifyTotpHelper.generateTotp(timestampMillis: ts + 30000); // +30s, new window
      expect(totp1, isNot(totp2));
    });

    test('uses current time when no timestamp provided', () {
      final totp = SpotifyTotpHelper.generateTotp();
      expect(totp.length, 6);
      expect(RegExp(r'^\d{6}$').hasMatch(totp), isTrue);
    });
  });

  group('SpotifyTotpHelper TOTP algorithm correctness', () {
    // Reference value verified against the live Spotify web player via Playwright
    // on 2026-06-09: at unix timestamp 1780948075s (timeStep 59364935),
    // with v61 secrets and an 8-byte counter, the code must be 159457.
    // The 4-byte implementation produced 000165 (wrong) — confirmed by intercepting
    // the real web player's /api/token request which returned 159457 and got 200 OK.
    test('generates the Spotify-verified code 159457 for v61 at timeStep 59364935', () {
      SpotifyTotpHelper.applySecrets({
        '61': [44,55,47,42,70,40,34,114,76,74,50,111,120,97,75,76,94,102,43,69,49,120,118,80,64,78],
      });
      // 1780948075000 ms → timeStep 59364935
      final totp = SpotifyTotpHelper.generateTotp(timestampMillis: 1780948075000);
      SpotifyTotpHelper.clearRuntimeSecrets();
      expect(totp, '159457',
          reason: '8-byte counter (RFC 6238) is required; 4-byte counter produces 000165');
    });
  });

  group('SpotifyTotpHelper hardcoded secrets freshness', () {
    test('secretCipherDict contains versions >= 50 (Spotify requires v59+ as of mid-2025)', () {
      final maxVersion = SpotifyTotpHelper.secretCipherDict.keys
          .map(int.parse)
          .reduce((a, b) => a > b ? a : b);
      expect(maxVersion, greaterThanOrEqualTo(50),
          reason: 'Spotify rotated TOTP secrets to v59+ in 2025; v14 and older are rejected by the API');
    });

    test('totpVer constant is not stuck at a stale version', () {
      expect(int.parse(SpotifyTotpHelper.totpVer), greaterThanOrEqualTo(50),
          reason: 'totpVer must match a currently accepted Spotify version (v59+ as of mid-2025)');
    });
  });

  group('SpotifyTotpHelper.generateTotpParams', () {
    test('returns map with totp, totpServer, totpVer keys', () {
      const ts = 1700000000000;
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: ts);
      expect(params.containsKey('totp'), isTrue);
      expect(params.containsKey('totpServer'), isTrue);
      expect(params.containsKey('totpVer'), isTrue);
    });

    test('totpServer is the unix timestamp in seconds', () {
      const ts = 1700000000000;
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: ts);
      expect(params['totpServer'], '1700000000');
    });

    test('totpVer matches the current configured version', () {
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: 1700000000000);
      expect(params['totpVer'], SpotifyTotpHelper.totpVer);
    });

    test('totp in params matches standalone generateTotp output', () {
      const ts = 1700000000000;
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: ts);
      final standalone = SpotifyTotpHelper.generateTotp(timestampMillis: ts);
      expect(params['totp'], standalone);
    });
  });
}
