import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/spotify_service.dart';
import '../services/spotify_buddy_service.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  static const String _spDcCookieKey = 'spotify_sp_dc_cookie';
  static const String _accessTokenKey = 'spotify_access_token';
  static const String _refreshTokenKey = 'spotify_refresh_token';
  static const String _tokenExpiryKey = 'spotify_token_expiry';
  
  final SharedPreferences _prefs;
  final SpotifyService _spotifyService = SpotifyService();
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();
  
  String? _spDcCookie;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  User? _currentUser;
  bool _isLoading = false;
  bool _isInitialized = false;

  AuthProvider(this._prefs) {
    _initializeAuth();
  }

  bool get isAuthenticated {
    if (!_isInitialized) return false;
    
    final oauthAuth = _accessToken != null && !_isTokenExpired;
    final cookieAuth = _spDcCookie != null && _currentUser != null;
    final result = oauthAuth || cookieAuth;
    
    // Keep minimal logging for release builds
    if (!result) {
      print('❌ Not authenticated - OAuth: $oauthAuth, Cookie: $cookieAuth');
    }
    
    return result;
  }
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  User? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  String? get spDcCookie => _spDcCookie;

  bool get _isTokenExpired {
    if (_tokenExpiry == null) return true;
    return DateTime.now().isAfter(_tokenExpiry!);
  }

  /// Gets token status information for debugging
  Map<String, dynamic> get tokenStatus {
    final now = DateTime.now();
    final hasToken = _accessToken != null;
    final hasRefreshToken = _refreshToken != null;
    final isExpired = _isTokenExpired;
    final timeUntilExpiry = _tokenExpiry != null 
        ? _tokenExpiry!.difference(now).inMinutes 
        : null;
    
    return {
      'hasToken': hasToken,
      'hasRefreshToken': hasRefreshToken,
      'isExpired': isExpired,
      'expiryTime': _tokenExpiry?.toIso8601String(),
      'minutesUntilExpiry': timeUntilExpiry,
    };
  }

  Future<void> _initializeAuth() async {
    try {
      _loadStoredData();
      
      if (_accessToken != null && !_isTokenExpired) {
        print('✅ Valid OAuth token found, loading user profile');
        await _loadCurrentUser();
      } else if (_accessToken != null && _isTokenExpired) {
        print('⚠️ OAuth token found but expired');
      } else if (_spDcCookie != null && _accessToken == null) {
        print('✅ Cookie-only authentication found, creating minimal user profile');
        _currentUser = User(
          id: 'cookie_user',
          displayName: 'Spotify User',
          email: '',
          imageUrl: null,
          followers: 0,
          country: '',
        );
      }
    } catch (e) {
      print('❌ Error during auth initialization: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  void _loadStoredData() {
    _spDcCookie = _prefs.getString(_spDcCookieKey);
    _accessToken = _prefs.getString(_accessTokenKey);
    _refreshToken = _prefs.getString(_refreshTokenKey);
    
    final expiryTimestamp = _prefs.getInt(_tokenExpiryKey);
    if (expiryTimestamp != null) {
      _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryTimestamp);
    }

    // Log what we loaded
    print('📦 Loaded stored auth data:');
    print('   - sp_dc cookie: ${_spDcCookie != null ? 'present' : 'missing'}');
    print('   - OAuth access token: ${_accessToken != null ? 'present' : 'missing'}');
    print('   - Refresh token: ${_refreshToken != null ? 'present' : 'missing'}');
    print('   - Token expiry: ${_tokenExpiry?.toIso8601String() ?? 'not set'}');
    print('   - Token expired: ${_isTokenExpired}');
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Use OAuth token to get real user profile from Spotify API
      _currentUser = await _spotifyService.getCurrentUser(_accessToken!);
    } catch (e) {
      print('Failed to load user: $e');
      // Don't logout during initialization, just clear the invalid token
      _accessToken = null;
      _refreshToken = null;
      _tokenExpiry = null;
      await _prefs.remove(_accessTokenKey);
      await _prefs.remove(_refreshTokenKey);
      await _prefs.remove(_tokenExpiryKey);
    }
  }

  void startLogin() {
    _isLoading = true;
    notifyListeners();
  }

  void cancelLogin() {
    _isLoading = false;
    notifyListeners();
  }

  Future<void> handleAuthComplete(String oauthCode, String? spDcCookie) async {
    try {
      print('🔍 handleAuthComplete called with:');
      print('   - oauthCode: "${oauthCode}" (length: ${oauthCode.length}, isEmpty: ${oauthCode.isEmpty})');
      print('   - spDcCookie: ${spDcCookie != null ? 'present' : 'null'}');
      
      if (oauthCode.isNotEmpty) {
        // OAuth flow - exchange code for tokens
      print('🔄 Processing OAuth code and sp_dc cookie...');
      
      final tokenData = await _spotifyService.exchangeCodeForToken(oauthCode);
      
      _accessToken = tokenData['access_token'];
      _refreshToken = tokenData['refresh_token'];
      
      final expiresIn = tokenData['expires_in'] as int;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

        // Store sp_dc cookie for friend activities
      _spDcCookie = spDcCookie;

      await _saveStoredData();
      await _loadCurrentUser();
        
        print('✅ Authentication complete - OAuth tokens and sp_dc cookie stored');
      } else {
        // Cookie-only authentication
        print('🔄 Processing cookie-only authentication...');
        
        if (spDcCookie == null || spDcCookie.isEmpty) {
          throw Exception('No sp_dc cookie provided for cookie-only authentication');
        }

        // Store sp_dc cookie
        _spDcCookie = spDcCookie;
        
        // Create a minimal user profile for cookie-only auth
        _currentUser = User(
          id: 'cookie_user',
          displayName: 'Spotify User',
          email: '',
          imageUrl: null,
          followers: 0,
          country: '',
        );

        await _saveStoredData();
        
        print('✅ Cookie-only authentication complete - sp_dc cookie stored');
      }
      
      _isLoading = false;
      _isInitialized = true; // Ensure we're marked as initialized after auth completion
      
      // Ensure UI updates in release builds
      notifyListeners();
      
      // Small delay to ensure state is properly propagated
      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();
      
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _saveStoredData() async {
    print('💾 Saving auth data to storage...');
    
    if (_spDcCookie != null) {
      await _prefs.setString(_spDcCookieKey, _spDcCookie!);
    }
    if (_accessToken != null) {
      await _prefs.setString(_accessTokenKey, _accessToken!);
    }
    if (_refreshToken != null) {
      await _prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    if (_tokenExpiry != null) {
      await _prefs.setInt(_tokenExpiryKey, _tokenExpiry!.millisecondsSinceEpoch);
    }
    
    print('✅ Auth data saved successfully');
    print('   - Token expires at: ${_tokenExpiry?.toIso8601String()}');
  }

  Future<void> refreshAccessToken() async {
    if (_refreshToken == null) {
      print('❌ No refresh token available, logging out');
      await logout();
      return;
    }

    try {
      print('🔄 Refreshing OAuth access token...');
      final tokenData = await _spotifyService.refreshToken(_refreshToken!);
      
      _accessToken = tokenData['access_token'];
      final expiresIn = tokenData['expires_in'] as int;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

      await _saveStoredData();
      notifyListeners();
      
      print('✅ OAuth access token refreshed successfully (expires at ${_tokenExpiry?.toIso8601String()})');
    } catch (e) {
      print('❌ Failed to refresh OAuth access token: $e');
      print('🔄 Clearing invalid tokens and logging out');
      await logout();
    }
  }

  Future<void> logout() async {
    print('🚪 Logging out and clearing all auth data...');
    
    _spDcCookie = null;
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _currentUser = null;

    await _prefs.remove(_spDcCookieKey);
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove(_tokenExpiryKey);

    print('✅ All auth data cleared successfully');
    notifyListeners();
  }

  Future<String?> getValidToken() async {
    // Check if we have a valid cached token
    if (_accessToken != null && !_isTokenExpired) {
      print('✅ Using cached OAuth access token (expires at ${_tokenExpiry?.toIso8601String()})');
      return _accessToken;
    }
    
    // Token is expired but we have a refresh token
    if (_isTokenExpired && _refreshToken != null) {
      print('🔄 OAuth access token expired, refreshing...');
      await refreshAccessToken();
      if (_accessToken != null) {
        print('✅ Successfully refreshed OAuth access token');
        return _accessToken;
      }
    }
    
    // No valid token available
    if (_accessToken == null) {
      print('❌ No OAuth access token available');
    }
    
    return _accessToken;
  }
} 