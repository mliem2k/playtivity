import 'package:flutter/material.dart';
import '../services/spotify_buddy_service.dart';
import '../services/spotify_service.dart';
import '../models/track.dart';
import '../models/activity.dart';
import '../models/artist.dart';

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
  List<Track> get topTracks => _topTracks;
  List<Artist> get topArtists => _topArtists;
  List<Activity> get friendsActivities => _friendsActivities;
  Track? get currentlyPlaying => _currentlyPlaying;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isSkeletonLoading => _isSkeletonLoading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;



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
          fastLoad: useFastLoad
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
        if (errorMessage.contains('No Bearer token available') || 
            errorMessage.contains('No cookie string available') ||
            errorMessage.contains('401') ||
            errorMessage.contains('403')) {
          print('🔐 Authentication error detected, may need re-authentication');
          _error = 'Authentication expired. Please login again.';
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
    _topTracks = [];
    _topArtists = [];
    _friendsActivities = [];
    _currentlyPlaying = null;
    _isLoading = false;
    _isRefreshing = false;
    _isSkeletonLoading = false;
    _error = null;
    _lastUpdated = null;
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
      
      // Check if this is an authentication error
      final errorMessage = e.toString();
      if (errorMessage.contains('No Bearer token available') || 
          errorMessage.contains('No cookie string available') ||
          errorMessage.contains('401') ||
          errorMessage.contains('403')) {
        print('🔐 Authentication error detected during enhancement');
        _error = 'Authentication expired. Please login again.';
        notifyListeners();
      }
      // Don't update error state for other errors since we already have basic data
    }
  }

  /// Full refresh - shows loading indicators during data fetch
  Future<void> fullRefresh() async {
    await refreshData(showLoading: true);
  }
} 