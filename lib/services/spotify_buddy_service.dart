import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/models/activity.dart';
import 'package:playtivity/models/user.dart';
import 'package:playtivity/models/track.dart';
import 'package:playtivity/models/playlist.dart';
import 'package:playtivity/models/artist.dart';
import 'http_interceptor.dart';
import 'app_logger.dart';
import 'api_retry_service.dart';
import 'cache_service.dart';
import 'lru_cache_service.dart';
import 'debounced_refresh_service.dart';
import '../constants/api_constants.dart';
import '../constants/app_constants.dart';
// import 'package:playtivity/services/spotify_service.dart';

class SpotifyBuddyService {
  
  // Singleton pattern
  static SpotifyBuddyService? _instance;
  static SpotifyBuddyService get instance {
    _instance ??= SpotifyBuddyService._internal();
    return _instance!;
  }
  
  // Private constructor for singleton
  SpotifyBuddyService._internal() {
    // Initialize LRU caches with optimal sizes for performance
    _trackDurationCache = LRUCache<String, int>(500); // 500 tracks
    _artistDetailsCache = LRUCache<String, Map<String, dynamic>>(200); // 200 artists
    
    // Load persistent cache data
    _loadTrackDurationCache();
    _loadArtistDetailsCache();
  }
  
  // Public factory constructor that returns the singleton
  factory SpotifyBuddyService() => instance;
  
  // Cache for complete cookie string
  String? _completeCookieString;
  
  // New: Direct Bearer token support (bypasses TOTP generation)
  String? _directBearerToken;
  
  // New: Client token storage
  String? _clientToken;
    // Spotify service for fetching track details
  // final SpotifyService _spotifyService = SpotifyService();
  
  // High-performance LRU caches with automatic memory management
  late final LRUCache<String, int> _trackDurationCache;
  late final LRUCache<String, Map<String, dynamic>> _artistDetailsCache;
  
  // Track if cache has been modified since last save
  bool _cacheModified = false;
  bool _artistCacheModified = false;
  
  // Cache for buddy list activities to reduce API hits
  List<Activity>? _cachedBuddyActivities;
  DateTime? _lastBuddyListFetch;
  
  // Cache duration - refresh every 1.5 minutes
  static const Duration _buddyListCacheDuration = Duration(minutes: 1, seconds: 30);


  /// Loads track duration cache from SharedPreferences
  Future<void> _loadTrackDurationCache() async {
    try {
      const cacheKey = 'track_duration_cache';
      final cacheData = await CacheService.loadJson(cacheKey);
      
      if (cacheData != null) {
        cacheData.forEach((key, value) {
          if (value is int) {
            _trackDurationCache.put(key, value);
          }
        });
        AppLogger.spotify('📖 Loaded ${_trackDurationCache.length} track durations from cache');
      }
    } catch (e) {
      AppLogger.spotify('❌ Error loading track duration cache: $e');
    }
  }

  /// Saves track duration cache to SharedPreferences
  Future<void> _saveTrackDurationCache() async {
    try {
      // Convert LRU cache to Map for JSON serialization
      final cacheData = <String, int>{};
      for (final key in _trackDurationCache.keys) {
        final value = _trackDurationCache.get(key);
        if (value != null) {
          cacheData[key] = value;
        }
      }
      
      const cacheKey = 'track_duration_cache';
      await CacheService.saveJson(cacheKey, cacheData);
      AppLogger.spotify('💾 Saved ${cacheData.length} track durations to cache');
    } catch (e) {
      AppLogger.spotify('❌ Error saving track duration cache: $e');
    }
  }

  /// Clears the track duration cache (both memory and storage)
  Future<void> clearTrackDurationCache() async {
    try {
      _trackDurationCache.clear();
      _cacheModified = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trackDurationCacheKey);
      AppLogger.spotify('🗑️ Cleared track duration cache');
    } catch (e) {
      AppLogger.spotify('❌ Error clearing track duration cache: $e');
    }
  }

  /// Clears the buddy list cache to force a fresh fetch on next request
  void clearBuddyListCache() {
    _cachedBuddyActivities = null;
    _lastBuddyListFetch = null;
    AppLogger.spotify('🗑️ Cleared buddy list cache - next request will fetch fresh data');
  }

  /// Gets information about the current buddy list cache status
  Map<String, dynamic> getBuddyListCacheStatus() {
    final now = DateTime.now();
    final hasCache = _cachedBuddyActivities != null && _lastBuddyListFetch != null;
    
    if (!hasCache) {
      return {
        'hasCache': false,
        'cacheAge': null,
        'activityCount': 0,
        'shouldRefresh': true,
      };
    }
    
    final cacheAge = now.difference(_lastBuddyListFetch!);
    return {
      'hasCache': true,
      'cacheAge': cacheAge.inSeconds,
      'activityCount': _cachedBuddyActivities!.length,
      'shouldRefresh': _shouldRefreshBuddyList(),
      'lastFetch': _lastBuddyListFetch!.toIso8601String(),
    };
  }

  /// Fetches track duration from Spotify API using stored bearer token
  Future<int?> _getTrackDuration(String trackUri) async {
    return ApiRetryService.retryApiCall(
      () async {
        // Load cache from storage if not already loaded
        if (_trackDurationCache.isEmpty) {
          await _loadTrackDurationCache();
        }
        
        // Check cache first
        if (_trackDurationCache.containsKey(trackUri)) {
          AppLogger.spotify('💾 Using cached duration for track: $trackUri');
          return _trackDurationCache.get(trackUri);
        }
        
        // Extract track ID from URI (spotify:track:id)
        final trackId = trackUri.split(':').last;
        
        // Get Bearer token
        final bearerToken = getBearerToken();
        
        final url = 'https://api.spotify.com/v1/tracks/$trackId';
        final headers = {
          'Authorization': 'Bearer $bearerToken',
        };

        final response = await HttpInterceptor.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final durationMs = data['duration_ms'] as int?;
          
          if (durationMs != null) {
            // Cache the duration in memory
            _trackDurationCache.put(trackUri, durationMs);
            _cacheModified = true;

            return durationMs;
          }
        } else {
          throw Exception('Failed to fetch track duration: ${response.statusCode} - ${response.body}');
        }
        
        throw Exception('Track duration not found in response');
      },
      operation: 'Get Track Duration',
    );
  }

  /// Sets the Bearer token and headers directly (bypasses TOTP generation)
  void setBearerToken(String bearerToken, Map<String, String> headers) {
    AppLogger.spotify('🔧 setBearerToken called with:');
    AppLogger.spotify('   - bearerToken: ${bearerToken.substring(0, 20)}... (length: ${bearerToken.length})');
    AppLogger.spotify('   - headers keys: ${headers.keys.join(', ')}');
    
    _directBearerToken = bearerToken;
    
    // Store the complete cookie string
    _completeCookieString = headers['Cookie'] ?? '';
    
    // Store the client token if present
    if (headers['client-token'] != null) {
      _clientToken = headers['client-token'];
      AppLogger.spotify('✅ Client token stored (length: ${_clientToken?.length ?? 0})');
    }
    
    AppLogger.spotify('✅ Bearer token and headers set directly');
    AppLogger.spotify('   Token length: ${bearerToken.length}');
    AppLogger.spotify('   Headers: ${headers.keys.join(', ')}');
    AppLogger.spotify('   Cookie key exists: ${headers.containsKey('Cookie')}');
    AppLogger.spotify('   Cookie value: ${headers['Cookie']?.substring(0, 100) ?? 'null'}...');
    AppLogger.spotify('   Cookie length: ${_completeCookieString?.length ?? 0}');
    AppLogger.spotify('   Final _completeCookieString: ${_completeCookieString?.isNotEmpty == true ? '${_completeCookieString!.substring(0, 100)}...' : 'EMPTY'}');
    AppLogger.spotify('_directBearerToken stored: ${_directBearerToken?.substring(0, 20)}...');
    AppLogger.spotify('_clientToken stored: ${_clientToken != null ? '${_clientToken!.substring(0, 20)}...' : 'null'}');
  }

  /// Gets the current Bearer token (direct only)
  String? getBearerToken() {
    if (_directBearerToken != null && _directBearerToken!.isNotEmpty) {
      return _directBearerToken;
    }
    return null; // Return null instead of throwing exception
  }

  /// Gets the complete cookie string
  String? getCookieString() {
    return _completeCookieString;
  }

  /// Gets the client token
  String? getClientToken() {
    if (_clientToken != null && _clientToken!.isNotEmpty) {
      AppLogger.spotify('✅ Using stored client token');
      return _clientToken;
    }
    AppLogger.spotify('❌ No client token available');
    return null;
  }

  /// Clears the stored Bearer token and headers
  void clearBearerToken() {
    AppLogger.spotify('🗑️ Clearing all SpotifyBuddyService state...');
    
    // Clear authentication tokens
    _directBearerToken = null;
    _completeCookieString = null;
    _clientToken = null;
    
    // Clear all cached data to prevent stale state
    clearBuddyListCache();
    _trackDurationCache.clear();
    _artistDetailsCache.clear();
    _cacheModified = false;
    _artistCacheModified = false;
    
    AppLogger.spotify('✅ Cleared Bearer token, headers, and all cached data');
  }



  /// Determines if a friend is currently playing based on timestamp and song duration
  bool _isCurrentlyPlaying(Map<String, dynamic> friend, {int? durationMs}) {
    try {
      final timestamp = friend['timestamp'];
      final track = friend['track'];
      final userName = friend['user']?['display_name'] ?? 'Unknown';
      
      if (timestamp == null || track == null) {
        AppLogger.spotify('❌ $userName: Missing timestamp or track data');
        return false;
      }
      
      // Get song duration in milliseconds - use provided duration or try to get from track data
      final trackDurationMs = durationMs ?? track['duration_ms'];
      if (trackDurationMs == null) {
        AppLogger.spotify('❌ $userName: Missing duration_ms in track data and no duration provided');
        AppLogger.spotify('🔍 Track data: $track');
        return false;
      }
      
      // Convert timestamp to DateTime
      final friendTimestamp = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final currentTime = DateTime.now();
      
      // Calculate elapsed time since the friend started playing
      final elapsedMs = currentTime.difference(friendTimestamp).inMilliseconds;
      
      // Friend is currently playing if elapsed time is less than song duration
      // Add a small buffer (5 seconds) to account for network delays
      final isPlaying = elapsedMs >= 0 && elapsedMs < (trackDurationMs + 5000);
      
      return isPlaying;
    } catch (e) {
      AppLogger.spotify('❌ Error calculating playback status: $e');
      return false;
    }
  }
  
  /// Checks if we should refresh the buddy list cache based on cache expiration or track completion
  bool _shouldRefreshBuddyList() {
    final now = DateTime.now();
    
    // If no cache exists or cache is older than 1.5 minutes, refresh
    if (_cachedBuddyActivities == null || _lastBuddyListFetch == null) {
      AppLogger.spotify('📊 Cache refresh needed: No cached data');
      return true;
    }
    
    // Check if cache has expired (1.5 minutes)
    final cacheAge = now.difference(_lastBuddyListFetch!);
    if (cacheAge >= _buddyListCacheDuration) {
      AppLogger.spotify('📊 Cache refresh needed: Cache expired (${cacheAge.inSeconds}s > ${_buddyListCacheDuration.inSeconds}s)');
      return true;
    }
    
    // Check if any currently playing track should have finished
    for (final activity in _cachedBuddyActivities!) {
      if (activity.type == ActivityType.track && 
          activity.isCurrentlyPlaying && 
          activity.track != null) {
        
        final trackStartTime = activity.timestamp;
        final trackDurationMs = activity.track!.durationMs;
        final elapsedMs = now.difference(trackStartTime).inMilliseconds;
        
        // If track should have finished (with 5 second buffer), refresh cache
        if (elapsedMs >= (trackDurationMs + 5000)) {
          AppLogger.spotify('📊 Cache refresh needed: Track "${activity.track!.name}" by ${activity.user.displayName} should have finished');
          return true;
        }
      }
    }
    
    AppLogger.spotify('📊 Cache still valid: Age=${cacheAge.inSeconds}s, no tracks finished');
    return false;
  }
  
  /// Generates a curl command for debugging API requests
  String _generateCurlCommand(String method, String url, Map<String, String> headers, {String? body}) {
    final buffer = StringBuffer();
    buffer.write("curl '$url'");
    
    // Add headers
    headers.forEach((key, value) {
      // Escape single quotes in values
      final escapedValue = value.replaceAll("'", "'\\''");
      buffer.write(" \\\n  -H '$key: $escapedValue'");
    });
    
    // Add method if not GET
    if (method != 'GET') {
      buffer.write(" \\\n  -X $method");
    }
    
    // Add body if present
    if (body != null && body.isNotEmpty) {
      // Escape single quotes in body
      final escapedBody = body.replaceAll("'", "'\\''");
      buffer.write(" \\\n  --data-raw '$escapedBody'");
    }
    
    return buffer.toString();
  }

  Future<List<Activity>> getFriendActivity({
    bool fastLoad = false,
    Function(List<Activity>)? onActivitiesUpdate,
  }) async {
    AppLogger.spotify('🔍 getFriendActivity called');
    
    // The new buddylist endpoint only requires Bearer token authentication
    String? accessToken = getBearerToken();
    if (accessToken == null) {
      throw Exception('No Bearer token available - please authenticate first');
    }
    // Check if we can use cached data
    if (!_shouldRefreshBuddyList()) {
      AppLogger.spotify('✅ Using cached buddy list data');
      return _cachedBuddyActivities!;
    }
    
    return ApiRetryService.retryApiCall(
      () async {
        // Preload track duration cache only if not doing fast load
        if (!fastLoad && _trackDurationCache.isEmpty) {
          await _loadTrackDurationCache();
        }
        
        AppLogger.spotify('✅ Got access token, fetching friend activity...');
        
        // Use the new buddylist endpoint - no hash parameter needed
        final url = '$_baseUrl/presence-view/v1/buddylist';
        final headers = {
          'Authorization': 'Bearer $accessToken',
        };

        try {
          final response = await HttpInterceptor.get(
            Uri.parse(url),
            headers: headers,
          );

          // Only log status code for debugging
          // Handle unauthorized response - clear cache and retry once
          if (response.statusCode == 401 || response.statusCode == 403) {
            _completeCookieString = null;
            
            // Use the new buddylist endpoint for retry as well
            final retryUrl = '$_baseUrl/presence-view/v1/buddylist';
            final retryHeaders = {
              'Authorization': 'Bearer $accessToken',
            };
            
            try {
              final retryResponse = await HttpInterceptor.get(
                Uri.parse(retryUrl),
                headers: retryHeaders,
              );
              
              if (retryResponse.statusCode == 200) {
                final activities = await _parseActivityResponse(
                  retryResponse.body, 
                  fastLoad: fastLoad,
                  onActivitiesUpdate: onActivitiesUpdate,
                );
                // Cache the successful response
                _cachedBuddyActivities = activities;
                _lastBuddyListFetch = DateTime.now();
                return activities;
              } else {
                throw Exception('Failed to fetch friend activity: ${retryResponse.statusCode}');
              }
            } catch (retryError) {
              throw Exception('Network error during retry: $retryError');
            }
          }

          if (response.statusCode == 200) {
            final activities = await _parseActivityResponse(
              response.body, 
              fastLoad: fastLoad,
              onActivitiesUpdate: onActivitiesUpdate,
            );
            // Cache the successful response
            _cachedBuddyActivities = activities;
            _lastBuddyListFetch = DateTime.now();
            return activities;
          } else {
            throw Exception('Failed to fetch friend activity: ${response.statusCode}');
          }
        } catch (e) {
          return [];
        }
      },
      operation: 'Get Friend Activity',
    );
  }

  Future<List<Activity>> _parseActivityResponse(
    String responseBody, {
    bool fastLoad = false,
    Function(List<Activity>)? onActivitiesUpdate,
  }) async {
    try {
      final data = json.decode(responseBody);
      final friends = data['friends'] as List?;
      
      if (friends != null) {
        final activities = <Activity>[];
        final tracksNeedingDuration = <int>[];
        
        // First pass: Create all activities with basic information
        for (int i = 0; i < friends.length; i++) {
          final friend = friends[i];
          final userInfo = friend['user'];
          final timestamp = friend['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          
          // Create User object
          final userUri = userInfo['uri'] ?? '';
          final userId = userUri.startsWith('spotify:user:') 
              ? userUri.substring('spotify:user:'.length)
              : userUri;
          
          final user = User(
            id: userId,
            displayName: userInfo['name'] ?? 'Unknown User',
            email: '', // Not available in buddy list API
            imageUrl: userInfo['imageUrl'],
            followers: 0, // Not available in buddy list API
            country: '', // Not available in buddy list API
          );
          
          // Check if this is a track or playlist activity
          final trackInfo = friend['track'];
          final playlistInfo = friend['playlist'];
          
          if (playlistInfo != null) {
            // For playlists, we can't calculate duration-based playback
            final playlist = Playlist(
              id: playlistInfo['uri']?.split(':').last ?? '',
              name: playlistInfo['name'] ?? 'Unknown Playlist',
              description: playlistInfo['description'],
              imageUrl: playlistInfo['imageUrl'],
              trackCount: playlistInfo['trackCount'] ?? 0,
              uri: playlistInfo['uri'] ?? '',
              ownerId: playlistInfo['owner']?['id'] ?? '',
              ownerName: playlistInfo['owner']?['name'] ?? 'Unknown',
              isPublic: playlistInfo['public'] ?? false,
            );
            
            activities.add(Activity(
              user: user,
              playlist: playlist,
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : DateTime.now().millisecondsSinceEpoch),
              isCurrentlyPlaying: false, // Can't determine for playlists
              type: ActivityType.playlist,
            ));
          } else if (trackInfo != null) {
            // Get track duration from cache or API response
            int? durationMs = trackInfo['duration_ms'];
            final trackUri = trackInfo['uri'] ?? '';
            bool isCurrentlyPlaying = false;
            
            // Check cache first for duration
            if (durationMs == null && trackUri.isNotEmpty && _trackDurationCache.containsKey(trackUri)) {
              durationMs = _trackDurationCache.get(trackUri);
            }
            
            // If we have duration, calculate if currently playing
            if (durationMs != null) {
              isCurrentlyPlaying = _isCurrentlyPlaying(friend, durationMs: durationMs);
            } else if (!fastLoad && trackUri.isNotEmpty) {
              // Mark this track as needing duration fetch
              tracksNeedingDuration.add(i);
            }
            
            // Create Track object - handle v2 API structure
            final albumInfo = trackInfo['album'] ?? {};
            final artistInfo = trackInfo['artist'] ?? {};
            
            final track = Track(
              id: trackInfo['uri'] ?? '',
              name: trackInfo['name'] ?? 'Unknown Track',
              artists: [artistInfo['name'] ?? 'Unknown Artist'],
              album: albumInfo['name'] ?? 'Unknown Album',
              albumUri: albumInfo['uri'],
              imageUrl: trackInfo['imageUrl'] ?? albumInfo['imageUrl'] ?? '',
              durationMs: durationMs ?? 0,
              uri: trackInfo['uri'] ?? '',
            );
            
            activities.add(Activity(
              user: user,
              track: track,
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : DateTime.now().millisecondsSinceEpoch),
              isCurrentlyPlaying: isCurrentlyPlaying,
              type: ActivityType.track,
            ));
          }
        }
        
        // Sort by timestamp - most recent first
        activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        // Second pass: Fetch missing track durations in background and update progressively
        if (tracksNeedingDuration.isNotEmpty && !fastLoad) {
          _fetchTrackDurationsProgressively(friends, activities, tracksNeedingDuration, onActivitiesUpdate);
        }
        
        // Save cache if it was modified
        if (_cacheModified) {
          await _saveTrackDurationCache();
          _cacheModified = false;
        }
        
        return activities;
      }
    } catch (e) {
      AppLogger.spotify('❌ Error parsing activity response: $e');
    }
    
    return [];
  }

  /// Fetches track durations progressively and updates activities as they become available
  void _fetchTrackDurationsProgressively(
    List<dynamic> friends,
    List<Activity> activities,
    List<int> tracksNeedingDuration,
    Function(List<Activity>)? onActivitiesUpdate,
  ) {
    // Run in background without blocking the main response
    Future.microtask(() async {
      AppLogger.spotify('🔄 Starting progressive track duration fetch for ${tracksNeedingDuration.length} tracks...');
      
      var updatedActivities = List<Activity>.from(activities);
      
      for (final friendIndex in tracksNeedingDuration) {
        try {
          final friend = friends[friendIndex];
          final trackInfo = friend['track'];
          final trackUri = trackInfo['uri'] ?? '';
          final userName = friend['user']?['name'] ?? 'Unknown';
          
          if (trackUri.isEmpty) continue;
          
          AppLogger.spotify('🔍 Fetching duration for track: $trackUri (user: $userName)');
          final durationMs = await _getTrackDuration(trackUri);
          
          if (durationMs != null) {
            // Find the corresponding activity and update it
            final activityIndex = updatedActivities.indexWhere((activity) => 
              activity.track?.uri == trackUri && 
              activity.user.displayName == userName
            );
            
            if (activityIndex != -1) {
              final oldActivity = updatedActivities[activityIndex];
              final isCurrentlyPlaying = _isCurrentlyPlaying(friend, durationMs: durationMs);
              
              // Create updated track with duration
              final updatedTrack = Track(
                id: oldActivity.track!.id,
                name: oldActivity.track!.name,
                artists: oldActivity.track!.artists,
                album: oldActivity.track!.album,
                albumUri: oldActivity.track!.albumUri,
                imageUrl: oldActivity.track!.imageUrl,
                durationMs: durationMs,
                uri: oldActivity.track!.uri,
              );
              
              // Create updated activity
              updatedActivities[activityIndex] = Activity(
                user: oldActivity.user,
                track: updatedTrack,
                timestamp: oldActivity.timestamp,
                isCurrentlyPlaying: isCurrentlyPlaying,
                type: oldActivity.type,
              );
              
              AppLogger.spotify('✅ Updated activity for $userName: ${oldActivity.track!.name} - Currently Playing: $isCurrentlyPlaying');
              
              // Update cached activities
              _cachedBuddyActivities = List<Activity>.from(updatedActivities);
              
              // Notify callback with updated activities
              if (onActivitiesUpdate != null) {
                onActivitiesUpdate(List<Activity>.from(updatedActivities));
              }
            }
          }
        } catch (e) {
          AppLogger.spotify('⚠️ Failed to fetch duration for track at index $friendIndex: $e');
        }
      }
      
      // Save cache if it was modified
      if (_cacheModified) {
        await _saveTrackDurationCache();
        _cacheModified = false;
      }
      
      AppLogger.spotify('✅ Completed progressive track duration fetch');
    });
  }

  // Enhanced mock data as fallback
  List<Activity> getMockActivities() {
    final mockContent = [
      {'type': 'track', 'name': 'Bohemian Rhapsody', 'artist': 'Queen', 'user': 'Alex'},
      {'type': 'playlist', 'name': 'Rock Classics', 'owner': 'Spotify', 'user': 'Sarah'},
      {'type': 'track', 'name': 'Hotel California', 'artist': 'Eagles', 'user': 'Mike'},
      {'type': 'playlist', 'name': 'Chill Vibes', 'owner': 'Emma', 'user': 'Emma'},
      {'type': 'track', 'name': 'Smells Like Teen Spirit', 'artist': 'Nirvana', 'user': 'Josh'},
      {'type': 'playlist', 'name': 'Workout Mix', 'owner': 'Josh', 'user': 'Lisa'},
      {'type': 'track', 'name': 'Purple Haze', 'artist': 'Jimi Hendrix', 'user': 'David'},
      {'type': 'playlist', 'name': 'Study Focus', 'owner': 'David', 'user': 'Anna'},
    ];

    final activities = List.generate(8, (index) {
      final content = mockContent[index % mockContent.length];
      final isPlaylist = content['type'] == 'playlist';
      
      // Create more realistic timestamps for testing the duration-based calculation
      final now = DateTime.now();
      DateTime activityTimestamp;
      bool shouldBeCurrentlyPlaying;
      
      if (index < 3) {
        // Recent activities that should be "currently playing"
        final secondsAgo = Random().nextInt(120) + 30; // 30 seconds to 2.5 minutes ago
        activityTimestamp = now.subtract(Duration(seconds: secondsAgo));
        shouldBeCurrentlyPlaying = true;
      } else if (index < 6) {
        // Activities that should have finished playing
        final minutesAgo = Random().nextInt(20) + 5; // 5-25 minutes ago
        activityTimestamp = now.subtract(Duration(minutes: minutesAgo));
        shouldBeCurrentlyPlaying = false;
      } else {
        // Very recent activities (within last 30 seconds)
        final secondsAgo = Random().nextInt(30);
        activityTimestamp = now.subtract(Duration(seconds: secondsAgo));
        shouldBeCurrentlyPlaying = true;
      }
      
      // Create User object
      final user = User(
        id: 'mock_user_$index',
        displayName: content['user']!,
        email: '${content['user']!.toLowerCase()}@example.com',
        imageUrl: null,
        followers: Random().nextInt(1000),
        country: 'US',
      );
      
      if (isPlaylist) {
        // Create Playlist object
        final playlist = Playlist(
          id: 'mock_playlist_$index',
          name: content['name']!,
          description: 'A great playlist for any occasion',
          imageUrl: 'https://picsum.photos/64/64?random=${index + 100}',
          trackCount: Random().nextInt(50) + 10,
          uri: 'spotify:playlist:mock_$index',
          ownerId: 'mock_owner_$index',
          ownerName: content['owner']!,
          isPublic: true,
        );
        
        return Activity(
          user: user,
          playlist: playlist,
          timestamp: activityTimestamp,
          isCurrentlyPlaying: shouldBeCurrentlyPlaying, // For playlists, use the intended status
          type: ActivityType.playlist,
        );
      } else {
        // Create Track object with realistic duration (3-5 minutes)
        final durationMs = (Random().nextInt(120) + 180) * 1000; // 3-5 minutes in ms
        final track = Track(
          id: 'mock_track_$index',
          name: content['name']!,
          artists: [content['artist']!],
          album: '${content['artist']} - Greatest Hits',
          albumUri: 'spotify:album:mock_album_$index',
          imageUrl: 'https://picsum.photos/64/64?random=$index',
          durationMs: durationMs,
          uri: 'spotify:track:mock_$index',
        );
        
        // For tracks, calculate if currently playing based on timestamp and duration
        final mockFriend = {
          'timestamp': activityTimestamp.millisecondsSinceEpoch,
          'track': {'duration_ms': durationMs},
          'user': {'display_name': content['user']!}
        };
        final calculatedPlaying = _isCurrentlyPlaying(mockFriend);
        
        return Activity(
          user: user,
          track: track,
          timestamp: activityTimestamp,
          isCurrentlyPlaying: calculatedPlaying,
          type: ActivityType.track,
        );
      }
    });
    
    // Sort by timestamp - most recent first
    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return activities;
  }




  /// Gets current user profile using web access token
  /// Gets user profile using Bearer token directly
  Future<User?> getCurrentUserProfileWithToken(String bearerToken) async {
    return ApiRetryService.retryApiCall(
      () async {
        AppLogger.spotify('🔄 Getting user profile with Bearer token...');
        
        final url = 'https://api.spotify.com/v1/me';
        final headers = {
          'Accept': 'application/json',
          'Authorization': 'Bearer $bearerToken',
          'Content-Type': 'application/json',
        };

        final response = await HttpInterceptor.get(
          Uri.parse(url),
          headers: headers,
        );

        AppLogger.spotify('📡 User profile API response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          AppLogger.spotify('✅ Successfully fetched user profile: ${data['display_name']}');
          
          return User.fromSpotifyApi(data);
        } else {
          throw Exception('Failed to fetch user profile: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get User Profile with Bearer Token',
    );
  }

  /// Gets user's top content (tracks and artists) using GraphQL API
  Future<Map<String, dynamic>?> getTopContent({
    String timeRange = 'SHORT_TERM', 
    int tracksLimit = 4, 
    int artistsLimit = 10,
    bool includeTopTracks = true,
    bool includeTopArtists = true,
  }) async {
    try {
      if (_completeCookieString == null) {
        throw Exception('No cookie string available - please authenticate first');
      }
      
      return await ApiRetryService.retryApiCall(
        () async {
          AppLogger.spotify('🔄 Getting top content with GraphQL API...');
          AppLogger.spotify('   - Time range: $timeRange');
          AppLogger.spotify('   - Tracks limit: $tracksLimit (enabled: $includeTopTracks)');
          AppLogger.spotify('   - Artists limit: $artistsLimit (enabled: $includeTopArtists)');
          
          // Get Bearer token (direct only)
          String? accessToken = getBearerToken();
          String? clientToken = getClientToken();
          
          if (accessToken == null) {
            throw Exception('Failed to get access token for top content');
          }

          AppLogger.spotify('✅ Got access token, fetching top content...');
          
          final url = 'https://api-partner.spotify.com/pathfinder/v2/query';
          final headers = {
            'accept': 'application/json',
            'accept-language': 'en',
            'app-platform': 'WebPlayer',
            'authorization': 'Bearer $accessToken',
            'cache-control': 'no-cache',
            'client-token': clientToken ?? _generateClientToken(),
            'content-type': 'application/json;charset=UTF-8',
            'dnt': '1',
            'origin': 'https://open.spotify.com',
            'pragma': 'no-cache',
            'priority': 'u=1, i',
            'referer': 'https://open.spotify.com/',
            'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
            'spotify-app-version': '1.2.67.546.ga043c80d',
            'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
            'Cookie': _completeCookieString!,
          };

          final requestBody = {
            'variables': {
              'includeTopArtists': includeTopArtists,
              'topArtistsInput': {
                'offset': 0,
                'limit': artistsLimit,
                'sortBy': 'AFFINITY',
                'timeRange': 'SHORT_TERM'
              },
              'includeTopTracks': includeTopTracks,
              'topTracksInput': {
                'offset': 0,
                'limit': tracksLimit,
                'sortBy': 'AFFINITY',
                'timeRange': 'SHORT_TERM'
              }
            },
            'operationName': 'userTopContent',
            'extensions': {
              'persistedQuery': {
                'version': 1,
                'sha256Hash': 'feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2'
              }
            }
          };

          final response = await HttpInterceptor.post(
            Uri.parse(url),
            headers: headers,
            body: json.encode(requestBody),
          );

          AppLogger.spotify('📡 Top content API response: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final topArtistsCount = data['data']?['me']?['profile']?['topArtists']?['totalCount'] ?? 0;
            final topTracksCount = data['data']?['me']?['profile']?['topTracks']?['totalCount'] ?? 0;
            AppLogger.spotify('✅ Successfully fetched top content (artists: $topArtistsCount, tracks: $topTracksCount)');
            return data;
          } else if (response.statusCode == 401 || response.statusCode == 403) {
            AppLogger.spotify('🔄 Access token unauthorized, clearing cache and retrying...');
            AppLogger.spotify('Response body: ${response.body}');
            _completeCookieString = null;
            
            // Retry with the same request
            final retryHeaders = {
              'accept': 'application/json',
              'accept-language': 'en',
              'app-platform': 'WebPlayer',
              'authorization': 'Bearer $accessToken',
              'cache-control': 'no-cache',
              'client-token': _generateClientToken(),
              'content-type': 'application/json;charset=UTF-8',
              'dnt': '1',
              'origin': 'https://open.spotify.com',
              'pragma': 'no-cache',
              'priority': 'u=1, i',
              'referer': 'https://open.spotify.com/',
              'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
              'sec-ch-ua-mobile': '?0',
              'sec-ch-ua-platform': '"Windows"',
              'sec-fetch-dest': 'empty',
              'sec-fetch-mode': 'cors',
              'sec-fetch-site': 'same-site',
              'spotify-app-version': '1.2.67.546.ga043c80d',
              'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
              'Cookie': _completeCookieString!,
            };
            
            try {
              // Log retry curl command for debugging
              AppLogger.spotify('📡 Retry request curl command:');
              AppLogger.spotify(_generateCurlCommand('POST', url, retryHeaders, body: json.encode(requestBody)));

              final retryResponse = await HttpInterceptor.post(
                Uri.parse(url),
                headers: retryHeaders,
                body: json.encode(requestBody),
              );
              
              AppLogger.spotify('📡 Retry response: ${retryResponse.statusCode}');
              
              if (retryResponse.statusCode == 200) {
                final data = json.decode(retryResponse.body);
                final topArtistsCount = data['data']?['me']?['profile']?['topArtists']?['totalCount'] ?? 0;
                final topTracksCount = data['data']?['me']?['profile']?['topTracks']?['totalCount'] ?? 0;
                AppLogger.spotify('✅ Successfully fetched top content on retry:');
                AppLogger.spotify('   - Total artists available: $topArtistsCount');
                AppLogger.spotify('   - Total tracks available: $topTracksCount');
                return data;
              } else {
                AppLogger.spotify('❌ Retry also failed with status: ${retryResponse.statusCode}');
                throw Exception('Failed to fetch top content: ${retryResponse.statusCode}');
              }
            } catch (retryError) {
              AppLogger.spotify('❌ Error during retry request: $retryError');
              throw Exception('Network error during retry: $retryError');
            }
          } else {
            AppLogger.spotify('❌ Failed to fetch top content: ${response.statusCode}');
            AppLogger.spotify('   Response body: ${response.body}');
            throw Exception('Failed to fetch top content: ${response.statusCode} - ${response.body}');
          }
        },
        operation: 'Get Top Content',
      );
    } catch (e) {
      AppLogger.spotify('❌ Error in getTopContent: $e');
      return null;
    }
  }

  /// Gets user's top tracks using the new GraphQL API
  Future<List<Track>> getTopTracks({String timeRange = 'medium_term', int limit = 20}) async {
    try {
      final gqlTimeRange = _convertTimeRangeToGraphQL(timeRange);
      final data = await getTopContent(
        timeRange: gqlTimeRange,
        tracksLimit: limit,
        includeTopTracks: true,
        includeTopArtists: false,
      );
      
      if (data == null) {
        AppLogger.spotify('⚠️ Failed to get top content data for tracks');
        return [];
      }
      
      final tracks = <Track>[];
      final topTracksItems = data['data']?['me']?['profile']?['topTracks']?['items'] as List? ?? [];
      
      for (final item in topTracksItems) {
        final trackData = item['data'];
        if (trackData != null) {
          final albumData = trackData['albumOfTrack'] ?? {};
          final artistsData = trackData['artists']?['items'] as List? ?? [];
          
          // Extract artist names
          final artistNames = artistsData
              .map((artist) => artist['profile']?['name'] as String? ?? 'Unknown Artist')
              .toList();
          
          // Get the best album image
          final coverArt = albumData['coverArt']?['sources'] as List? ?? [];
          String? imageUrl;
          if (coverArt.isNotEmpty) {
            // Try to find an image close to 300x300 first (good for display)
            for (final image in coverArt) {
              final height = image['height'] as int?;
              if (height != null && height == 300) {
                imageUrl = image['url'] as String?;
                break;
              }
            }
            // If no 300x300 found, use the highest resolution
            if (imageUrl == null) {
              var maxHeight = 0;
              for (final image in coverArt) {
                final height = image['height'] as int?;
                if (height != null && height > maxHeight) {
                  maxHeight = height;
                  imageUrl = image['url'] as String?;
                }
              }
            }
            // Fallback to first image if no suitable size found
            imageUrl ??= coverArt.first['url'] as String?;
          }
          
          tracks.add(Track(
            id: trackData['uri']?.split(':').last ?? '',
            name: trackData['name'] ?? 'Unknown Track',
            artists: artistNames,
            album: albumData['name'] ?? 'Unknown Album',
            albumUri: albumData['uri'],
            imageUrl: imageUrl ?? '',
            durationMs: trackData['duration']?['totalMilliseconds'] ?? 0,
            uri: trackData['uri'] ?? '',
          ));
        }
      }
      

      return tracks;
    } catch (e) {
      AppLogger.spotify('❌ Error in getTopTracks: $e');
      return [];
    }
  }

  /// Gets user's top artists using the new GraphQL API
  Future<List<Artist>> getTopArtists({String timeRange = 'medium_term', int limit = 20}) async {
    try {
      final gqlTimeRange = _convertTimeRangeToGraphQL(timeRange);
      final data = await getTopContent(
        timeRange: gqlTimeRange,
        artistsLimit: limit,
        includeTopTracks: false,
        includeTopArtists: true,
      );
      
      if (data == null) {
        AppLogger.spotify('⚠️ Failed to get top content data for artists');
        return [];
      }
      
      // Load artist details cache if not already loaded
      if (_artistDetailsCache.isEmpty) {
        await _loadArtistDetailsCache();
      }
      
      final artists = <Artist>[];
      final topArtistsItems = data['data']?['me']?['profile']?['topArtists']?['items'] as List? ?? [];
      
      for (final item in topArtistsItems) {
        final artistData = item['data'];
        if (artistData != null) {
          // Get the best artist image
          final avatarImages = artistData['visuals']?['avatarImage']?['sources'] as List? ?? [];
          String? imageUrl;
          if (avatarImages.isNotEmpty) {
            // Try to find a 320x320 image first (good balance of quality and size)
            for (final image in avatarImages) {
              final height = image['height'] as int?;
              if (height != null && height == 320) {
                imageUrl = image['url'] as String?;
                break;
              }
            }
            // If no 320x320 found, use the highest resolution
            if (imageUrl == null) {
              var maxHeight = 0;
              for (final image in avatarImages) {
                final height = image['height'] as int?;
                if (height != null && height > maxHeight) {
                  maxHeight = height;
                  imageUrl = image['url'] as String?;
                }
              }
            }
            // Fallback to first image if no suitable size found
            imageUrl ??= avatarImages.first['url'] as String?;
          }
          
          final artistId = artistData['uri']?.split(':').last ?? '';
          
          // Check cache first for artist details
          int followers = -1; // Use -1 to indicate not loaded yet
          List<String> genres = [];
          int popularity = 0;
          
          if (_artistDetailsCache.containsKey(artistId)) {
            final cachedDetails = _artistDetailsCache[artistId]!;
            followers = cachedDetails['followers'] ?? -1;
            genres = (cachedDetails['genres'] as List?)?.map((g) => g.toString()).toList() ?? [];
            popularity = cachedDetails['popularity'] ?? 0;

          }
          
          artists.add(Artist(
            id: artistId,
            name: artistData['profile']?['name'] ?? 'Unknown Artist',
            imageUrl: imageUrl,
            followers: followers,
            genres: genres,
            popularity: popularity,
            uri: artistData['uri'] ?? '',
          ));
        }
      }
      

      
      return artists;
    } catch (e) {
      AppLogger.spotify('❌ Error in getTopArtists: $e');
      return [];
    }
  }

  /// Gets user's top artists and fetches missing details in background
  Future<List<Artist>> getTopArtistsWithDetails({
    String timeRange = 'medium_term', 
    int limit = 20,
    Function(List<Artist>)? onArtistDetailsUpdate,
  }) async {
    // First get the basic artist list
    final artists = await getTopArtists(timeRange: timeRange, limit: limit);
    
    // Fetch missing details in background with callback
    _fetchMissingArtistDetails(artists, onUpdate: onArtistDetailsUpdate);
    
    return artists;
  }

  /// Fetches missing artist details in background and updates cache
  Future<List<Artist>> _fetchMissingArtistDetails(List<Artist> artists, {Function(List<Artist>)? onUpdate}) async {
    final missingIds = <String>[];
    
    for (final artist in artists) {
      if (artist.followers == -1) { // Not loaded yet
        missingIds.add(artist.id);
      }
    }
    
    if (missingIds.isEmpty) {
      return artists;
    }
    
    var updatedArtists = List<Artist>.from(artists);
    
    for (final artistId in missingIds) {
      try {
        final artistDetails = await _getArtistDetails(artistId);
        if (artistDetails != null) {
          _artistDetailsCache[artistId] = {
            'followers': artistDetails['followers']?['total'] ?? 0,
            'genres': artistDetails['genres'] ?? [],
            'popularity': artistDetails['popularity'] ?? 0,
            'cached_at': DateTime.now().millisecondsSinceEpoch,
          };
          _artistCacheModified = true;
          
          // Update the artist in the list
          final artistIndex = updatedArtists.indexWhere((a) => a.id == artistId);
          if (artistIndex != -1) {
            final oldArtist = updatedArtists[artistIndex];
            updatedArtists[artistIndex] = Artist(
              id: oldArtist.id,
              name: oldArtist.name,
              imageUrl: oldArtist.imageUrl,
              followers: artistDetails['followers']?['total'] ?? 0,
              genres: (artistDetails['genres'] as List?)?.map((g) => g.toString()).toList() ?? [],
              popularity: artistDetails['popularity'] ?? 0,
              uri: oldArtist.uri,
            );
            

            
            // Notify callback with updated list
            if (onUpdate != null) {
              onUpdate(List<Artist>.from(updatedArtists));
            }
          }
        }
      } catch (e) {
        AppLogger.spotify('⚠️ Failed to fetch details for artist $artistId: $e');
        // Cache a placeholder to avoid repeated failures
        _artistDetailsCache[artistId] = {
          'followers': 0,
          'genres': [],
          'popularity': 0,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'failed': true,
        };
        _artistCacheModified = true;
      }
    }
    
    // Save updated cache
    if (_artistCacheModified) {
      await _saveArtistDetailsCache();
      _artistCacheModified = false;
    }
    
    return updatedArtists;
  }

  /// Fetches detailed artist information from Spotify Web API
  Future<Map<String, dynamic>?> _getArtistDetails(String artistId) async {
    return ApiRetryService.retryApiCall(
      () async {
        // Get Bearer token
        final bearerToken = getBearerToken();
        
        final url = 'https://api.spotify.com/v1/artists/$artistId';
        final headers = {
          'Authorization': 'Bearer $bearerToken',
        };

        final response = await HttpInterceptor.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return data;
        } else {
          throw Exception('Failed to fetch artist details: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get Artist Details',
    );
  }

  /// Loads artist details cache from SharedPreferences
  Future<void> _loadArtistDetailsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_artistDetailsCacheKey);
      
      if (cacheJson != null) {
        final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
        _artistDetailsCache.clear();
        
        // Convert and validate cache entries
        cacheData.forEach((artistId, details) {
          if (details is Map<String, dynamic>) {
            final cachedAt = details['cached_at'] as int?;
            final now = DateTime.now().millisecondsSinceEpoch;
            
            // Cache expires after 7 days for artist details (they don't change often)
            if (cachedAt != null && (now - cachedAt) < (7 * 24 * 60 * 60 * 1000)) {
              _artistDetailsCache[artistId] = Map<String, dynamic>.from(details);
            } else {

            }
          }
        });
        

      }
    } catch (e) {
      AppLogger.spotify('⚠️ Failed to load artist details cache: $e');
      _artistDetailsCache.clear();
    }
  }

  /// Saves artist details cache to SharedPreferences
  Future<void> _saveArtistDetailsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_artistDetailsCache);
      await prefs.setString(_artistDetailsCacheKey, cacheJson);
      AppLogger.spotify('💾 Saved ${_artistDetailsCache.length} artist details to cache');
    } catch (e) {
      AppLogger.spotify('⚠️ Failed to save artist details cache: $e');
    }
  }

  /// Converts time range from REST API format to GraphQL format
  String _convertTimeRangeToGraphQL(String timeRange) {
    // Always return SHORT_TERM as that's what works with the current GraphQL schema
    return 'SHORT_TERM';
  }

  /// Generates a client token for the GraphQL API
  /// This is a fallback in case we don't have an intercepted token
  String _generateClientToken() {
    AppLogger.spotify('⚠️ Using fallback client token - this should be replaced with an intercepted token');
    // This is a placeholder - the actual client token generation is complex
    // For now, we'll use a static token from the example
    return 'AAAyrFCYuQiGGFsq0OYbkiotiZ9YtDPzdjemsDOtMJ6msHslHFxskOjd1h1q28igZTPhiB+n++o4n7/QkdHbIuzznY/QOKMesZKLlV83stuo8yn7hiiDN1R7b0HyInceiDZUgEPotzcBSM7v9ff76LEOJ53Hxl4W8qp+bwi+WAMlKSG6LSKb4905Tyqj0p2nsnWblSZVUw+Lj7huYgvu2y4istr4/zCyTIed9nI6ys3M2C8yhYfF1+5PC58l5gwGasCb7J7EikdPOfjBXZlMfMfh3gnOP4mK1ITzqmfaevpbrZDkJpspdzZFtYJT2eax';
  }
}