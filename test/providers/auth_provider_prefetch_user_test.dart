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
    test('returns real email michael_liem2000@yahoo.com from x-prefetched-user', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': 'michael_liem2000@yahoo.com',
          'country': 'ID',
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.email, 'michael_liem2000@yahoo.com');
      expect(provider.currentUser?.email, isNot('user@spotify.com'));
    });

    test('returns real country ID (Indonesia) from x-prefetched-user', () async {
      final provider = await _makeProvider();

      await provider.loginComplete(
        _kValidToken,
        _headersWithPrefetch({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': 'michael_liem2000@yahoo.com',
          'country': 'ID',
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.country, 'ID');
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
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'displayName': 'Michael Liem',
          'email': 'michael_liem2000@yahoo.com',
          'country': 'ID',
          'followers': 48,
        }),
      );

      expect(provider.currentUser?.displayName, 'Michael Liem');
      expect(provider.currentUser?.id, '21fvdxlt6ejvha6jnrgdwamja');
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

  group('AuthProvider._initializeAuth — stale placeholder migration', () {
    test('scrubs user@spotify.com email and US country stored from old app version', () async {
      // Simulate stored data from an older build that wrote hardcoded placeholders.
      SharedPreferences.setMockInitialValues({
        'spotify_bearer_token': _kValidToken,
        'spotify_headers': jsonEncode({'Cookie': 'sp_dc=validSpDc'}),
        'spotify_user': jsonEncode({
          'id': '21fvdxlt6ejvha6jnrgdwamja',
          'display_name': 'Michael Liem',
          'email': 'user@spotify.com',
          'country': 'US',
          'image_url': null,
          'followers': 48,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      for (var i = 0; i < 50; i++) {
        if (provider.isInitialized) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(provider.currentUser?.email, '');
      expect(provider.currentUser?.country, '');
      expect(provider.currentUser?.displayName, 'Michael Liem');
    });

    test('leaves real US country intact when email is also real (not a placeholder)', () async {
      // A genuine US user must not have their country cleared.
      SharedPreferences.setMockInitialValues({
        'spotify_bearer_token': _kValidToken,
        'spotify_headers': jsonEncode({'Cookie': 'sp_dc=validSpDc'}),
        'spotify_user': jsonEncode({
          'id': 'realuserid1234567890',
          'display_name': 'Real User',
          'email': 'real@gmail.com',
          'country': 'US',
          'image_url': null,
          'followers': 5,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      for (var i = 0; i < 50; i++) {
        if (provider.isInitialized) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(provider.currentUser?.email, 'real@gmail.com');
      expect(provider.currentUser?.country, 'US');
    });
  });
}
