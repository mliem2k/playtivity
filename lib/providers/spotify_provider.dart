import 'package:flutter/material.dart';
import '../services/spotify_service.dart';
import '../services/spotify_buddy_service.dart';
import '../models/track.dart';
import '../models/activity.dart';
import '../models/artist.dart';

class SpotifyProvider extends ChangeNotifier {
  final SpotifyService _spotifyService = SpotifyService();
  final SpotifyBuddyService _buddyService = SpotifyBuddyService();
  
  Track? _currentlyPlaying;
  List<Track> _topTracks = [];
  List<Artist> _topArtists = [];
  List<Activity> _friendsActivities = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isSkeletonLoading = false;
  String? _error;
  DateTime? _lastUpdated;
  
  Track? get currentlyPlaying => _currentlyPlaying;
  List<Track> get topTracks => _topTracks;
  List<Artist> get topArtists => _topArtists;
  List<Activity> get friendsActivities => _friendsActivities;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isSkeletonLoading => _isSkeletonLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  Future<void> loadCurrentlyPlaying(String accessToken, {bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;
      
      final newCurrentlyPlaying = await _spotifyService.getCurrentlyPlaying(accessToken);
      _currentlyPlaying = newCurrentlyPlaying;
      
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

  Future<void> loadTopTracks(String accessToken, {String timeRange = 'medium_term', bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;

      final newTopTracks = await _spotifyService.getTopTracks(accessToken, timeRange: timeRange);
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

  Future<void> loadTopArtists(String accessToken, {String timeRange = 'medium_term', bool showLoading = false}) async {
    try {
      if (showLoading) {
        _isLoading = true;
        notifyListeners();
      }
      _error = null;
      
      final newTopArtists = await _spotifyService.getTopArtists(accessToken, timeRange: timeRange);
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

  Future<void> loadFriendsActivities(String accessToken, {String? spDcCookie, bool showLoading = false, bool showSkeleton = false}) async {
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

      // Try to get real friend activities using sp_dc cookie if available
      if (spDcCookie != null) {
        print('🔄 Attempting to fetch real friend activities with sp_dc cookie...');
        try {
          // Use fast load when showing skeleton to avoid slow API calls
          final useFastLoad = showSkeleton;
          activities = await _buddyService.getFriendActivity(
            spDcCookie, 
            oauthAccessToken: accessToken,
            fastLoad: useFastLoad
          );
          if (activities.isNotEmpty) {
            print('✅ Successfully fetched ${activities.length} real friend activities');
          } else {
            print('⚠️ No friend activities found');
          }
        } catch (e) {
          print('❌ Failed to fetch real friend activities: $e');
        }
      } else {
        print('⚠️ No sp_dc cookie available, cannot fetch friend activities');
      }
      
      _friendsActivities = activities;
      if (showLoading) {
        _isLoading = false;
      } else if (showSkeleton) {
        _isSkeletonLoading = false;
      }
      notifyListeners();
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
    _currentlyPlaying = null;
    _topTracks = [];
    _topArtists = [];
    _friendsActivities = [];
    _isLoading = false;
    _isRefreshing = false;
    _isSkeletonLoading = false;
    _error = null;
    _lastUpdated = null;
    notifyListeners();
  }

  Future<void> refreshData(String accessToken, {String? spDcCookie, bool showLoading = false}) async {
    List<Future> futures = [];
    
    // Only load OAuth-dependent features if we have a valid access token
    if (accessToken.isNotEmpty) {
      futures.addAll([
      loadCurrentlyPlaying(accessToken, showLoading: showLoading),
      loadTopTracks(accessToken, showLoading: showLoading),
      loadTopArtists(accessToken, showLoading: showLoading),
      ]);
    } else {
      print('⚠️ No OAuth token available - skipping OAuth-dependent features');
    }
    
    // Always try to load friends' activities if we have a cookie
    if (spDcCookie != null) {
      futures.add(loadFriendsActivities(accessToken, spDcCookie: spDcCookie, showLoading: showLoading));
    }
    
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  /// Silent refresh - updates data without showing loading indicators
  Future<void> silentRefresh(String accessToken, {String? spDcCookie}) async {
    _isRefreshing = true;
    notifyListeners();
    
    try {
      await refreshData(accessToken, spDcCookie: spDcCookie, showLoading: false);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Fast initial load - shows skeleton while loading basic data, then loads detailed info
  Future<void> fastInitialLoad(String accessToken, {String? spDcCookie}) async {
    try {
      // First, show skeleton loading
      if (_friendsActivities.isEmpty) {
        _isSkeletonLoading = true;
        notifyListeners();
        
        // Small delay to show skeleton
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Load basic friends activities data (fast mode)
      if (spDcCookie != null) {
        await loadFriendsActivities(
          accessToken, 
          spDcCookie: spDcCookie, 
          showSkeleton: _friendsActivities.isEmpty
        );
        
        // After fast load, enhance with detailed info in background
        _enhanceActivitiesInBackground(accessToken, spDcCookie);
      }
      
      _lastUpdated = DateTime.now();
      notifyListeners();
    } catch (e) {
      print('❌ Error during fast initial load: $e');
      _error = e.toString();
      _isSkeletonLoading = false;
      notifyListeners();
    }
  }

  /// Enhances activities with detailed information in the background
  Future<void> _enhanceActivitiesInBackground(String accessToken, String spDcCookie) async {
    // Wait a bit to let the UI settle
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      print('🔄 Enhancing activities with detailed info...');
      // Load detailed activities (with duration checks)
      final detailedActivities = await _buddyService.getFriendActivity(
        spDcCookie, 
        oauthAccessToken: accessToken,
        fastLoad: false // Full load with duration checks
      );
      
      if (detailedActivities.isNotEmpty) {
        _friendsActivities = detailedActivities;
        _lastUpdated = DateTime.now();
        notifyListeners();
        print('✅ Enhanced ${detailedActivities.length} activities with detailed info');
      }
    } catch (e) {
      print('❌ Failed to enhance activities: $e');
      // Don't update error state since we already have basic data
    }
  }

  /// Full refresh - shows loading indicators during data fetch
  Future<void> fullRefresh(String accessToken, {String? spDcCookie}) async {
    await refreshData(accessToken, spDcCookie: spDcCookie, showLoading: true);
  }
} 