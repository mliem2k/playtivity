import 'package:flutter/material.dart';
import '../services/spotify_buddy_service.dart';
import '../services/spotify_service.dart';
import '../services/widget_service.dart';
import '../services/app_logger.dart';
import '../models/track.dart';
import '../models/activity.dart';
import '../models/artist.dart';
import '../models/user.dart';

class SpotifyProvider extends ChangeNotifier {
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();
  final SpotifyService _spotifyService = SpotifyService();

  String? _bearerToken;

  List<Track> _topTracks = [];
  List<Artist> _topArtists = [];
  List<Activity> _friendsActivities = [];
  Track? _currentlyPlaying;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSkeletonLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  // Flag to indicate if an authentication error occurred
  bool _hasAuthError = false;
  String? _authErrorMessage;

  bool _batchMode = false;

  void _notify() {
    if (!_batchMode) notifyListeners();
  }

  List<Track> get topTracks => _topTracks;
  List<Artist> get topArtists => _topArtists;
  List<Activity> get friendsActivities => _friendsActivities;
  Track? get currentlyPlaying => _currentlyPlaying;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isSkeletonLoading => _isSkeletonLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  bool get hasAuthError => _hasAuthError;
  String? get authErrorMessage => _authErrorMessage;
  String get buddylistDiagnostic => SpotifyBuddyService.lastDiagnostic;

  void setBearer(String token) {
    _bearerToken = token;
  }

  void clearBearer() {
    _bearerToken = null;
    clearData();
  }

  /// Check if error is authentication-related and handle accordingly
  bool _isAuthenticationError(String error) {
    return error.contains('401') ||
           error.contains('403') ||
           error.contains('No Bearer token available') ||
           error.contains('Authentication expired') ||
           error.contains('Unauthorized') ||
           error.contains('Not authenticated');
  }

  /// Handle authentication errors by setting flag for UI to handle
  Future<void> _handleAuthenticationError(String error) async {
    AppLogger.error('Authentication error detected in provider', error);
    _hasAuthError = true;
    _authErrorMessage = error;

    // Clear all cached data in this provider since authentication failed
    _topTracks = [];
    _topArtists = [];
    _friendsActivities = [];
    _currentlyPlaying = null;
    _error = 'Authentication expired. Please login again.';
  }

  /// Clear authentication error flag
  void clearAuthError() {
    _hasAuthError = false;
    _authErrorMessage = null;
    notifyListeners();
  }

  Future<void> loadCurrentlyPlaying({bool showLoading = false}) async {
    if (showLoading) {
      _isLoading = true;
      _error = null;
      _notify();
    }

    try {
      final token = _bearerToken;
      if (token != null) {
        _currentlyPlaying = await _spotifyService.getCurrentlyPlaying(token);
      } else {
        _currentlyPlaying = null;
      }
    } catch (e) {
      AppLogger.error('Failed to load currently playing', e);
      _currentlyPlaying = null;
      if (!e.toString().contains('No Bearer token available')) {
        _error = e.toString();
      }
    }

    if (showLoading) _isLoading = false;
    _notify();

    // Update widget with new currently playing data
    await _updateWidget();
  }

  Future<void> loadTopTracks({String timeRange = 'medium_term', bool showLoading = false}) async {
    final token = _bearerToken;
    if (token == null) {
      _error = 'Not authenticated';
      _notify();
      return;
    }

    if (showLoading) {
      _isLoading = true;
      _error = null;
      _notify();
    }

    try {
      _topTracks = await _buddyService.getTopTracks(token, timeRange: timeRange);
    } catch (e) {
      _error = e.toString();
    }

    if (showLoading) _isLoading = false;
    _notify();
  }

  Future<void> loadTopArtists({String timeRange = 'medium_term', bool showLoading = false}) async {
    final token = _bearerToken;
    if (token == null) {
      _error = 'Not authenticated';
      _notify();
      return;
    }

    if (showLoading) {
      _isLoading = true;
      _error = null;
      _notify();
    }

    try {
      final newTopArtists = await _buddyService.getTopArtistsWithDetails(
        token,
        timeRange: timeRange,
        onArtistDetailsUpdate: (updatedArtists) {
          // Progressive disclosure: intentionally notifies on each artist detail page
          _topArtists = updatedArtists;
          notifyListeners();
        },
      );
      _topArtists = newTopArtists;
    } catch (e) {
      _error = e.toString();
    }

    if (showLoading) _isLoading = false;
    _notify();
  }

  Future<void> loadFriendsActivities({bool showLoading = false, bool showSkeleton = false}) async {
    final token = _bearerToken;
    if (token == null) {
      _error = 'Not authenticated';
      if (showLoading) _isLoading = false;
      if (showSkeleton) _isSkeletonLoading = false;
      _notify();
      return;
    }

    if (showLoading) {
      _isLoading = true;
      _error = null;
      _notify();
    } else if (showSkeleton) {
      _isSkeletonLoading = true;
      _error = null;
      _notify();
    }

    try {
      List<Activity> activities = [];

      // Get friend activities using Bearer token
      try {
        activities = await _buddyService.getFriendActivity(token);
      } catch (e) {
        AppLogger.error('Failed to fetch friend activities', e);

        // Check if this is an authentication error
        final errorMessage = e.toString();
        if (_isAuthenticationError(errorMessage)) {
          AppLogger.auth('Authentication error detected, may need re-authentication');
          await _handleAuthenticationError(errorMessage);
        } else {
          _error = 'Failed to load friend activities: $errorMessage';
        }
      }

      _friendsActivities = activities;

      // Only update lastUpdated when we actually fetch new data
      if (activities.isNotEmpty) _lastUpdated = DateTime.now();
    } catch (e) {
      _error = e.toString();
      _friendsActivities = [];
    }

    if (showLoading) _isLoading = false;
    if (showSkeleton) _isSkeletonLoading = false;
    _notify();

    if (_friendsActivities.isNotEmpty) await _updateWidget();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearData() {
    _topTracks = [];
    _topArtists = [];
    _friendsActivities = [];
    _currentlyPlaying = null;
    _isLoading = false;
    _isRefreshing = false;
    _isSkeletonLoading = false;
    _error = null;
    _lastUpdated = null;
    _hasAuthError = false;
    _authErrorMessage = null;
    notifyListeners();
  }

  Future<void> refreshData({bool showLoading = false}) async {
    _batchMode = true;
    try {
      await Future.wait([
        loadCurrentlyPlaying(showLoading: showLoading),
        loadTopTracks(showLoading: showLoading),
        loadTopArtists(showLoading: showLoading),
        loadFriendsActivities(showLoading: showLoading),
      ]);
    } finally {
      _batchMode = false;
    }

    _lastUpdated = DateTime.now();
    notifyListeners();

    // Update widget after refreshing data
    await _updateWidget();
  }

  /// Silent refresh - updates data without showing loading indicators
  Future<void> silentRefresh() async {
    _isRefreshing = true;
    notifyListeners();

    try {
      await refreshData(showLoading: false);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Fast initial load - shows skeleton while loading basic data, then loads detailed info
  Future<void> fastInitialLoad() async {
    try {
      // First, show skeleton loading
      if (_friendsActivities.isEmpty) {
        _isSkeletonLoading = true;
        notifyListeners();

        // Small delay to show skeleton
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await loadFriendsActivities(showSkeleton: _friendsActivities.isEmpty);

      _lastUpdated = DateTime.now();
      notifyListeners();

      // Update widget after initial load
      await _updateWidget();
    } catch (e) {
      AppLogger.error('Error during fast initial load', e);
      _error = e.toString();
      _isSkeletonLoading = false;
      notifyListeners();
    }
  }

  /// Full refresh - shows loading indicators during data fetch
  Future<void> fullRefresh() async {
    await refreshData(showLoading: true);
  }

  /// Update home screen widget with current data
  Future<void> _updateWidget({User? currentUser}) async {
    try {
      await WidgetService.updateWidget(
        currentUser: currentUser,
        friendsActivities: _friendsActivities,
      );
    } catch (e) {
      AppLogger.error('Failed to update widget', e);
    }
  }

  /// Public method to update widget with user data
  Future<void> updateWidget({User? currentUser}) async {
    await _updateWidget(currentUser: currentUser);
  }

}
