import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/providers/auth_provider.dart';
import 'package:playtivity/models/user.dart';
import '../helpers/test_fixtures.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

User _fakeUser() => User.fromJson(TestFixtures.userJson());

/// Builds an [AuthProvider] with injectable network seams so no real HTTP
/// calls are made. Overrides must be set before init runs (microtask), so
/// they are passed here and applied before returning.
Future<AuthProvider> _makeProvider({
  Map<String, Object> prefsValues = const {},
  Future<String?> Function(String)? tokenFetcher,
  Future<User?> Function(String)? profileFetcher,
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final provider = AuthProvider(prefs);
  if (tokenFetcher != null) provider.tokenFetchOverride = tokenFetcher;
  if (profileFetcher != null) provider.userProfileFetchOverride = profileFetcher;
  return provider;
}

/// Waits for [AuthProvider.isInitialized] to become true (i.e. state is no
/// longer [AuthState.uninitialized]).
Future<void> _waitForInit(AuthProvider provider) async {
  for (var i = 0; i < 50; i++) {
    if (provider.isInitialized) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // 1. Initial state
  // ---------------------------------------------------------------------------
  group('AuthProvider — initial state', () {
    test('authState is uninitialized before init completes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // Construct without waiting — the microtask hasn't run yet.
      final provider = AuthProvider(prefs);

      expect(provider.authState, AuthState.uninitialized);
      expect(provider.isInitialized, isFalse);
    });

    test('authState is unauthenticated after init with no stored credentials',
        () async {
      final provider = await _makeProvider();
      await _waitForInit(provider);

      expect(provider.authState, AuthState.unauthenticated);
      expect(provider.isInitialized, isTrue);
      expect(provider.isAuthenticated, isFalse);
    });

    test('authState is authenticated when startup silent refresh succeeds',
        () async {
      // Provide sp_dc but no bearer token so the init path goes through
      // _trySilentRefresh (which uses the overridable tokenFetchOverride).
      final provider = await _makeProvider(
        prefsValues: {'spotify_sp_dc': 'validSpDc'},
        tokenFetcher: (_) async =>
            'refreshedToken12345678901234567890123456789012345',
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);

      expect(provider.authState, AuthState.authenticated);
      expect(provider.isAuthenticated, isTrue);
    });

    test('authState is unauthenticated when startup silent refresh fails',
        () async {
      final provider = await _makeProvider(
        prefsValues: {'spotify_sp_dc': 'expiredSpDc'},
        tokenFetcher: (_) async => null, // refresh fails
      );
      await _waitForInit(provider);

      expect(provider.authState, AuthState.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. loginComplete — AuthState transitions
  // ---------------------------------------------------------------------------
  group('AuthProvider.loginComplete — AuthState transitions', () {
    test('transitions to authenticated on success', () async {
      final provider = await _makeProvider(
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_dc=validSpDc'},
      );

      expect(provider.authState, AuthState.authenticated);
      expect(provider.isAuthenticated, isTrue);
    });

    test('transitions to unauthenticated when profile fetch fails', () async {
      final provider = await _makeProvider(
        profileFetcher: (_) async => null, // all attempts return null
      );
      await _waitForInit(provider);

      await expectLater(
        provider.loginComplete(
          'Bearer.token.abc1234567890123456789012345678901234567890',
          {'Cookie': 'sp_dc=validSpDc'},
        ),
        throwsA(isA<Exception>()),
      );

      expect(provider.authState, AuthState.unauthenticated);
    });

    test('throws and stays unauthenticated for a short token', () async {
      final provider = await _makeProvider(
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);

      await expectLater(
        provider.loginComplete('short-token', {'Cookie': 'sp_dc=x'}),
        throwsA(isA<Exception>()),
      );

      expect(provider.authState, AuthState.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. logout
  // ---------------------------------------------------------------------------
  group('AuthProvider.logout — AuthState transitions', () {
    test('transitions to unauthenticated after being authenticated', () async {
      final provider = await _makeProvider(
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_dc=validSpDc'},
      );
      expect(provider.isAuthenticated, isTrue);

      await provider.logout();

      expect(provider.authState, AuthState.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
    });

    test('clears sp_dc from SharedPreferences on logout', () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'storedSpDc',
        'spotify_bearer_token': 'oldToken',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      await _waitForInit(provider);

      await provider.logout();

      expect(prefs.getString('spotify_sp_dc'), isNull);
    });

    test('logout is idempotent — calling twice stays unauthenticated', () async {
      final provider = await _makeProvider();
      await _waitForInit(provider);
      expect(provider.authState, AuthState.unauthenticated);

      await provider.logout();
      await provider.logout();

      expect(provider.authState, AuthState.unauthenticated);
    });
  });

  // ---------------------------------------------------------------------------
  // 3b. loginComplete — x-prefetched-user header (WebView JS injection path)
  // ---------------------------------------------------------------------------
  group('AuthProvider.loginComplete — x-prefetched-user header', () {
    const _validToken =
        'Bearer.token.abc1234567890123456789012345678901234567890';

    Map<String, String> _headersWithUser(Map<String, dynamic> user) => {
          'Cookie': 'sp_dc=validSpDc',
          'x-prefetched-user': jsonEncode(user),
        };

    test('uses prefetched user directly without calling profileFetcher', () async {
      var profileFetcherCalled = false;
      final provider = await _makeProvider(
        profileFetcher: (_) async {
          profileFetcherCalled = true;
          return _fakeUser();
        },
      );
      await _waitForInit(provider);

      await provider.loginComplete(
        _validToken,
        _headersWithUser({
          'id': 'spotify-user-abc123',
          'displayName': 'Test Display Name',
          'imageUrl': null,
          'country': 'AU',
          'followers': 12,
        }),
      );

      expect(provider.authState, AuthState.authenticated);
      expect(provider.currentUser?.displayName, 'Test Display Name');
      expect(profileFetcherCalled, isFalse,
          reason: 'profileFetcher must be skipped when prefetched user is valid');
    });

    test('prefetched user fields are stored correctly on the User model', () async {
      final provider = await _makeProvider();
      await _waitForInit(provider);

      await provider.loginComplete(
        _validToken,
        _headersWithUser({
          'id': 'spotify-user-abc123',
          'displayName': 'Test Display Name',
          'imageUrl': 'https://i.scdn.co/image/abc123',
          'country': 'AU',
          'followers': 42,
        }),
      );

      final user = provider.currentUser!;
      expect(user.id, 'spotify-user-abc123');
      expect(user.displayName, 'Test Display Name');
      expect(user.imageUrl, 'https://i.scdn.co/image/abc123');
      expect(user.country, 'AU');
      expect(user.followers, 42);
    });

    test('falls through to profileFetcher when x-prefetched-user id is empty', () async {
      var profileFetcherCalled = false;
      final provider = await _makeProvider(
        profileFetcher: (_) async {
          profileFetcherCalled = true;
          return _fakeUser();
        },
      );
      await _waitForInit(provider);

      await provider.loginComplete(
        _validToken,
        _headersWithUser({'id': '', 'displayName': 'Should be ignored'}),
      );

      expect(profileFetcherCalled, isTrue,
          reason: 'empty id must fall through to profileFetcher');
      expect(provider.authState, AuthState.authenticated);
    });

    test('falls through to profileFetcher when x-prefetched-user is malformed JSON', () async {
      var profileFetcherCalled = false;
      final provider = await _makeProvider(
        profileFetcher: (_) async {
          profileFetcherCalled = true;
          return _fakeUser();
        },
      );
      await _waitForInit(provider);

      await provider.loginComplete(
        _validToken,
        {
          'Cookie': 'sp_dc=validSpDc',
          'x-prefetched-user': 'not-valid-json',
        },
      );

      expect(profileFetcherCalled, isTrue,
          reason: 'malformed JSON must fall through to profileFetcher');
      expect(provider.authState, AuthState.authenticated);
    });
  });

  // ---------------------------------------------------------------------------
  // 4. refreshIfNeeded
  // ---------------------------------------------------------------------------
  group('AuthProvider.refreshIfNeeded — AuthState transitions', () {
    test('returns false and stays unauthenticated when not authenticated',
        () async {
      final provider = await _makeProvider();
      await _waitForInit(provider);
      // Provider is now unauthenticated (no credentials stored).

      final result = await provider.refreshIfNeeded();

      expect(result, isFalse);
      expect(provider.authState, AuthState.unauthenticated);
    });

    test('returns true and stays authenticated on successful silent refresh',
        () async {
      // Start authenticated via startup silent refresh.
      final provider = await _makeProvider(
        prefsValues: {'spotify_sp_dc': 'validSpDc'},
        tokenFetcher: (_) async =>
            'refreshedToken12345678901234567890123456789012345',
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);
      expect(provider.isAuthenticated, isTrue);

      // refreshIfNeeded should keep us authenticated.
      final result = await provider.refreshIfNeeded();

      expect(result, isTrue);
      expect(provider.authState, AuthState.authenticated);
    });

    test(
        'returns false and transitions to unauthenticated when silent refresh fails',
        () async {
      // Start authenticated, then make the refresh fail.
      final provider = await _makeProvider(
        prefsValues: {'spotify_sp_dc': 'validSpDc'},
        tokenFetcher: (_) async =>
            'refreshedToken12345678901234567890123456789012345',
        profileFetcher: (_) async => _fakeUser(),
      );
      await _waitForInit(provider);
      expect(provider.isAuthenticated, isTrue);

      // Now override the token fetcher to simulate expiry.
      provider.tokenFetchOverride = (_) async => null;

      final result = await provider.refreshIfNeeded();

      expect(result, isFalse);
      expect(provider.authState, AuthState.unauthenticated);
    });
  });
}
