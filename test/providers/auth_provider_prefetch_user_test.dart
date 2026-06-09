// Tests for the x-prefetched-user header parsing in AuthProvider.loginComplete.
// Specifically validates that email and country come from the prefetched payload
// and are not hardcoded to 'user@spotify.com' / 'US'.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/providers/auth_provider.dart';

const _kValidToken =
    'Bearer.token.abc1234567890123456789012345678901234567890';

Future<AuthProvider> _makeProvider() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final provider = AuthProvider(prefs);
  for (var i = 0; i < 50; i++) {
    if (provider.isInitialized) break;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return provider;
}

Map<String, String> _headersWithPrefetch(Map<String, dynamic> prefetch) => {
      'Cookie': 'sp_dc=validSpDc',
      'x-prefetched-user': jsonEncode(prefetch),
    };

void main() {
  group('AuthProvider.loginComplete — prefetched user email and country', () {
    test('uses real email from x-prefetched-user (not hardcoded placeholder)', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': 'michael@example.com',
          'country': 'AU',
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.email, 'michael@example.com');
      expect(provider.currentUser?.email, isNot('user@spotify.com'));
    });

    test('uses real country from x-prefetched-user (not hardcoded US)', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': 'michael@example.com',
          'country': 'AU',
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.country, 'AU');
      expect(provider.currentUser?.country, isNot('US'));
    });

    test('stores empty string for email when /v1/me not available (null in payload)', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': null,
          'country': null,
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.email, '');
      expect(provider.currentUser?.country, '');
      expect(provider.currentUser?.email, isNot('user@spotify.com'));
    });

    test('displayName is correctly parsed from prefetched payload', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': 'abc123def456ghi789jkl012',
          'displayName': 'Jane Smith',
          'email': 'jane@example.com',
          'country': 'GB',
          'followers': 10,
        }),
      );

      expect(provider.currentUser?.displayName, 'Jane Smith');
      expect(provider.currentUser?.id, 'abc123def456ghi789jkl012');
    });

    test('falls back to profileFetcher when x-prefetched-user header is absent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async {
        return null; // force the fail path
      };
      for (var i = 0; i < 50; i++) {
        if (provider.isInitialized) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await expectLater(
        provider.loginComplete(
          _kValidToken,
          {'Cookie': 'sp_dc=validSpDc'}, // no x-prefetched-user
        ),
        throwsA(isA<Exception>()),
      );
      expect(provider.isAuthenticated, isFalse);
    });
  });
}
