// test/services/update_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/update_service.dart';
import 'package:playtivity/utils/version_utils.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UpdateService.isCurrentVersionNightly', () {
    test('returns true for nightly version string', () {
      expect(
        UpdateService.isCurrentVersionNightly('0.0.2-nightly-20250915-061558+1757974558'),
        isTrue,
      );
    });

    test('returns false for stable version string', () {
      expect(UpdateService.isCurrentVersionNightly('1.0.0'), isFalse);
    });

    test('returns false for pre-release without nightly tag', () {
      expect(UpdateService.isCurrentVersionNightly('1.0.0-beta.1'), isFalse);
    });
  });

  group('UpdateService.shouldCheckForUpdates', () {
    test('returns true when never checked before (lastCheck = 0)', () async {
      SharedPreferences.setMockInitialValues({});
      final result = await UpdateService.shouldCheckForUpdates();
      expect(result, isTrue);
    });

    test('returns false when checked very recently (within default 24h window)', () async {
      final recentTimestamp = DateTime.now().millisecondsSinceEpoch - 1000; // 1 second ago
      SharedPreferences.setMockInitialValues({
        'last_update_check_time': recentTimestamp,
      });
      final result = await UpdateService.shouldCheckForUpdates();
      expect(result, isFalse);
    });

    test('returns true when last check was more than 24h ago', () async {
      final oldTimestamp = DateTime.now().millisecondsSinceEpoch -
          (25 * 60 * 60 * 1000); // 25 hours ago
      SharedPreferences.setMockInitialValues({
        'last_update_check_time': oldTimestamp,
      });
      final result = await UpdateService.shouldCheckForUpdates();
      expect(result, isTrue);
    });
  });

  group('UpdateService preferences', () {
    test('getNightlyBuildPreference returns false by default', () async {
      final result = await UpdateService.getNightlyBuildPreference();
      expect(result, isFalse);
    });

    test('setNightlyBuildPreference persists value', () async {
      await UpdateService.setNightlyBuildPreference(true);
      final result = await UpdateService.getNightlyBuildPreference();
      expect(result, isTrue);
    });

    test('getCheckFrequency returns 24 by default', () async {
      final result = await UpdateService.getCheckFrequency();
      expect(result, 24);
    });

    test('setCheckFrequency persists value', () async {
      await UpdateService.setCheckFrequency(12);
      final result = await UpdateService.getCheckFrequency();
      expect(result, 12);
    });

    test('getAutoDownloadPreference returns false by default', () async {
      final result = await UpdateService.getAutoDownloadPreference();
      expect(result, isFalse);
    });

    test('setAutoDownloadPreference persists value', () async {
      await UpdateService.setAutoDownloadPreference(true);
      final result = await UpdateService.getAutoDownloadPreference();
      expect(result, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // _shouldUpdateToNightly — stable-to-nightly base-version guard
  // ---------------------------------------------------------------------------
  group('_shouldUpdateToNightly via VersionUtils — stable base version guard', () {
    // These tests use the public VersionUtils helpers to validate the logic that
    // was previously always returning true for stable→nightly users.

    test('nightly on same base version is at-least-same (should offer)', () {
      const stableBase = '0.0.2';
      const nightlyBase = '0.0.2';
      final atLeastSame = VersionUtils.isNewerVersion(
            currentVersion: stableBase,
            newVersion: nightlyBase,
          ) ||
          stableBase == nightlyBase;
      expect(atLeastSame, isTrue);
    });

    test('nightly on newer base version should be offered', () {
      const stableBase = '0.0.2';
      const nightlyBase = '0.0.3';
      final atLeastSame = VersionUtils.isNewerVersion(
            currentVersion: stableBase,
            newVersion: nightlyBase,
          ) ||
          stableBase == nightlyBase;
      expect(atLeastSame, isTrue);
    });

    test('nightly on older base version must NOT be offered (was the bug)', () {
      const stableBase = '0.0.2';
      const nightlyBase = '0.0.1';
      final atLeastSame = VersionUtils.isNewerVersion(
            currentVersion: stableBase,
            newVersion: nightlyBase,
          ) ||
          stableBase == nightlyBase;
      expect(atLeastSame, isFalse,
          reason: 'Offering nightly-0.0.1 to stable-0.0.2 user is a downgrade');
    });

    test('isNewerNightly returns true for a build 2 hours newer', () {
      const current = '0.0.2-nightly-20260609-020000';
      const newer = '0.0.2-nightly-20260609-040000';
      expect(
        VersionUtils.isNewerNightly(currentVersion: current, newVersion: newer),
        isTrue,
      );
    });

    test('isNewerNightly returns false when build is only 3 minutes newer', () {
      const current = '0.0.2-nightly-20260609-100000';
      const sameish = '0.0.2-nightly-20260609-100300';
      expect(
        VersionUtils.isNewerNightly(currentVersion: current, newVersion: sameish),
        isFalse,
      );
    });

    test('isNewerNightly returns false for same version', () {
      const v = '0.0.2-nightly-20260609-100000';
      expect(
        VersionUtils.isNewerNightly(currentVersion: v, newVersion: v),
        isFalse,
      );
    });
  });
}
