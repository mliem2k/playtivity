import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../services/spotify_token_service.dart';
import '../services/app_logger.dart';

enum AuthState { uninitialized, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  static const String _bearerTokenKey = 'spotify_bearer_token';
  static const String _headersKey = 'spotify_headers';
  static const String _userKey = 'spotify_user';
  static const String _spDcKey = 'spotify_sp_dc';

  final SharedPreferences _prefs;
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();

  String? _bearerToken;
  Map<String, String>? _headers;
  User? _currentUser;
  String? _spDc;
  AuthState _authState = AuthState.uninitialized;

  /// Injectable token fetcher — override in tests to avoid real network calls.
  @visibleForTesting
  Future<String?> Function(String spDc)? tokenFetchOverride;

  /// Injectable user-profile fetcher — override in tests.
  @visibleForTesting
  Future<User?> Function(String bearerToken)? userProfileFetchOverride;

  AuthProvider(this._prefs) {
    // Scheduled as a microtask so callers (including tests) can set overrides
    // on the instance before initialization reads them.
    Future.microtask(_initializeAuth);
  }

  AuthState get authState => _authState;
  bool get isAuthenticated => _authState == AuthState.authenticated;
  bool get isLoading => _authState == AuthState.loading;
  bool get isInitialized => _authState != AuthState.uninitialized;
  User? get currentUser => _currentUser;
  String? get bearerToken => _bearerToken;
  Map<String, String>? get headers => _headers;

  Future<void> _initializeAuth() async {
    _authState = AuthState.loading;
    notifyListeners();

    try {
      AppLogger.auth('Starting authentication initialization...');
      _loadStoredData();

      // Load saved Bearer token and headers if available
      final savedBearerToken = _prefs.getString(_bearerTokenKey);
      final savedHeadersJson = _prefs.getString(_headersKey);
      final savedUserJson = _prefs.getString(_userKey);

      // Restore sp_dc regardless of whether a token is present
      _spDc = _prefs.getString(_spDcKey);

      if (savedBearerToken != null && savedHeadersJson != null) {
        try {
          _bearerToken = savedBearerToken;
          _headers = Map<String, String>.from(json.decode(savedHeadersJson));
          AppLogger.auth('Restored saved Bearer token and headers');

          // Try to load saved user profile
          if (savedUserJson != null) {
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);
            AppLogger.auth('Restored saved user profile: ${_currentUser!.displayName}');

            // Validate the restored authentication
            try {
              AppLogger.auth('Validating restored authentication...');
              final testUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (testUser != null && testUser.id == _currentUser!.id) {
                AppLogger.auth('Restored authentication is valid');
              } else {
                AppLogger.warning('Restored token invalid - attempting silent refresh');
                final didRefresh = await _trySilentRefresh();
                if (!didRefresh) {
                  await _clearStoredData();
                }
              }
            } catch (e) {
              AppLogger.warning('Authentication validation failed: $e - attempting silent refresh');
              final didRefresh = await _trySilentRefresh();
              if (!didRefresh) {
                await _clearStoredData();
              }
            }
          } else {
            // Fetch user profile using Bearer token
            AppLogger.auth('Fetching user profile with Bearer token...');
            try {
              _currentUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (_currentUser != null) {
                AppLogger.auth('Successfully loaded user profile: ${_currentUser!.displayName}');
                await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
              } else {
                AppLogger.warning('Failed to load user profile - attempting silent refresh');
                final didRefresh = await _trySilentRefresh();
                if (!didRefresh) {
                  await _clearStoredData();
                }
              }
            } catch (e) {
              AppLogger.warning('Failed to load user profile: $e - attempting silent refresh');
              final didRefresh = await _trySilentRefresh();
              if (!didRefresh) {
                await _clearStoredData();
              }
            }
          }
        } catch (e) {
          AppLogger.warning('Failed to restore saved authentication: $e');
          final didRefresh = await _trySilentRefresh();
          if (!didRefresh) {
            await _clearStoredData();
          }
        }
      } else if (_spDc != null) {
        // No stored Bearer token but we have sp_dc — try silent refresh
        AppLogger.auth('No stored token found, attempting silent refresh with sp_dc...');
        await _trySilentRefresh();
      }

      AppLogger.auth('Initialization complete. Final state:');
      AppLogger.auth('   - Has Bearer token: ${_bearerToken != null}');
      AppLogger.auth('   - Has user: ${_currentUser != null}');
      AppLogger.auth('   - User name: ${_currentUser?.displayName ?? 'none'}');

    } catch (e) {
      AppLogger.error('Error during auth initialization', e);
    } finally {
      _authState = _bearerToken != null && _currentUser != null
          ? AuthState.authenticated
          : AuthState.unauthenticated;
      AppLogger.auth('AuthProvider initialization completed');
      notifyListeners();
    }
  }

  void _loadStoredData() {
    // Clean up old data during migration
    AppLogger.auth('Cleaning up old authentication data...');
    _prefs.remove('spotify_sp_dc_cookie');
    _prefs.remove('spotify_access_token');
    _prefs.remove('spotify_refresh_token');
    _prefs.remove('spotify_token_expiry');

    AppLogger.auth('Old authentication data cleaned up');
  }

  Future<void> loginComplete(String bearerToken, Map<String, String> headers) async {
    _authState = AuthState.loading;
    notifyListeners();

    try {
      AppLogger.auth('loginComplete called with:');
      AppLogger.auth('   - bearerToken: "${bearerToken.length > 20 ? bearerToken.substring(0, 20) : bearerToken}..." (length: ${bearerToken.length})');
      AppLogger.auth('   - headers: ${headers.keys.join(', ')}');
      AppLogger.auth('   - headers Cookie exists: ${headers.containsKey('Cookie')}');
      final cookiePreview = headers['Cookie'];
      AppLogger.auth('   - headers Cookie value: ${cookiePreview == null ? 'null' : (cookiePreview.length > 100 ? cookiePreview.substring(0, 100) : cookiePreview)}...');
      AppLogger.auth('   - headers Cookie length: ${headers['Cookie']?.length ?? 0}');

      AppLogger.auth('Processing Bearer token authentication...');

      // Validate the bearer token
      if (bearerToken.isEmpty || bearerToken.length < 50) {
        throw Exception('Invalid bearer token provided');
      }

      // Extract and persist sp_dc for future silent refreshes
      final cookieHeader = headers['Cookie'] ?? '';
      final extractedSpDc = SpotifyTokenService.extractSpDc(cookieHeader);
      if (extractedSpDc != null && extractedSpDc.isNotEmpty) {
        _spDc = extractedSpDc;
        AppLogger.auth('sp_dc extracted and stored for silent refresh');
      }

      // Store Bearer token and headers
      _bearerToken = bearerToken;
      _headers = headers;

      // Fetch user profile using Bearer token with retry logic
      AppLogger.auth('Fetching user profile with Bearer token...');

      // Skip delay in tests (override present means we're in a controlled environment)
      if (userProfileFetchOverride == null) {
        AppLogger.auth('Waiting 3 seconds before first API call to avoid rate limiting...');
        await Future.delayed(const Duration(seconds: 3));
      }

      User? userProfile;

      final profileFetcher = userProfileFetchOverride ??
          _buddyService.getCurrentUserProfileWithToken;

      // Try multiple times to get user profile (sometimes the token needs a moment to propagate)
      // Extended retry logic for long idle scenarios
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          userProfile = await profileFetcher(_bearerToken!);
          if (userProfile != null) {
            AppLogger.auth('Successfully loaded user profile on attempt $attempt: ${userProfile.displayName}');
            break;
          }
        } catch (e) {
          AppLogger.warning('Failed to load user profile on attempt $attempt: $e');
          if (attempt < 5) {
            // Check if this is a rate limit error (429)
            final errorStr = e.toString().toLowerCase();
            final isRateLimitError = errorStr.contains('429') || errorStr.contains('rate limit');

            int delayMs;
            if (isRateLimitError) {
              // Use longer delays for rate limit errors: 5s, 10s, 20s, 40s
              delayMs = 5000 * (1 << (attempt - 1)); // 5000, 10000, 20000, 40000
              AppLogger.auth('Rate limit detected (429), backing off for ${delayMs}ms...');
            } else {
              // Use shorter delays for other errors: 1s, 2s
              delayMs = attempt <= 2 ? 1000 : 2000;
              AppLogger.auth('Retrying in ${delayMs}ms...');
            }

            await Future.delayed(Duration(milliseconds: delayMs));
          }
        }
      }

      if (userProfile == null) {
        throw Exception('Failed to load user profile after multiple attempts');
      }

      _currentUser = userProfile;

      // Save the data to persistent storage
      await _saveStoredData();

      AppLogger.auth('Bearer token authentication complete - token and user profile stored');

      _authState = AuthState.authenticated;
      AppLogger.auth('Authentication flow completed successfully');

    } catch (e) {
      AppLogger.error('Error in loginComplete', e);

      // Clean up on error
      _bearerToken = null;
      _headers = null;
      _currentUser = null;

      // Ensure we clear any potentially corrupted stored data
      await _clearStoredData();

      _authState = AuthState.unauthenticated;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  // Keep handleAuthComplete as an alias so existing tests continue to pass
  // until they are updated in Task 8.
  Future<void> handleAuthComplete(String bearerToken, Map<String, String> headers) =>
      loginComplete(bearerToken, headers);

  Future<void> _saveStoredData() async {
    AppLogger.auth('Saving auth data to storage...');

    if (_bearerToken != null) {
      await _prefs.setString(_bearerTokenKey, _bearerToken!);
      AppLogger.auth('Bearer token saved successfully');
    }

    if (_headers != null) {
      await _prefs.setString(_headersKey, json.encode(_headers!));
      AppLogger.auth('Headers saved successfully');
    }

    if (_currentUser != null) {
      await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
      AppLogger.auth('User profile saved successfully');
    }

    if (_spDc != null) {
      await _prefs.setString(_spDcKey, _spDc!);
      AppLogger.auth('sp_dc saved successfully');
    }

    AppLogger.auth('Auth data saved successfully');
  }

  Future<void> _clearStoredData() async {
    AppLogger.auth('Clearing stored auth data...');

    await _prefs.remove(_bearerTokenKey);
    await _prefs.remove(_headersKey);
    await _prefs.remove(_userKey);
    // sp_dc is intentionally NOT removed here — it survives token expiry
    // and allows silent refresh on next session. Only logout clears it.

    _bearerToken = null;
    _headers = null;
    _currentUser = null;

    AppLogger.auth('Stored auth data cleared');
  }

  Future<void> logout() async {
    AppLogger.auth('Logging out and clearing all auth data...');
    await _clearStoredData();
    await _prefs.remove(_spDcKey);
    _spDc = null;
    _buddyService.clearActivityCache();
    _authState = AuthState.unauthenticated;
    notifyListeners();
  }

  /// Refresh the token if currently authenticated. Returns false if not
  /// authenticated or if the silent refresh fails.
  Future<bool> refreshIfNeeded() async {
    if (_authState != AuthState.authenticated) return false;
    final ok = await _trySilentRefresh();
    if (!ok) {
      _authState = AuthState.unauthenticated;
      notifyListeners();
    }
    return ok;
  }

  /// Attempts to silently obtain a fresh Bearer token using the stored sp_dc.
  /// Updates internal state and storage on success. Returns true on success.
  Future<bool> _trySilentRefresh() async {
    final spDc = _spDc ?? _prefs.getString(_spDcKey);
    if (spDc == null || spDc.isEmpty) {
      AppLogger.auth('No sp_dc available for silent refresh');
      return false;
    }

    AppLogger.auth('Attempting silent token refresh...');
    final fetcher = tokenFetchOverride ?? SpotifyTokenService.fetchBearerToken;
    final newToken = await fetcher(spDc);
    if (newToken == null || newToken.isEmpty) {
      AppLogger.warning('Silent token refresh returned no token');
      return false;
    }

    _spDc = spDc;
    _bearerToken = newToken;
    _headers = SpotifyTokenService.headersFromSpDc(spDc);

    try {
      final profileFetcher = userProfileFetchOverride ??
          _buddyService.getCurrentUserProfileWithToken;
      _currentUser = await profileFetcher(newToken);
    } catch (e) {
      AppLogger.warning('Failed to fetch user profile after silent refresh: $e');
    }

    if (_currentUser == null) {
      AppLogger.warning('Silent refresh produced token but could not fetch user profile');
      _bearerToken = null;
      _headers = null;
      return false;
    }

    await _saveStoredData();
    AppLogger.auth('Silent refresh complete: ${_currentUser!.displayName}');
    notifyListeners();
    return true;
  }
}
