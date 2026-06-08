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
