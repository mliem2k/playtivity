import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../services/spotify_service.dart';
import '../services/app_logger.dart';
import 'spotify_provider.dart';

class AuthProvider extends ChangeNotifier {
  static const String _bearerTokenKey = 'spotify_bearer_token';
  static const String _headersKey = 'spotify_headers';
  static const String _userKey = 'spotify_user';
  
  final SharedPreferences _prefs;
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();
  
  String? _bearerToken;
  Map<String, String>? _headers;
  User? _currentUser;
  bool _isLoading = false;
  bool _isInitialized = false;

  AuthProvider(this._prefs) {
    _initializeAuth();
  }

  bool get isAuthenticated {
    if (!_isInitialized) {
      AppLogger.auth('isAuthenticated: false (not initialized)');
      return false;
    }
    
    // Check for Bearer token authentication
    final hasToken = _bearerToken != null && _bearerToken!.isNotEmpty;
    final hasUser = _currentUser != null;
    
    // Also verify the buddy service has the token
    final buddyServiceToken = _buddyService.getBearerToken();
    final buddyServiceHasToken = buddyServiceToken != null && buddyServiceToken.isNotEmpty;
    
    final tokenAuth = hasToken && hasUser && buddyServiceHasToken;
    
    return tokenAuth;
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
      
      if (savedBearerToken != null && savedHeadersJson != null) {
        try {
          _bearerToken = savedBearerToken;
          _headers = Map<String, String>.from(json.decode(savedHeadersJson));
          _buddyService.setBearerToken(savedBearerToken, _headers!);
          AppLogger.auth('Restored saved Bearer token and headers');
          
          // Try to load saved user profile
          if (savedUserJson != null) {
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);
            AppLogger.auth('Restored saved user profile: ${_currentUser!.displayName}');
            
            // Validate the restored authentication by making a quick API call
            // This helps detect if tokens have expired while app was backgrounded
            try {
              AppLogger.auth('Validating restored authentication...');
              final testUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (testUser != null && testUser.id == _currentUser!.id) {
                AppLogger.auth('Restored authentication is valid');
              } else {
                AppLogger.warning('Restored authentication validation failed - clearing stored data');
                await _clearStoredData();
                _bearerToken = null;
                _headers = null;
                _currentUser = null;
              }
            } catch (e) {
              AppLogger.warning('Authentication validation failed: $e - clearing stored data');
              await _clearStoredData();
              _bearerToken = null;
              _headers = null;
              _currentUser = null;
            }
          } else {
            // Fetch user profile using Bearer token
            AppLogger.auth('Fetching user profile with Bearer token...');
            try {
              _currentUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
              if (_currentUser != null) {
                AppLogger.auth('Successfully loaded user profile: ${_currentUser!.displayName}');
                // Save the user profile for next time
                await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
              } else {
                AppLogger.warning('Failed to load user profile - clearing stored data');
                await _clearStoredData();
                _bearerToken = null;
                _headers = null;
              }
            } catch (e) {
              AppLogger.warning('Failed to load user profile: $e - clearing stored data');
              await _clearStoredData();
              _bearerToken = null;
              _headers = null;
            }
          }
        } catch (e) {
          AppLogger.warning('Failed to restore saved authentication: $e');
          await _clearStoredData();
        }
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
      AppLogger.auth('   - bearerToken: "${bearerToken.substring(0, 20)}..." (length: ${bearerToken.length})');
      AppLogger.auth('   - headers: ${headers.keys.join(', ')}');
      AppLogger.auth('   - headers Cookie exists: ${headers.containsKey('Cookie')}');
      AppLogger.auth('   - headers Cookie value: ${headers['Cookie']?.substring(0, 100) ?? 'null'}...');
      AppLogger.auth('   - headers Cookie length: ${headers['Cookie']?.length ?? 0}');

      AppLogger.auth('Processing Bearer token authentication...');
      
      // Validate the bearer token
      if (bearerToken.isEmpty || bearerToken.length < 50) {
        throw Exception('Invalid bearer token provided');
      }
      
      // Store Bearer token and headers
      _bearerToken = bearerToken;
      _headers = headers;
      
      // Set the Bearer token directly in buddy service
      _buddyService.setBearerToken(bearerToken, headers);
      
      // Verify the buddy service has the token properly set
      AppLogger.auth('Verifying buddy service token after setting...');
      final buddyServiceToken = _buddyService.getBearerToken();
      if (buddyServiceToken == null || buddyServiceToken.isEmpty) {
        throw Exception('Failed to set Bearer token in buddy service');
      } else {
        AppLogger.auth('Buddy service token verified: ${buddyServiceToken.substring(0, 20)}...');
      }
      
      // Fetch user profile using Bearer token with retry logic
      AppLogger.auth('Fetching user profile with Bearer token...');
      User? userProfile;
      
      // Try multiple times to get user profile (sometimes the token needs a moment to propagate)
      // Extended retry logic for long idle scenarios
      for (int attempt = 1; attempt <= 5; attempt++) {
        try {
          userProfile = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
          if (userProfile != null) {
            AppLogger.auth('Successfully loaded user profile on attempt $attempt: ${userProfile.displayName}');
            break;
          }
        } catch (e) {
          AppLogger.warning('Failed to load user profile on attempt $attempt: $e');
          if (attempt < 5) {
            // Increase delay for later attempts to handle network issues
            final delayMs = attempt <= 2 ? 1000 : 2000;
            AppLogger.auth('Retrying in ${delayMs}ms...');
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
      
      // Final verification with more robust error handling for long idle scenarios
      final hasToken = _bearerToken != null && _bearerToken!.isNotEmpty;
      final hasUser = _currentUser != null;
      final isInitComplete = _isInitialized;
      final finalBuddyServiceToken = _buddyService.getBearerToken();
      final buddyServiceHasToken = finalBuddyServiceToken != null && finalBuddyServiceToken.isNotEmpty;
      
      AppLogger.auth('Final verification check:');
      AppLogger.auth('   - hasToken: $hasToken');
      AppLogger.auth('   - hasUser: $hasUser');
      AppLogger.auth('   - isInitialized: $isInitComplete');
      AppLogger.auth('   - buddyServiceHasToken: $buddyServiceHasToken');
      
      if (!hasToken || !hasUser || !isInitComplete || !buddyServiceHasToken) {
        throw Exception('Authentication verification failed after completion - Token: $hasToken, User: $hasUser, Init: $isInitComplete, BuddyService: $buddyServiceHasToken');
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
    
    AppLogger.auth('Auth data saved successfully');
  }

  Future<void> _clearStoredData() async {
    AppLogger.auth('Clearing stored auth data...');
    
    await _prefs.remove(_bearerTokenKey);
    await _prefs.remove(_headersKey);
    await _prefs.remove(_userKey);
    
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
    
    // Clean up buddy service (this now clears all cached data)
    _buddyService.clearBearerToken();
    
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

  /// Re-authenticate when token expires or is invalid
  Future<bool> reAuthenticate() async {
    AppLogger.auth('Re-authentication requested...');
    
    try {
      // Clear old authentication data
      await _clearStoredData();
      _buddyService.clearBearerToken();
      
      // Start loading state
      _isLoading = true;
      notifyListeners();
      
      // Import the WebView login widget
      // Note: This would need to be called from a UI context
      // For now, we'll return false to indicate manual login is needed
      AppLogger.warning('Re-authentication requires user interaction');
      
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

  /// Debug method to print current authentication state
  void debugAuthState() {
    AppLogger.auth('=== AuthProvider Debug State ===');
    AppLogger.auth('   - isInitialized: $_isInitialized');
    AppLogger.auth('   - isLoading: $_isLoading');
    AppLogger.auth('   - isAuthenticated: $isAuthenticated');
    AppLogger.auth('   - hasBearerToken: ${_bearerToken != null}');
    AppLogger.auth('   - bearerToken: ${_bearerToken?.substring(0, 20) ?? 'null'}...');
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
      
      // Clear buddy service state and caches
      _buddyService.clearBearerToken();
      
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
        
        // Update user info in case anything changed
        _currentUser = testUser;
        await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
        notifyListeners();
        
        return true;
      } else {
        AppLogger.warning('Authentication test failed - user mismatch or null');
        await _clearStoredData();
        _bearerToken = null;
        _headers = null;
        _currentUser = null;
        notifyListeners();
        return false;
      }
    } catch (e) {
      AppLogger.error('Authentication verification failed', e);
      
      // Clear invalid auth data
      await _clearStoredData();
      _bearerToken = null;
      _headers = null;
      _currentUser = null;
      notifyListeners();
      
      return false;
    }
  }
}