import 'package:flutter/material.dart';
import '../services/spotify_buddy_service.dart';
import '../services/spotify_service.dart';
import '../services/widget_service.dart';
import '../models/track.dart';
import '../models/activity.dart';
import '../models/artist.dart';
import '../models/user.dart';

class SpotifyProvider extends ChangeNotifier {
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();
  final SpotifyService _spotifyService = SpotifyService();
  
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

  /// Check if error is authentication-related and handle accordingly
  bool _isAuthenticationError(String error) {
    return error.contains('401') || 
           error.contains('403') || 
           error.contains('No Bearer token available') || 
           error.contains('No cookie string available') ||
           error.contains('Authentication expired') ||
           error.contains('Unauthorized');
  }

  /// Handle authentication errors by setting flag for UI to handle
  Future<void> _handleAuthenticationError(String error) async {
    print('🚨 Authentication error detected in provider: $error');
    _hasAuthError = true;
    _authErrorMessage = error;
    notifyListeners();
  }

  /// Clear authentication error flag
  void clearAuthError() {
    _hasAuthError = false;
    _authErrorMessage = null;
    notifyListeners();
  }

  Future<void> loadCurrentlyPlaying({bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;

      // Get Bearer token from buddy service
      final accessToken = _buddyService.getBearerToken();
      if (accessToken != null) {
        final track = await _spotifyService.getCurrentlyPlaying(accessToken);
        _currentlyPlaying = track;
      } else {
        _currentlyPlaying = null;
      }
      
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
      
      // Update widget with new currently playing data
      await _updateWidget();
    } catch (e) {
      print('❌ Failed to load currently playing: $e');
      _currentlyPlaying = null;
      if (!e.toString().contains('No Bearer token available')) {
        _error = e.toString();
      }
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadTopTracks({String timeRange = 'medium_term', bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;

      final newTopTracks = await _buddyService.getTopTracks(timeRange: timeRange);
      _topTracks = newTopTracks;
      
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadTopArtists({String timeRange = 'medium_term', bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;
      
      final newTopArtists = await _buddyService.getTopArtistsWithDetails(
        timeRange: timeRange,
        onArtistDetailsUpdate: (updatedArtists) {
          // Update the list dynamically as artist details are loaded
          _topArtists = updatedArtists;
          notifyListeners();
        },
      );
      _topArtists = newTopArtists;
      
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadFriendsActivities({bool showLoading = false, bool showSkeleton = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      } else if (showSkeleton) {
        _isSkeletonLoading = true;
        notifyListeners();
      }
      _error = null;

      List<Activity> activities = [];

      // Get friend activities using Bearer token
      print('🔄 Attempting to fetch friend activities with Bearer token...');
      try {
        // Use fast load when showing skeleton to avoid slow API calls
        final useFastLoad = showSkeleton;
        activities = await _buddyService.getFriendActivity(
          fastLoad: useFastLoad,
          onActivitiesUpdate: (updatedActivities) {
            // Update activities progressively as track durations are fetched
            _friendsActivities = updatedActivities;
            notifyListeners();
            print('🔄 Progressive update: ${updatedActivities.length} activities updated');
          },
        );
        if (activities.isNotEmpty) {
          print('✅ Successfully fetched ${activities.length} friend activities');
        } else {
          print('⚠️ No friend activities found');
        }
      } catch (e) {
        print('❌ Failed to fetch friend activities: $e');
        
        // Check if this is an authentication error
        final errorMessage = e.toString();
        if (_isAuthenticationError(errorMessage)) {
          print('🔐 Authentication error detected, may need re-authentication');
          _error = 'Authentication expired. Please login again.';
          await _handleAuthenticationError(errorMessage);
        } else {
          _error = 'Failed to load friend activities: $errorMessage';
        }
      }
      
      _friendsActivities = activities;
      if (showLoading) {
        _isLoading = false;
      } else if (showSkeleton) {
        _isSkeletonLoading = false;
      }
      
      // Only update lastUpdated when we actually fetch new data
      if (activities.isNotEmpty) {
        _lastUpdated = DateTime.now();
      }
      
      notifyListeners();
      
      // Update widget if we have activities data
      if (activities.isNotEmpty) {
        await _updateWidget();
      }
    } catch (e) {
      _error = e.toString();
      _friendsActivities = [];
      if (showLoading) {
        _isLoading = false;
      } else if (showSkeleton) {
        _isSkeletonLoading = false;
      }
      notifyListeners();
    }
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
    List<Future> futures = [];
    
    // Load all features using Bearer token authentication
    futures.addAll([
      loadCurrentlyPlaying(showLoading: showLoading),
      loadTopTracks(showLoading: showLoading),
      loadTopArtists(showLoading: showLoading),
      loadFriendsActivities(showLoading: showLoading),
    ]);
    
    if (futures.isNotEmpty) {
      await Future.wait(futures);
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
      
      // Load basic friends activities data (fast mode)
      await loadFriendsActivities(
        showSkeleton: _friendsActivities.isEmpty
      );
      
      // After fast load, enhance with detailed info in background
      _enhanceActivitiesInBackground();
      
      _lastUpdated = DateTime.now();
      notifyListeners();
      
      // Update widget after initial load
      await _updateWidget();
    } catch (e) {
      print('❌ Error during fast initial load: $e');
      _error = e.toString();
      _isSkeletonLoading = false;
      notifyListeners();
    }
  }

  /// Enhances activities with detailed information in the background
  Future<void> _enhanceActivitiesInBackground() async {
    // Wait a bit to let the UI settle
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      print('🔄 Enhancing activities with detailed info...');
      // Load detailed activities (with duration checks)
      final detailedActivities = await _buddyService.getFriendActivity(
        fastLoad: false, // Full load with duration checks
        onActivitiesUpdate: (updatedActivities) {
          // Update activities progressively as track durations are fetched
          _friendsActivities = updatedActivities;
          notifyListeners();
          print('🔄 Background enhancement update: ${updatedActivities.length} activities updated');
        },
      );
      
      if (detailedActivities.isNotEmpty) {
        _friendsActivities = detailedActivities;
        _lastUpdated = DateTime.now();
        notifyListeners();
        print('✅ Enhanced ${detailedActivities.length} activities with detailed info');
      }
    } catch (e) {
      print('❌ Failed to enhance activities: $e');
      
      // Check if this is an authentication error
      final errorMessage = e.toString();
      if (_isAuthenticationError(errorMessage)) {
        print('🔐 Authentication error detected during enhancement');
        _error = 'Authentication expired. Please login again.';
        await _handleAuthenticationError(errorMessage);
        notifyListeners();
      }
      // Don't update error state for other errors since we already have basic data
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
      print('❌ Failed to update widget: $e');
    }
  }

  /// Public method to update widget with user data
  Future<void> updateWidget({User? currentUser}) async {
    await _updateWidget(currentUser: currentUser);
  }
  
  /// Debug method for widget testing
  Future<void> debugWidget() async {
    await WidgetService.debugWidgetData();
  }
} 