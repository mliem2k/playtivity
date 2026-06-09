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
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);
            _addEvent('Restored user: ${_currentUser!.displayName}');

            try {
              _addEvent('Validating token...');
              final testUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (testUser != null && testUser.id == _currentUser!.id) {
                _addEvent('Token valid');
              } else {
                _addEvent('Token invalid — trying silent refresh');
                final didRefresh = await _trySilentRefresh();
                if (!didRefresh) {
                  await _clearStoredData();
                }
              }
            } catch (e) {
              _addEvent('Validation error — trying silent refresh');
              _lastAuthError = 'Validation: $e';
              final didRefresh = await _trySilentRefresh();
              if (!didRefresh) {
                await _clearStoredData();
              }
            }
          } else {
            _addEvent('Fetching user profile...');
            try {
              _currentUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (_currentUser != null) {
                _addEvent('User profile loaded: ${_currentUser!.displayName}');
                await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
              } else {
                _addEvent('Profile fetch returned null — trying silent refresh');
                final didRefresh = await _trySilentRefresh();
                if (!didRefresh) {
                  await _clearStoredData();
                }
              }
            } catch (e) {
              _addEvent('Profile fetch error — trying silent refresh');
              _lastAuthError = 'Profile fetch: $e';
              final didRefresh = await _trySilentRefresh();
              if (!didRefresh) {
                await _clearStoredData();
              }
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

      if (userProfileFetchOverride == null) {
        // Brief pause to let the token propagate before the first API call.
        _addEvent('Waiting 500ms before profile fetch...');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      User? userProfile;
      final profileFetcher = userProfileFetchOverride ??
          _buddyService.getCurrentUserProfileWithToken;

      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          _addEvent('Profile fetch attempt $attempt/5...');
          userProfile = await profileFetcher(_bearerToken!);
          if (userProfile != null) {
            _addEvent('Profile loaded: ${userProfile.displayName} (attempt $attempt)');
            break;
          }
          _addEvent('Attempt $attempt returned null');
        } catch (e) {
          _lastAuthError = 'Attempt $attempt: $e';
          _addEvent('Attempt $attempt failed: $e');
          if (attempt < 5) {
            final errorStr = e.toString().toLowerCase();
            final isRateLimit = errorStr.contains('429') || errorStr.contains('rate limit');
            final delayMs = isRateLimit
                ? 5000 * (1 << (attempt - 1))
                : (attempt <= 2 ? 1000 : 2000);
            _addEvent('Retry in ${delayMs}ms${isRateLimit ? " (rate limit)" : ""}');
            await Future.delayed(Duration(milliseconds: delayMs));
          }
        }
      }

      if (userProfile == null) {
        throw Exception('Profile fetch failed after 5 attempts');
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

    try {
      final profileFetcher = userProfileFetchOverride ??
          _buddyService.getCurrentUserProfileWithToken;
      _currentUser = await profileFetcher(newToken);
    } catch (e) {
      _addEvent('Silent refresh: profile fetch failed: $e');
      _lastAuthError = 'Silent refresh profile: $e';
    }

    if (_currentUser == null) {
      _addEvent('Silent refresh: profile null — aborting');
      _bearerToken = null;
      _headers = null;
      return false;
    }

    await _saveStoredData();
    _addEvent('Silent refresh OK: ${_currentUser!.displayName}');
    notifyListeners();
    return true;
  }
}
