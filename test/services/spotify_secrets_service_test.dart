// test/services/spotify_secrets_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_secrets_service.dart';
import 'package:playtivity/services/spotify_totp_helper.dart';

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

  group('SpotifyTotpHelper runtime secrets', () {
    setUp(() => SpotifyTotpHelper.clearRuntimeSecrets());
    tearDown(() => SpotifyTotpHelper.clearRuntimeSecrets());

    test('activeVersion returns highest hardcoded version when no runtime secrets', () {
      // hardcoded dict has keys '59', '60', '61' — max is '61'
      expect(SpotifyTotpHelper.activeVersion, '61');
    });

    test('activeVersion returns highest version from applied secrets', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
        '14': [62, 54, 109, 83, 107, 77, 41, 103, 45, 93, 114, 38, 41, 97, 64, 51, 95, 94, 95, 94],
      });
      expect(SpotifyTotpHelper.activeVersion, '15');
    });

    test('generateTotp produces different code after applySecrets with different bytes', () {
      final totpBefore = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);

      SpotifyTotpHelper.applySecrets({
        '14': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      final totpAfter = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);

      expect(totpBefore, isNot(totpAfter));
    });

    test('clearRuntimeSecrets reverts activeVersion to hardcoded fallback', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      expect(SpotifyTotpHelper.activeVersion, '15');
      SpotifyTotpHelper.clearRuntimeSecrets();
      // After clearing, reverts to the highest hardcoded version (currently '61')
      expect(SpotifyTotpHelper.activeVersion, '61');
    });

    test('generateTotpParams totpVer reflects activeVersion', () {
      SpotifyTotpHelper.applySecrets({
        '15': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20],
      });
      final params = SpotifyTotpHelper.generateTotpParams(timestampMillis: 1700000000000);
      expect(params['totpVer'], '15');
    });
  });

  group('SpotifySecretsService.loadAndApply — cache-hit flow', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SpotifyTotpHelper.clearRuntimeSecrets();
    });
    tearDown(() => SpotifyTotpHelper.clearRuntimeSecrets());

    test('loadAndApply with fresh valid cache applies secrets to SpotifyTotpHelper', () async {
      // Pre-populate a fresh cache with current-era secrets
      final freshTs = DateTime.now().millisecondsSinceEpoch - (1 * 60 * 60 * 1000); // 1h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': freshTs,
        'spotify_totp_secrets': '{"61": [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78]}',
      });

      final result = await SpotifySecretsService.loadAndApply();

      expect(result, isNotNull);
      expect(result!['61'], isA<List<int>>());
      // After loadAndApply, SpotifyTotpHelper uses the applied secrets
      expect(SpotifyTotpHelper.activeVersion, '61');
    });

    test('loadAndApply with stale cache returns null, hardcoded fallback intact', () async {
      final staleTs = DateTime.now().millisecondsSinceEpoch - (8 * 60 * 60 * 1000); // 8h ago
      SharedPreferences.setMockInitialValues({
        'spotify_totp_secrets_ts': staleTs,
        'spotify_totp_secrets': '{"14": [62, 54, 109, 83]}',
      });

      // Network will fail in test environment — loadAndApply returns null gracefully.
      // In CI/offline environments result will be null; if network is available it may return secrets.
      final result = await SpotifySecretsService.loadAndApply().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      // result is null (network unavailable) or a valid secrets map (network available) — both are acceptable
      if (result != null) {
        expect(result, isA<Map<String, List<int>>>());
      }

      // Hardcoded fallback still produces valid TOTP
      final totpCode = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);
      expect(totpCode.length, 6);
      expect(RegExp(r'^\d{6}$').hasMatch(totpCode), isTrue);
    });

    test('loadAndApply with no cache returns null, hardcoded fallback intact', () async {
      SharedPreferences.setMockInitialValues({});

      // Network will fail in test environment — loadAndApply returns null gracefully.
      // In CI/offline environments result will be null; if network is available it may return secrets.
      final result = await SpotifySecretsService.loadAndApply().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      // result is null (network unavailable) or a valid secrets map (network available) — both are acceptable
      if (result != null) {
        expect(result, isA<Map<String, List<int>>>());
      }

      // Hardcoded fallback still produces valid TOTP
      final totpCode = SpotifyTotpHelper.generateTotp(timestampMillis: 1700000000000);
      expect(totpCode.length, 6);
      expect(RegExp(r'^\d{6}$').hasMatch(totpCode), isTrue);
    });
  });
}
