import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../services/spotify_service.dart';
import '../services/spotify_token_service.dart';
import '../services/app_logger.dart';
import 'spotify_provider.dart';

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
  bool _isLoading = false;
  bool _isInitialized = false;

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

  bool get isAuthenticated {
    if (!_isInitialized) {
      AppLogger.auth('isAuthenticated: false (not initialized)');
      return false;
    }
    return _bearerToken != null && _currentUser != null;
  }
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  User? get currentUser => _currentUser;
  String? get bearerToken => _bearerToken;
  Map<String, String>? get headers => _headers;

  Future<void> _initializeAuth() async {
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
      _isInitialized = true;
      AppLogger.auth('AuthProvider initialization completed');
      notifyListeners();
      
      // Additional notification after a short delay to ensure UI updates
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!_isLoading) { // Only notify if not in an active auth flow
          notifyListeners();
        }
      });
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

  void startLogin() {
    _isLoading = true;
    notifyListeners();
  }

  void cancelLogin() {
    _isLoading = false;
    notifyListeners();
  }

  Future<void> handleAuthComplete(String bearerToken, Map<String, String> headers) async {
    try {
      AppLogger.auth('handleAuthComplete called with:');
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
      
      // Ensure initialization is complete and clear loading state
      _isInitialized = true;
      _isLoading = false;
      
      AppLogger.auth('AuthProvider state after completion:');
      AppLogger.auth('   - isAuthenticated: $isAuthenticated');
      AppLogger.auth('   - isInitialized: $_isInitialized');
      AppLogger.auth('   - isLoading: $_isLoading');
      AppLogger.auth('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
      
      // Notify listeners once with the final state
      notifyListeners();
      
      // Simplified verification - just check that we have the basic requirements
      // Removed complex retry logic that was causing race conditions
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Final verification
      final hasToken = _bearerToken != null && _bearerToken!.isNotEmpty;
      final hasUser = _currentUser != null;
      final isInitComplete = _isInitialized;

      AppLogger.auth('Final verification check:');
      AppLogger.auth('   - hasToken: $hasToken');
      AppLogger.auth('   - hasUser: $hasUser');
      AppLogger.auth('   - isInitialized: $isInitComplete');

      if (!hasToken || !hasUser || !isInitComplete) {
        throw Exception('Authentication verification failed after completion - Token: $hasToken, User: $hasUser, Init: $isInitComplete');
      }

      AppLogger.auth('Authentication flow completed successfully');
      
    } catch (e) {
      AppLogger.error('Error in handleAuthComplete', e);
      
      // Clean up on error
      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      _isLoading = false;
      
      // Ensure we clear any potentially corrupted stored data
      await _clearStoredData();
      
      notifyListeners();
      rethrow;
    }
  }

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
    
    // Set loading state to prevent race conditions
    _isLoading = true;
    notifyListeners();
    
    await _clearStoredData();
    await _prefs.remove(_spDcKey);
    _spDc = null;

    // Clean up buddy service activity cache
    _buddyService.clearActivityCache();
    
    // Ensure all state is properly reset
    _isLoading = false;
    
    AppLogger.auth('All auth data cleared successfully');
    AppLogger.auth('Post-logout state:');
    AppLogger.auth('   - isAuthenticated: $isAuthenticated');
    AppLogger.auth('   - isInitialized: $_isInitialized');
    AppLogger.auth('   - isLoading: $_isLoading');
    AppLogger.auth('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
    
    // Force multiple notifications to ensure UI updates
    notifyListeners();
    
    // Additional notification after a short delay to handle race conditions
    await Future.delayed(const Duration(milliseconds: 50));
    notifyListeners();
    
    // Final notification to ensure all consumers are updated
    await Future.delayed(const Duration(milliseconds: 100));
    notifyListeners();
  }

  /// Re-authenticate when token expires or is invalid.
  /// Tries silent refresh first; returns false only if WebView login is required.
  Future<bool> reAuthenticate() async {
    AppLogger.auth('Re-authentication requested...');

    try {
      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      _buddyService.clearActivityCache();

      _isLoading = true;
      notifyListeners();

      final didRefresh = await _trySilentRefresh();
      if (didRefresh) {
        AppLogger.auth('Silent re-authentication succeeded');
        return true;
      }

      AppLogger.warning('Silent refresh failed — WebView login required');
      return false;
    } catch (e) {
      AppLogger.error('Error during re-authentication', e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if token needs refresh and handle it
  Future<bool> ensureValidAuthentication() async {
    if (!isAuthenticated) {
      AppLogger.warning('No valid authentication, re-authentication needed');
      return false;
    }
    
    // Test if current token is still valid by making a simple API call
    try {
      await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
      AppLogger.auth('Current authentication is valid');
      return true;
    } catch (e) {
      try {
        // Fallback to SpotifyService
        final spotifyService = SpotifyService();
        await spotifyService.getCurrentUser(_bearerToken!);
        AppLogger.auth('Current authentication is valid (via fallback)');
        return true;
      } catch (fallbackError) {
        AppLogger.warning('Current authentication invalid: $e');
        AppLogger.warning('Fallback also failed: $fallbackError');
        AppLogger.auth('Attempting re-authentication...');
        return await reAuthenticate();
      }
    }
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

  /// Debug method to print current authentication state
  void debugAuthState() {
    AppLogger.auth('=== AuthProvider Debug State ===');
    AppLogger.auth('   - isInitialized: $_isInitialized');
    AppLogger.auth('   - isLoading: $_isLoading');
    AppLogger.auth('   - isAuthenticated: $isAuthenticated');
    AppLogger.auth('   - hasBearerToken: ${_bearerToken != null}');
    AppLogger.auth('   - bearerToken: ${_bearerToken == null ? 'null' : (_bearerToken!.length > 20 ? _bearerToken!.substring(0, 20) : _bearerToken!)}...');
    AppLogger.auth('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
    AppLogger.auth('   - currentUserId: ${_currentUser?.id ?? 'null'}');
    AppLogger.auth('   - userEmail: ${_currentUser?.email ?? 'null'}');
    AppLogger.auth('=================================');
  }

  /// Global method to reset authentication state after 401 errors
  /// This can be called from anywhere in the app to recover from auth failures
  Future<void> resetAuthenticationState() async {
    AppLogger.auth('Resetting authentication state after error...');
    
    try {
      // Clear all stored authentication data
      await _clearStoredData();
      
      // Clear buddy service activity cache
      _buddyService.clearActivityCache();
      
      // Reset internal state variables
      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      _isLoading = false;
      // Keep _isInitialized = true so the app doesn't show loading screen
      
      AppLogger.auth('Authentication state reset completed');
      AppLogger.auth('Post-reset state:');
      AppLogger.auth('   - isAuthenticated: $isAuthenticated');
      AppLogger.auth('   - isInitialized: $_isInitialized');
      AppLogger.auth('   - bearerToken: ${_bearerToken ?? 'null'}');
      AppLogger.auth('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
      
      // Notify all listeners that auth state has changed
      notifyListeners();
      
      // Additional notification to ensure all UI components update
      await Future.delayed(const Duration(milliseconds: 50));
      notifyListeners();
      
    } catch (e) {
      AppLogger.error('Error during authentication state reset', e);
      // Even if there's an error, ensure we're in a clean state
      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Force logout with complete state reset and navigation
  Future<void> forceLogoutAndNavigate(BuildContext context) async {
    if (!context.mounted) return;
    
    AppLogger.auth('Force logout initiated...');
    
    // Set loading state
    _isLoading = true;
    notifyListeners();
    
    // Clear SpotifyProvider state first
    try {
      final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
      spotifyProvider.clearError();
      spotifyProvider.clearAuthError();
      AppLogger.auth('Cleared SpotifyProvider cached state');
    } catch (e) {
      AppLogger.warning('Could not clear SpotifyProvider state: $e');
    }
    
    // Clear all stored data
    await _clearStoredData();
    
    // Reset all state variables
    _bearerToken = null;
    _headers = null;
    _currentUser = null;
    
    AppLogger.auth('All auth data cleared, forcing navigation...');
    
    // Force multiple notifications
    notifyListeners();
    
    // Only navigate if the context is still valid
    if (context.mounted) {
      // Navigate to login screen and clear all routes
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      AppLogger.auth('Navigation completed to login screen');
    }
    
    // Clear loading state
    _isLoading = false;
    notifyListeners();
  }

  /// Verify authentication state and refresh if needed
  /// This can be called when app resumes or when we need to verify auth status
  Future<bool> verifyAndRefreshAuth() async {
    AppLogger.auth('Verifying and refreshing authentication state...');
    
    if (!_isInitialized) {
      AppLogger.warning('Auth not initialized yet, skipping verification');
      return false;
    }
    
    // If we don't have basic auth data, we're not authenticated
    if (_bearerToken == null || _currentUser == null) {
      AppLogger.warning('Missing basic auth data (token or user)');
      return false;
    }
    
    try {
      // Test the current token by making an API call
      AppLogger.auth('Testing current authentication with API call...');
      final testUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
      
      if (testUser != null && testUser.id == _currentUser!.id) {
        AppLogger.auth('Authentication verified successfully');

        _currentUser = testUser;
        await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
        notifyListeners();

        return true;
      } else {
        AppLogger.warning('Authentication test failed - attempting silent refresh');
        final didRefresh = await _trySilentRefresh();
        if (!didRefresh) {
          await _clearStoredData();
          notifyListeners();
        }
        return didRefresh;
      }
    } catch (e) {
      AppLogger.error('Authentication verification failed - attempting silent refresh', e);

      final didRefresh = await _trySilentRefresh();
      if (!didRefresh) {
        await _clearStoredData();
        notifyListeners();
      }
      return didRefresh;
    }
  }
}