// test/utils/version_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/utils/version_utils.dart';

void main() {
  group('VersionUtils.extractBaseVersion', () {
    test('returns version unchanged for simple semver', () {
      expect(VersionUtils.extractBaseVersion('1.2.3'), '1.2.3');
    });

    test('strips build metadata', () {
      expect(VersionUtils.extractBaseVersion('1.2.3+42'), '1.2.3');
    });

    test('extracts base from nightly version', () {
      expect(
        VersionUtils.extractBaseVersion('0.0.2-nightly-20250915-061558+1757974558'),
        '0.0.2',
      );
    });
  });

  group('VersionUtils.isNewerVersion', () {
    test('returns true when new version has higher patch', () {
      expect(
        VersionUtils.isNewerVersion(currentVersion: '1.0.0', newVersion: '1.0.1'),
        isTrue,
      );
    });

    test('returns true when new version has higher minor', () {
      expect(
        VersionUtils.isNewerVersion(currentVersion: '1.0.5', newVersion: '1.1.0'),
        isTrue,
      );
    });

    test('returns true when new version has higher major', () {
      expect(
        VersionUtils.isNewerVersion(currentVersion: '1.9.9', newVersion: '2.0.0'),
        isTrue,
      );
    });

    test('returns false for same version', () {
      expect(
        VersionUtils.isNewerVersion(currentVersion: '1.2.3', newVersion: '1.2.3'),
        isFalse,
      );
    });

    test('returns false when new version is older', () {
      expect(
        VersionUtils.isNewerVersion(currentVersion: '2.0.0', newVersion: '1.9.9'),
        isFalse,
      );
    });

    test('nightly vs nightly returns false (use isNewerNightly instead)', () {
      expect(
        VersionUtils.isNewerVersion(
          currentVersion: '0.0.2-nightly-20250901-000000',
          newVersion: '0.0.2-nightly-20250915-000000',
        ),
        isFalse,
      );
    });

    test('nightly vs stable: returns true only if stable has higher base version', () {
      expect(
        VersionUtils.isNewerVersion(
          currentVersion: '0.0.2-nightly-20250915-000000',
          newVersion: '0.1.0',
        ),
        isTrue,
      );
    });

    test('nightly vs stable: returns false if stable has same base version', () {
      expect(
        VersionUtils.isNewerVersion(
          currentVersion: '0.0.2-nightly-20250915-000000',
          newVersion: '0.0.2',
        ),
        isFalse,
      );
    });

    test('stable vs nightly: always false', () {
      expect(
        VersionUtils.isNewerVersion(
          currentVersion: '1.0.0',
          newVersion: '1.0.1-nightly-20250915-000000',
        ),
        isFalse,
      );
    });
  });

  group('VersionUtils.isNewerNightly', () {
    test('returns true when new nightly build is newer', () {
      const current = '0.0.2-nightly-20250901-100000';
      const newer = '0.0.2-nightly-20250901-120000'; // 2 hours later
      expect(
        VersionUtils.isNewerNightly(
          currentVersion: current,
          newVersion: newer,
        ),
        isTrue,
      );
    });

    test('returns true when build is only 3 minutes newer', () {
      const current = '0.0.2-nightly-20250901-100000';
      const sameish = '0.0.2-nightly-20250901-100300'; // 3 minutes later
      expect(
        VersionUtils.isNewerNightly(
          currentVersion: current,
          newVersion: sameish,
        ),
        isTrue,
      );
    });
  });

  group('VersionUtils.formatVersion', () {
    test('returns simple version unchanged', () {
      expect(VersionUtils.formatVersion('1.2.3'), '1.2.3');
    });

    test('formats nightly with date', () {
      final formatted = VersionUtils.formatVersion('0.0.2-nightly-20250615-030600');
      expect(formatted, contains('Nightly'));
      expect(formatted, contains('Jun 15, 2025'));
    });

    test('strips build metadata before formatting', () {
      final formatted = VersionUtils.formatVersion('1.2.3+42');
      expect(formatted, '1.2.3');
    });
  });
}
