import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';
import '../services/spotify_service.dart';

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
      print('🔍 isAuthenticated: false (not initialized)');
      return false;
    }
    
    // Check for Bearer token authentication
    final tokenAuth = _bearerToken != null && _currentUser != null;
    
    print('🔍 isAuthenticated evaluation:');
    print('   - Token valid: $tokenAuth (token: ${_bearerToken != null}, user: ${_currentUser != null})');
    print('   - User: ${_currentUser?.displayName ?? 'none'}');
    print('   - Final result: $tokenAuth');
    
    return tokenAuth;
  }
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  User? get currentUser => _currentUser;
  String? get bearerToken => _bearerToken;
  Map<String, String>? get headers => _headers;

  Future<void> _initializeAuth() async {
    try {
      print('🔄 Starting authentication initialization...');
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
          print('✅ Restored saved Bearer token and headers');
          
          // Try to load saved user profile
          if (savedUserJson != null) {
            final userMap = json.decode(savedUserJson);
            _currentUser = User.fromJson(userMap);
            print('✅ Restored saved user profile: ${_currentUser!.displayName}');
          } else {
            // Fetch user profile using Bearer token
            print('🔄 Fetching user profile with Bearer token...');
            _currentUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
            if (_currentUser != null) {
              print('✅ Successfully loaded user profile: ${_currentUser!.displayName}');
            }
          }
        } catch (e) {
          print('⚠️ Failed to restore saved authentication: $e');
          await _clearStoredData();
        }
      }
      
      print('🔍 Initialization complete. Final state:');
      print('   - Has Bearer token: ${_bearerToken != null}');
      print('   - Has user: ${_currentUser != null}');
      print('   - User name: ${_currentUser?.displayName ?? 'none'}');
      
    } catch (e) {
      print('❌ Error during auth initialization: $e');
    } finally {
      _isInitialized = true;
      print('✅ AuthProvider initialization completed');
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
    print('🧹 Cleaning up old authentication data...');
    _prefs.remove('spotify_sp_dc_cookie');
    _prefs.remove('spotify_access_token');
    _prefs.remove('spotify_refresh_token');
    _prefs.remove('spotify_token_expiry');
    
    print('📦 Old authentication data cleaned up');
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
      print('🔍 handleAuthComplete called with:');
      print('   - bearerToken: "${bearerToken.substring(0, 20)}..." (length: ${bearerToken.length})');
      print('   - headers: ${headers.keys.join(', ')}');
      print('   - headers Cookie exists: ${headers.containsKey('Cookie')}');
      print('   - headers Cookie value: ${headers['Cookie']?.substring(0, 100) ?? 'null'}...');
      print('   - headers Cookie length: ${headers['Cookie']?.length ?? 0}');

      print('🔄 Processing Bearer token authentication...');
      
      // Store Bearer token and headers
      _bearerToken = bearerToken;
      _headers = headers;
      
      // Set the Bearer token directly in buddy service
      _buddyService.setBearerToken(bearerToken, headers);
      
      // Fetch user profile using Bearer token
      print('🔄 Fetching user profile with Bearer token...');
      _currentUser = await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
      if (_currentUser != null) {
        print('✅ Successfully loaded user profile: ${_currentUser!.displayName}');
      } else {
        print('⚠️ Failed to load user profile');
      }

      await _saveStoredData();
      
      print('✅ Bearer token authentication complete - token and user profile stored');
      
      // Clear loading state and ensure initialization is complete
      _isLoading = false;
      _isInitialized = true;
      
      print('🔄 AuthProvider state after completion:');
      print('   - isAuthenticated: $isAuthenticated');
      print('   - isInitialized: $_isInitialized');
      print('   - isLoading: $_isLoading');
      print('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
      
      // Force UI update with multiple notifications to ensure state propagation
      notifyListeners();
      
      // Add a short delay and notify again to handle any race conditions
      await Future.delayed(const Duration(milliseconds: 50));
      notifyListeners();
      
      // Final notification after a longer delay to ensure all consumers are updated
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
      
    } catch (e) {
      print('❌ Error in handleAuthComplete: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _saveStoredData() async {
    print('💾 Saving auth data to storage...');
    
    if (_bearerToken != null) {
      await _prefs.setString(_bearerTokenKey, _bearerToken!);
      print('✅ Bearer token saved successfully');
    }
    
    if (_headers != null) {
      await _prefs.setString(_headersKey, json.encode(_headers!));
      print('✅ Headers saved successfully');
    }
    
    if (_currentUser != null) {
      await _prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
      print('✅ User profile saved successfully');
    }
    
    print('✅ Auth data saved successfully');
  }

  Future<void> _clearStoredData() async {
    print('🗑️ Clearing stored auth data...');
    
    await _prefs.remove(_bearerTokenKey);
    await _prefs.remove(_headersKey);
    await _prefs.remove(_userKey);
    
    _bearerToken = null;
    _headers = null;
    _currentUser = null;
    
    print('✅ Stored auth data cleared');
  }

  Future<void> logout() async {
    print('🚪 Logging out and clearing all auth data...');
    
    // Set loading state to prevent race conditions
    _isLoading = true;
    notifyListeners();
    
    await _clearStoredData();
    
    // Clean up buddy service
    _buddyService.clearBearerToken();
    
    // Ensure all state is properly reset
    _isLoading = false;
    
    print('✅ All auth data cleared successfully');
    print('🔍 Post-logout state:');
    print('   - isAuthenticated: $isAuthenticated');
    print('   - isInitialized: $_isInitialized');
    print('   - isLoading: $_isLoading');
    print('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
    
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
    print('🔄 Re-authentication requested...');
    
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
      print('⚠️ Re-authentication requires user interaction');
      
      return false;
    } catch (e) {
      print('❌ Error during re-authentication: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if token needs refresh and handle it
  Future<bool> ensureValidAuthentication() async {
    if (!isAuthenticated) {
      print('⚠️ No valid authentication, re-authentication needed');
      return false;
    }
    
    // Test if current token is still valid by making a simple API call
    try {
      await _buddyService.getCurrentUserProfileWithToken(_bearerToken!);
      print('✅ Current authentication is valid');
      return true;
    } catch (e) {
      try {
        // Fallback to SpotifyService
        final spotifyService = SpotifyService();
        await spotifyService.getCurrentUser(_bearerToken!);
        print('✅ Current authentication is valid (via fallback)');
        return true;
      } catch (fallbackError) {
        print('⚠️ Current authentication invalid: $e');
        print('⚠️ Fallback also failed: $fallbackError');
        print('🔄 Attempting re-authentication...');
        return await reAuthenticate();
      }
    }
  }

  /// Debug method to print current authentication state
  void debugAuthState() {
    print('🔍 === AuthProvider Debug State ===');
    print('   - isInitialized: $_isInitialized');
    print('   - isLoading: $_isLoading');
    print('   - isAuthenticated: $isAuthenticated');
    print('   - hasBearerToken: ${_bearerToken != null}');
    print('   - bearerToken: ${_bearerToken?.substring(0, 20) ?? 'null'}...');
    print('   - currentUser: ${_currentUser?.displayName ?? 'null'}');
    print('   - currentUserId: ${_currentUser?.id ?? 'null'}');
    print('   - userEmail: ${_currentUser?.email ?? 'null'}');
    print('=================================');
  }

  /// Force logout with complete state reset and navigation
  Future<void> forceLogoutAndNavigate(BuildContext context) async {
    print('🚪 Force logout initiated...');
    
    // Set loading state
    _isLoading = true;
    notifyListeners();
    
    // Clear all authentication data
    await _clearStoredData();
    _buddyService.clearBearerToken();
    
    // Reset all state variables
    _isLoading = false;
    _bearerToken = null;
    _headers = null;
    _currentUser = null;
    
    print('✅ All auth data cleared, forcing navigation...');
    
    // Force multiple notifications
    notifyListeners();
    
    // Navigate directly to login screen with complete stack clear
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
      print('✅ Navigation completed to login screen');
    }
    
    // Additional notifications after navigation
    await Future.delayed(const Duration(milliseconds: 100));
    notifyListeners();
  }
}