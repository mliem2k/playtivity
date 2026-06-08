// test/services/spotify_secrets_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_secrets_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SpotifySecretsService.validateSecretsFormat', () {
    test('accepts valid dict with int-list values', () {
      final result = SpotifySecretsService.validateSecretsFormat({
        '14': [62, 54, 109, 83],
        '13': [59, 92, 64, 70],
      });
      expect(result, isNotNull);
      expect(result!['14'], [62, 54, 109, 83]);
      expect(result['13'], [59, 92, 64, 70]);
    });

    test('rejects empty dict', () {
      expect(SpotifySecretsService.validateSecretsFormat({}), isNull);
    });

    test('rejects non-digit key', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'v14': [1, 2, 3]}),
        isNull,
      );
    });

    test('rejects key with letters mixed in', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14a': [1, 2, 3]}),
        isNull,
      );
    });

    test('rejects value that is not a list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': 'not-a-list'}),
        isNull,
      );
    });

    test('rejects value that is a map not a list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': {'nested': 1}}),
        isNull,
      );
    });

    test('rejects list containing non-ints', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': [1, 'two', 3]}),
        isNull,
      );
    });

    test('rejects empty value list', () {
      expect(
        SpotifySecretsService.validateSecretsFormat({'14': []}),
        isNull,
      );
    });
  });

  group('SpotifySecretsService cache TTL', () {
    test('fresh cache (< 6h) passes TTL check', () async {
      final freshTs = DateTime.now().millisecondsSinceEpoch - (1 * 60 * 60 * 1000); // 1h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': freshTs,
      });
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('spotify_totp_secrets_ts')!;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      expect(age, lessThan(6 * 60 * 60 * 1000));
    });

    test('stale cache (> 6h) fails TTL check', () async {
      final staleTs = DateTime.now().millisecondsSinceEpoch - (7 * 60 * 60 * 1000); // 7h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': staleTs,
      });
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('spotify_totp_secrets_ts')!;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      expect(age, greaterThan(6 * 60 * 60 * 1000));
    });

    test('missing timestamp means no usable cache', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('spotify_totp_secrets_ts'), isNull);
    });
  });
}
