// test/services/update_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/update_service.dart';

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
}
