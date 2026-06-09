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

/// Builds an [AuthProvider] with real SharedPreferences but injectable
/// network seams so no real HTTP calls are made.
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

/// Waits for [AuthProvider.isInitialized] to become true.
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
  group('AuthProvider.loginComplete — sp_dc extraction', () {
    test('stores sp_dc when Cookie header contains it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      // Override profile fetch so loginComplete doesn't make real calls
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      // Wait for init before calling loginComplete (mirrors real app flow —
      // the WebView is never shown until init finishes)
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {
          'Cookie':
              'sp_t=trackVal; sp_dc=mySecretSpDc; sp_key=keyVal',
        },
      );

      expect(prefs.getString('spotify_sp_dc'), 'mySecretSpDc');
    });

    test('does not crash when Cookie header is missing sp_dc', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_t=trackVal; sp_key=keyVal'},
      );

      expect(prefs.getString('spotify_sp_dc'), isNull);
    });
  });

  group('AuthProvider.loginComplete — full WebView auth flow', () {
    test('sets isAuthenticated to true after valid token and profile fetch', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_dc=validSpDc; sp_t=trackVal'},
      );

      expect(provider.isAuthenticated, isTrue);
    });

    test('sets currentUser after successful loginComplete', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      await provider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_dc=validSpDc'},
      );

      expect(provider.currentUser, isNotNull);
      expect(provider.currentUser!.id, 'user_123');
    });

    test('persists bearer token to SharedPreferences after loginComplete', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      const token = 'Bearer.token.abc1234567890123456789012345678901234567890';
      await provider.loginComplete(
        token,
        {'Cookie': 'sp_dc=validSpDc'},
      );

      expect(prefs.getString('spotify_bearer_token'), token);
    });

    test('throws when bearer token is too short (< 50 chars)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      await expectLater(
        provider.loginComplete('short-token', {'Cookie': 'sp_dc=x'}),
        throwsA(isA<Exception>()),
      );
      expect(provider.isAuthenticated, isFalse);
    });

    test('throws and stays unauthenticated when profile fetch always returns null', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => null;
      await _waitForInit(provider);

      // loginComplete rethrows when all profile fetch attempts return null
      await expectLater(
        provider.loginComplete(
          'Bearer.token.abc1234567890123456789012345678901234567890',
          {'Cookie': 'sp_dc=validSpDc'},
        ),
        throwsA(isA<Exception>()),
      );

      expect(provider.isAuthenticated, isFalse);
      expect(provider.currentUser, isNull);
    });

    test('stores bearer token in bearerToken getter after successful auth', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      const token = 'Bearer.token.abc1234567890123456789012345678901234567890';
      await provider.loginComplete(token, {'Cookie': 'sp_dc=x'});

      expect(provider.bearerToken, token);
    });
  });

  group('AuthProvider.logout — sp_dc cleared', () {
    test('removes sp_dc from SharedPreferences on logout', () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'oldSpDcValue',
        'spotify_bearer_token': 'oldToken',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      await _waitForInit(provider);

      await provider.logout();

      expect(prefs.getString('spotify_sp_dc'), isNull);
    });
  });

  group('AuthProvider.refreshIfNeeded — silent refresh', () {
    test('returns true and sets isAuthenticated when token fetch succeeds',
        () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'validSpDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.tokenFetchOverride = (_) async => 'newBearerToken12345678901234567890123456789012345';
      provider.userProfileFetchOverride = (_) async => _fakeUser();
      await _waitForInit(provider);

      final result = await provider.refreshIfNeeded();

      expect(result, isTrue);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.bearerToken, 'newBearerToken12345678901234567890123456789012345');
    });

    test('returns false when no sp_dc is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      await _waitForInit(provider);

      final result = await provider.refreshIfNeeded();

      expect(result, isFalse);
      expect(provider.isAuthenticated, isFalse);
    });

    test('returns false when token fetch returns null', () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'expiredSpDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.tokenFetchOverride = (_) async => null;
      await _waitForInit(provider);

      final result = await provider.refreshIfNeeded();

      expect(result, isFalse);
      expect(provider.isAuthenticated, isFalse);
    });

    test('returns false when user profile fetch fails after token fetch',
        () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'validSpDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.tokenFetchOverride =
          (_) async => 'freshToken12345678901234567890123456789012345';
      provider.userProfileFetchOverride = (_) async => null; // profile failed
      await _waitForInit(provider);

      final result = await provider.refreshIfNeeded();

      expect(result, isFalse);
      expect(provider.isAuthenticated, isFalse);
    });
  });

  group('AuthProvider._initializeAuth — silent refresh on startup', () {
    test('silently refreshes and authenticates when stored token is absent but sp_dc exists',
        () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'storedSpDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.tokenFetchOverride =
          (_) async => 'refreshedToken1234567890123456789012345678901';
      provider.userProfileFetchOverride = (_) async => _fakeUser();

      await _waitForInit(provider);

      expect(provider.isAuthenticated, isTrue);
      expect(provider.currentUser, isNotNull);
      expect(provider.currentUser!.id, 'user_123');
    });

    test('stays unauthenticated when no token and no sp_dc', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      await _waitForInit(provider);

      expect(provider.isAuthenticated, isFalse);
      expect(provider.currentUser, isNull);
    });

    test('persists new token to SharedPreferences after successful silent refresh',
        () async {
      SharedPreferences.setMockInitialValues({
        'spotify_sp_dc': 'storedSpDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      provider.tokenFetchOverride =
          (_) async => 'persistedToken12345678901234567890123456789';
      provider.userProfileFetchOverride = (_) async => _fakeUser();

      await _waitForInit(provider);

      expect(prefs.getString('spotify_bearer_token'), 'persistedToken12345678901234567890123456789');
      // User profile should also be persisted
      final savedUser = json.decode(prefs.getString('spotify_user')!);
      expect(savedUser['id'], 'user_123');
    });

    test('sp_dc is NOT removed from SharedPreferences when token validation fails',
        () async {
      // sp_dc should survive token expiry so next refreshIfNeeded can use it
      final savedUser = json.encode(TestFixtures.userJson());
      SharedPreferences.setMockInitialValues({
        'spotify_bearer_token': 'expiredToken',
        'spotify_headers': json.encode({'Cookie': 'sp_dc=myDc'}),
        'spotify_user': savedUser,
        'spotify_sp_dc': 'myDc',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = AuthProvider(prefs);
      // Token validation fails, silent refresh also fails
      provider.tokenFetchOverride = (_) async => null;
      provider.userProfileFetchOverride = (_) async => null;

      await _waitForInit(provider);

      // sp_dc must still be in prefs so a future refreshIfNeeded can try again
      expect(prefs.getString('spotify_sp_dc'), 'myDc');
      expect(provider.isAuthenticated, isFalse);
    });
  });
}
