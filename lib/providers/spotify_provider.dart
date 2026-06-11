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
  final SpotifyBuddyService _buddyService;
  final SpotifyService _spotifyService;

  SpotifyProvider({
    SpotifyBuddyService? buddyService,
    SpotifyService? spotifyService,
  })  : _buddyService = buddyService ?? SpotifyBuddyService(),
        _spotifyService = spotifyService ?? SpotifyService();

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
  int get buddylistApiCount => SpotifyBuddyService.lastApiFriendCount;
  // Show the merged count when accumulation added extra friends
  int get buddylistParsedCount {
    final merged = SpotifyBuddyService.lastMergedCount;
    final parsed = SpotifyBuddyService.lastParsedCount;
    return merged > parsed ? merged : parsed;
  }

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
      bool fetchSucceeded = false;
      bool authFailed = false;

      // Get friend activities using Bearer token
      try {
        activities = await _buddyService.getFriendActivity(token);
        fetchSucceeded = true;
      } catch (e) {
        AppLogger.error('Failed to fetch friend activities', e);

        // Check if this is an authentication error
        final errorMessage = e.toString();
        if (_isAuthenticationError(errorMessage)) {
          authFailed = true;
          AppLogger.auth('Authentication error detected, may need re-authentication');
          await _handleAuthenticationError(errorMessage);
        } else {
          _error = 'Failed to load friend activities: $errorMessage';
        }
      }

      if (fetchSucceeded) {
        // Honor the result even when empty — the buddy service already merges
        // and ages out friends, so an empty success means there is genuinely
        // nothing to show.
        _friendsActivities = activities;
        if (activities.isNotEmpty) _lastUpdated = DateTime.now();
      } else if (!authFailed) {
        // Transient (non-auth) failure: never drop to zero cards. Keep the
        // friends already on screen, and recover from the buddy service's
        // accumulated cache — the same data the home widget keeps rendering —
        // when we currently have nothing.
        if (_friendsActivities.isEmpty) {
          final cached = _buddyService.cachedActivities;
          if (cached != null && cached.isNotEmpty) {
            _friendsActivities = cached;
          }
        }
      }
    } catch (e) {
      _error = e.toString();
      // Preserve any friends already loaded; an unexpected error must not wipe
      // a list the widget is still showing.
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

  /// Loads only profile-related data (currently playing, top tracks, top artists).
  /// Does NOT fetch friend activity — home screen owns that call.
  /// Does NOT use _batchMode so its loading state never suppresses notifications
  /// from concurrent friend-activity fetches started by fastInitialLoad.
  Future<void> refreshProfileData({bool showLoading = false}) async {
    await Future.wait([
      loadCurrentlyPlaying(showLoading: showLoading),
      loadTopTracks(showLoading: showLoading),
      loadTopArtists(showLoading: showLoading),
    ]);
    _lastUpdated = DateTime.now();
    notifyListeners();
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

  /// Fast initial load — shows persisted stale data instantly, then fetches fresh.
  Future<void> fastInitialLoad() async {
    try {
      // Wait for SharedPreferences persistence load (typically <30ms)
      await _buddyService.persistenceReady;

      final stale = _buddyService.cachedActivities;
      if (stale != null && stale.isNotEmpty) {
        // Show stale data immediately — no skeleton needed
        _friendsActivities = stale;
        notifyListeners();
      } else {
        _isSkeletonLoading = true;
        notifyListeners();
      }

      // Force a live fetch without clearing existing activities — they'll be merged
      // with the fresh response so we accumulate friends across refreshes.
      _buddyService.forceRefresh();
      await loadFriendsActivities(showSkeleton: _friendsActivities.isEmpty);

      _lastUpdated = DateTime.now();
      notifyListeners();
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
