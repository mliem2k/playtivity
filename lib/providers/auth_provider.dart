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

  final List<String> _authEvents = [];
  String? _lastAuthError;

  List<String> get authEvents => List.unmodifiable(_authEvents);
  String? get lastAuthError => _lastAuthError;

  void _addEvent(String msg) {
    final t = DateTime.now();
    final ts = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    _authEvents.add('[$ts] $msg');
    if (_authEvents.length > 30) _authEvents.removeAt(0);
    AppLogger.auth(msg);
    notifyListeners();
  }

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
      _addEvent('Starting auth initialization...');
      _loadStoredData();

      final savedBearerToken = _prefs.getString(_bearerTokenKey);
      final savedHeadersJson = _prefs.getString(_headersKey);
      final savedUserJson = _prefs.getString(_userKey);

      _spDc = _prefs.getString(_spDcKey);

      if (savedBearerToken != null && savedHeadersJson != null) {
        try {
          _bearerToken = savedBearerToken;
          _headers = Map<String, String>.from(json.decode(savedHeadersJson));
          _addEvent('Restored saved token + headers');

          if (savedUserJson != null) {
            // Trust the stored profile — it was fetched correctly via WebView JS
            // injection at login time. Server-side re-fetching is blocked by Spotify's
            // rate limiter (429); a stale token will surface as 401 on the first API
            // call and trigger _trySilentRefresh at that point.
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);

            // One-time migration: scrub placeholder values written by older app
            // versions that hardcoded 'user@spotify.com' and 'US' as fallbacks.
            if (_currentUser!.email == 'user@spotify.com') {
              _currentUser = User(
                id: _currentUser!.id,
                displayName: _currentUser!.displayName,
                email: '',
                imageUrl: _currentUser!.imageUrl,
                followers: _currentUser!.followers,
                country: _currentUser!.country == 'US' ? '' : _currentUser!.country,
              );
              await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
              _addEvent('Scrubbed stale placeholder email/country from stored profile');
            }

            _addEvent('Restored: ${_currentUser!.displayName}');
          } else {
            // Token present but no user — try silent refresh to obtain profile.
            _addEvent('Token without user — trying silent refresh...');
            final didRefresh = await _trySilentRefresh();
            if (!didRefresh) {
              await _clearStoredData();
            }
          }
        } catch (e) {
          _addEvent('Restore error — trying silent refresh');
          _lastAuthError = 'Restore: $e';
          final didRefresh = await _trySilentRefresh();
          if (!didRefresh) {
            await _clearStoredData();
          }
        }
      } else if (_spDc != null) {
        _addEvent('No stored token — silent refresh with sp_dc...');
        await _trySilentRefresh();
      } else {
        _addEvent('No credentials found');
      }

      _addEvent('Init complete — token:${_bearerToken != null} user:${_currentUser?.displayName ?? "none"}');

    } catch (e) {
      _lastAuthError = 'Init error: $e';
      AppLogger.error('Error during auth initialization', e);
    } finally {
      _authState = _bearerToken != null && _currentUser != null
          ? AuthState.authenticated
          : AuthState.unauthenticated;
      _addEvent('State -> ${_authState.name}');
      notifyListeners();
    }
  }

  void _loadStoredData() {
    _prefs.remove('spotify_sp_dc_cookie');
    _prefs.remove('spotify_access_token');
    _prefs.remove('spotify_refresh_token');
    _prefs.remove('spotify_token_expiry');
  }

  Future<void> loginComplete(String bearerToken, Map<String, String> headers) async {
    _authState = AuthState.loading;
    _lastAuthError = null;
    notifyListeners();

    try {
      _addEvent('loginComplete: token len=${bearerToken.length} headers=${headers.keys.join(",")}');

      if (bearerToken.isEmpty || bearerToken.length < 50) {
        throw Exception('Invalid bearer token (len=${bearerToken.length})');
      }

      final cookieHeader = headers['Cookie'] ?? '';
      final extractedSpDc = SpotifyTokenService.extractSpDc(cookieHeader);
      if (extractedSpDc != null && extractedSpDc.isNotEmpty) {
        _spDc = extractedSpDc;
        _addEvent('sp_dc extracted (len=${extractedSpDc.length})');
      } else {
        _addEvent('WARNING: sp_dc not found in headers');
      }

      _bearerToken = bearerToken;
      _headers = headers;

      User? userProfile;

      // WebView pre-fetched profile via JS injection (avoids server-side rate limit).
      final prefetchedJson = headers['x-prefetched-user'];
      if (prefetchedJson != null) {
        try {
          final m = json.decode(prefetchedJson) as Map<String, dynamic>;
          final id = m['id'] as String? ?? '';
          if (id.isNotEmpty) {
            userProfile = User(
              id: id,
              displayName: m['displayName'] as String? ?? id,
              email: m['email'] as String? ?? '',
              imageUrl: m['imageUrl'] as String?,
              followers: m['followers'] as int? ?? 0,
              country: m['country'] as String? ?? '',
            );
            _addEvent('Profile from WebView JS: ${userProfile.displayName}');
          }
        } catch (e) {
          _addEvent('Failed to parse prefetched user: $e');
        }
      }

      // Server-side fallback — only used when WebView JS injection failed.
      // api.spotify.com/v1/me is rate-limited (429) for web-player tokens from
      // server-side Dart, so we only try once to fail fast rather than spinning
      // for 75+ seconds across 5 retries.
      if (userProfile == null) {
        final profileFetcher = userProfileFetchOverride ??
            _buddyService.getCurrentUserProfileWithToken;
        try {
          _addEvent('Profile fetch (server-side fallback)...');
          userProfile = await profileFetcher(_bearerToken!);
          if (userProfile != null) {
            _addEvent('Profile loaded: ${userProfile.displayName}');
          }
        } catch (e) {
          _lastAuthError = '$e';
          _addEvent('Server-side profile fetch failed: $e');
        }
      }

      if (userProfile == null) {
        throw Exception('Could not load profile. Please try logging in again.');
      }

      _currentUser = userProfile;
      await _saveStoredData();

      _authState = AuthState.authenticated;
      _addEvent('loginComplete SUCCESS: ${_currentUser!.displayName}');

    } catch (e) {
      _lastAuthError = 'loginComplete: $e';
      _addEvent('loginComplete FAILED: $e');
      AppLogger.error('Error in loginComplete', e);

      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      await _clearStoredData();

      _authState = AuthState.unauthenticated;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _saveStoredData() async {
    if (_bearerToken != null) await _prefs.setString(_bearerTokenKey, _bearerToken!);
    if (_headers != null) await _prefs.setString(_headersKey, json.encode(_headers!));
    if (_currentUser != null) await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
    if (_spDc != null) await _prefs.setString(_spDcKey, _spDc!);
    _addEvent('Auth data saved');
  }

  Future<void> _clearStoredData() async {
    await _prefs.remove(_bearerTokenKey);
    await _prefs.remove(_headersKey);
    await _prefs.remove(_userKey);
    // sp_dc intentionally NOT removed — survives token expiry for silent refresh.
    _bearerToken = null;
    _headers = null;
    _currentUser = null;
    _addEvent('Auth data cleared');
  }

  Future<void> logout() async {
    _addEvent('Logout requested');
    await _clearStoredData();
    await _prefs.remove(_spDcKey);
    _spDc = null;
    _buddyService.clearActivityCache();
    _authState = AuthState.unauthenticated;
    _addEvent('Logged out');
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
      _addEvent('Silent refresh skipped: no sp_dc');
      return false;
    }

    _addEvent('Silent refresh starting...');
    final fetcher = tokenFetchOverride ?? SpotifyTokenService.fetchBearerToken;
    final newToken = await fetcher(spDc);
    if (newToken == null || newToken.isEmpty) {
      _addEvent('Silent refresh: no token returned');
      return false;
    }

    _spDc = spDc;
    _bearerToken = newToken;
    _headers = SpotifyTokenService.headersFromSpDc(spDc);

    // Only fetch profile when we don't already have one. Existing profile was
    // obtained via WebView JS injection and is correct; server-side /v1/me is
    // rate-limited (429) and spclient/profile/me returns a different account.
    if (_currentUser == null) {
      try {
        final profileFetcher = userProfileFetchOverride ??
            _buddyService.getCurrentUserProfileWithToken;
        _currentUser = await profileFetcher(newToken);
      } catch (e) {
        _addEvent('Silent refresh: profile fetch failed: $e');
        _lastAuthError = 'Silent refresh profile: $e';
      }

      if (_currentUser == null) {
        _addEvent('Silent refresh: no profile — aborting');
        _bearerToken = null;
        _headers = null;
        return false;
      }
    }

    await _saveStoredData();
    _addEvent('Silent refresh OK: ${_currentUser!.displayName}');
    notifyListeners();
    return true;
  }
}
