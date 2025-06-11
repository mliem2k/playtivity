import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/models/activity.dart';
import 'package:playtivity/models/user.dart';
import 'package:playtivity/models/track.dart';
import 'package:playtivity/models/playlist.dart';
import 'package:playtivity/models/artist.dart';
// import 'package:playtivity/services/spotify_service.dart';

class SpotifyBuddyService {
  static const String _baseUrl = 'https://guc-spclient.spotify.com';
  
  // Singleton pattern
  static SpotifyBuddyService? _instance;
  static SpotifyBuddyService get instance {
    _instance ??= SpotifyBuddyService._internal();
    return _instance!;
  }
  
  // Private constructor for singleton
  SpotifyBuddyService._internal();
  
  // Public factory constructor that returns the singleton
  factory SpotifyBuddyService() => instance;
  
  // Cache for access token and complete cookie string to avoid repeated requests
  String? _cachedAccessToken;
  String? _completeCookieString;
  DateTime? _tokenExpiry;
  
  // New: Direct Bearer token support (bypasses TOTP generation)
  String? _directBearerToken;
  Map<String, String>? _savedHeaders;
    // Spotify service for fetching track details
  // final SpotifyService _spotifyService = SpotifyService();
  
  // In-memory cache for track durations
  final Map<String, int> _trackDurationCache = {};
  
  // Track if cache has been modified since last save
  bool _cacheModified = false;
  
  // SharedPreferences key for persistent track duration cache
  static const String _trackDurationCacheKey = 'track_duration_cache';
  
  // In-memory cache for artist details (followers, genres, popularity)
  final Map<String, Map<String, dynamic>> _artistDetailsCache = {};
  
  // Track if artist cache has been modified since last save
  bool _artistCacheModified = false;
  
  // SharedPreferences key for persistent artist details cache
  static const String _artistDetailsCacheKey = 'artist_details_cache';
  
  // Cache for buddy list activities to reduce API hits
  List<Activity>? _cachedBuddyActivities;
  DateTime? _lastBuddyListFetch;
  
  // Cache duration - refresh every 1.5 minutes
  static const Duration _buddyListCacheDuration = Duration(minutes: 1, seconds: 30);


  /// Loads track duration cache from SharedPreferences
  Future<void> _loadTrackDurationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_trackDurationCacheKey);
      
      if (cacheJson != null) {
        final cacheData = json.decode(cacheJson) as Map<String, dynamic>;
        _trackDurationCache.clear();
        cacheData.forEach((key, value) {
          _trackDurationCache[key] = value as int;
        });
        print('📦 Loaded ${_trackDurationCache.length} cached track durations');
      }
    } catch (e) {
      print('❌ Error loading track duration cache: $e');
    }
  }

  /// Saves track duration cache to SharedPreferences
  Future<void> _saveTrackDurationCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_trackDurationCache);
      await prefs.setString(_trackDurationCacheKey, cacheJson);
      print('💾 Saved ${_trackDurationCache.length} track durations to cache');
    } catch (e) {
      print('❌ Error saving track duration cache: $e');
    }
  }

  /// Clears the track duration cache (both memory and storage)
  Future<void> clearTrackDurationCache() async {
    try {
      _trackDurationCache.clear();
      _cacheModified = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trackDurationCacheKey);
      print('🗑️ Cleared track duration cache');
    } catch (e) {
      print('❌ Error clearing track duration cache: $e');
    }
  }

  /// Clears the buddy list cache to force a fresh fetch on next request
  void clearBuddyListCache() {
    _cachedBuddyActivities = null;
    _lastBuddyListFetch = null;
    print('🗑️ Cleared buddy list cache - next request will fetch fresh data');
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
    return _retryApiCall(
      () async {
        // Load cache from storage if not already loaded
        if (_trackDurationCache.isEmpty) {
          await _loadTrackDurationCache();
        }
        
        // Check cache first
        if (_trackDurationCache.containsKey(trackUri)) {
          print('💾 Using cached duration for track: $trackUri');
          return _trackDurationCache[trackUri];
        }
        
        // Extract track ID from URI (spotify:track:id)
        final trackId = trackUri.split(':').last;
        
        // Get Bearer token
        final bearerToken = getBearerToken();
        
        final url = 'https://api.spotify.com/v1/tracks/$trackId';
        final headers = {
          'Authorization': 'Bearer $bearerToken',
        };

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final durationMs = data['duration_ms'] as int?;
          
          if (durationMs != null) {
            // Cache the duration in memory
            _trackDurationCache[trackUri] = durationMs;
            _cacheModified = true;
            print('✅ Fetched and cached duration for track $trackId: ${(durationMs/1000).toStringAsFixed(1)}s');
            return durationMs;
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Authentication failed: ${response.statusCode} - Please login again');
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
    print('🔧 setBearerToken called with:');
    print('   - bearerToken: ${bearerToken.substring(0, 20)}... (length: ${bearerToken.length})');
    print('   - headers keys: ${headers.keys.join(', ')}');
    
    _directBearerToken = bearerToken;
    _savedHeaders = Map.from(headers);
    
    // Store the complete cookie string
    _completeCookieString = headers['Cookie'] ?? '';
    
    print('✅ Bearer token and headers set directly');
    print('   Token length: ${bearerToken.length}');
    print('   Headers: ${headers.keys.join(', ')}');
    print('   Cookie key exists: ${headers.containsKey('Cookie')}');
    print('   Cookie value: ${headers['Cookie']?.substring(0, 100) ?? 'null'}...');
    print('   Cookie length: ${_completeCookieString?.length ?? 0}');
    print('   Final _completeCookieString: ${_completeCookieString?.isNotEmpty == true ? _completeCookieString!.substring(0, 100) + '...' : 'EMPTY'}');
    print('   _directBearerToken stored: ${_directBearerToken?.substring(0, 20)}...');
  }

  /// Gets the current Bearer token (direct only)
  String? getBearerToken() {
    print('🔍 getBearerToken called:');
    print('   - _directBearerToken null: ${_directBearerToken == null}');
    print('   - _directBearerToken empty: ${_directBearerToken?.isEmpty ?? true}');
    print('   - _directBearerToken length: ${_directBearerToken?.length ?? 0}');
    print('   - _directBearerToken preview: ${_directBearerToken?.substring(0, 20) ?? 'null'}...');
    
    if (_directBearerToken != null && _directBearerToken!.isNotEmpty) {
      print('✅ Using direct Bearer token');
      return _directBearerToken;
    }
    
    print('❌ No Bearer token available');
    throw Exception('No Bearer token available - must authenticate first');
  }

  /// Gets the complete cookie string
  String? getCookieString() {
    return _completeCookieString;
  }

  /// Clears the stored Bearer token and headers
  void clearBearerToken() {
    _directBearerToken = null;
    _savedHeaders = null;
    _cachedAccessToken = null;
    _completeCookieString = null;
    _tokenExpiry = null;
    print('🗑️ Cleared Bearer token and headers');
  }



  /// Determines if a friend is currently playing based on timestamp and song duration
  bool _isCurrentlyPlaying(Map<String, dynamic> friend, {int? durationMs}) {
    try {
      final timestamp = friend['timestamp'];
      final track = friend['track'];
      final userName = friend['user']?['display_name'] ?? 'Unknown';
      
      if (timestamp == null || track == null) {
        print('❌ $userName: Missing timestamp or track data');
        return false;
      }
      
      // Get song duration in milliseconds - use provided duration or try to get from track data
      final trackDurationMs = durationMs ?? track['duration_ms'];
      if (trackDurationMs == null) {
        print('❌ $userName: Missing duration_ms in track data and no duration provided');
        print('🔍 Track data: $track');
        return false;
      }
      
      // Convert timestamp to DateTime
      final friendTimestamp = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final currentTime = DateTime.now();
      
      // Calculate elapsed time since the friend started playing
      final elapsedMs = currentTime.difference(friendTimestamp).inMilliseconds;
      
      print('🕐 $userName: timestamp=$timestamp, friendTime=${friendTimestamp.toIso8601String()}, now=${currentTime.toIso8601String()}');
      
      // Friend is currently playing if elapsed time is less than song duration
      // Add a small buffer (5 seconds) to account for network delays
      final isPlaying = elapsedMs >= 0 && elapsedMs < (trackDurationMs + 5000);
      
      print('⏱️  ${friend['user']?['display_name'] ?? 'Unknown'}: '
            'elapsed=${(elapsedMs/1000).toStringAsFixed(1)}s, '
            'duration=${(trackDurationMs/1000).toStringAsFixed(1)}s, '
            'playing=$isPlaying');
      
      return isPlaying;
    } catch (e) {
      print('❌ Error calculating playback status: $e');
      return false;
    }
  }
  
  /// Checks if we should refresh the buddy list cache based on cache expiration or track completion
  bool _shouldRefreshBuddyList() {
    final now = DateTime.now();
    
    // If no cache exists or cache is older than 1.5 minutes, refresh
    if (_cachedBuddyActivities == null || _lastBuddyListFetch == null) {
      print('📊 Cache refresh needed: No cached data');
      return true;
    }
    
    // Check if cache has expired (1.5 minutes)
    final cacheAge = now.difference(_lastBuddyListFetch!);
    if (cacheAge >= _buddyListCacheDuration) {
      print('📊 Cache refresh needed: Cache expired (${cacheAge.inSeconds}s > ${_buddyListCacheDuration.inSeconds}s)');
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
          print('📊 Cache refresh needed: Track "${activity.track!.name}" by ${activity.user.displayName} should have finished');
          return true;
        }
      }
    }
    
    print('📊 Cache still valid: Age=${cacheAge.inSeconds}s, no tracks finished');
    return false;
  }
  
  /// Generates a curl command for debugging API requests
  // String _generateCurlCommand(String method, String url, Map<String, String> headers, {String? body}) {
  //   final buffer = StringBuffer();
  //   buffer.write('curl -X $method');
  //   
  //   // Add headers
  //   headers.forEach((key, value) {
  //     buffer.write(' -H "$key: $value"');
  //   });
  //   
  //   // Add body if present
  //   if (body != null && body.isNotEmpty) {
  //     buffer.write(' -d \'$body\'');
  //   });
  //   
  //   // Add URL
  //   buffer.write(' "$url"');
  //   
  //   return buffer.toString();
  // }

  Future<List<Activity>> getFriendActivity({
    bool fastLoad = false,
    Function(List<Activity>)? onActivitiesUpdate,
  }) async {
    print('🔍 getFriendActivity called');
    
    // The new buddylist endpoint only requires Bearer token authentication
    String? accessToken = getBearerToken();
    if (accessToken == null) {
      throw Exception('No Bearer token available - please authenticate first');
    }
    // Check if we can use cached data
    if (!_shouldRefreshBuddyList()) {
      print('✅ Using cached buddy list data');
      return _cachedBuddyActivities!;
    }
    
    return _retryApiCall(
      () async {
        // Preload track duration cache only if not doing fast load
        if (!fastLoad && _trackDurationCache.isEmpty) {
          await _loadTrackDurationCache();
        }
        
        print('✅ Got access token, fetching friend activity...');
        
        // Use the new buddylist endpoint - no hash parameter needed
        final url = '$_baseUrl/presence-view/v1/buddylist';
        final headers = {
          'Authorization': 'Bearer $accessToken',
        };

        try {
          final response = await http.get(
            Uri.parse(url),
            headers: headers,
          );

          print('📡 Buddy list API response: ${response.statusCode}');
          print('📦 Response body: ${response.body}');

          // Handle unauthorized response - clear cache and retry once
          if (response.statusCode == 401 || response.statusCode == 403) {
            print('🔄 Access token unauthorized, clearing cache and retrying...');
            _cachedAccessToken = null;
            _completeCookieString = null;
            _tokenExpiry = null;
            
            // Use the new buddylist endpoint for retry as well
            final retryUrl = '$_baseUrl/presence-view/v1/buddylist';
            final retryHeaders = {
              'Authorization': 'Bearer $accessToken',
            };
            
            try {
              final retryResponse = await http.get(
                Uri.parse(retryUrl),
                headers: retryHeaders,
              );
              
              print('📡 Retry response: ${retryResponse.statusCode}');
              
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
              } else if (retryResponse.statusCode == 401 || retryResponse.statusCode == 403) {
                print('❌ Retry also failed with authentication error: ${retryResponse.statusCode}');
                throw Exception('Authentication failed: ${retryResponse.statusCode} - Please login again');
              } else {
                print('❌ Retry also failed with status: ${retryResponse.statusCode}');
                throw Exception('Failed to fetch friend activity: ${retryResponse.statusCode}');
              }
            } catch (retryError) {
              print('❌ Error during retry request: $retryError');
              if (retryError.toString().contains('Authentication failed')) {
                rethrow; // Re-throw authentication errors
              }
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
            print('💾 Cached buddy list data with ${activities.length} activities');
            return activities;
          } else if (response.statusCode == 401 || response.statusCode == 403) {
            throw Exception('Authentication failed: ${response.statusCode} - Please login again');
          } else {
            print('❌ Failed to fetch friend activity: ${response.statusCode} - ${response.body}');
            throw Exception('Failed to fetch friend activity: ${response.statusCode} - ${response.body}');
          }
        } catch (e) {
          print('❌ Error making buddy list API request: $e');
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
      print('📦 Buddy list response data: $data');
      final friends = data['friends'] as List?;
      
      if (friends != null) {
        print('👥 Found ${friends.length} friends in response');
        final activities = <Activity>[];
        final tracksNeedingDuration = <int>[];
        
        // First pass: Create all activities with basic information
        for (int i = 0; i < friends.length; i++) {
          final friend = friends[i];
          final userInfo = friend['user'];
          final timestamp = friend['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          
          print('👤 Processing friend: ${userInfo?['name']} at timestamp $timestamp');
          
          // Create User object
          // Extract user ID from URI (e.g., "spotify:user:214diupj3zah2rimagmv4wrgy" -> "214diupj3zah2rimagmv4wrgy")
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
          // final contextInfo = friend['context']; // v2 API includes context - not used yet
          
          if (playlistInfo != null) {
            print('🎵 Processing playlist activity: ${playlistInfo['name']}');
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
            print('🎵 Processing track activity: ${trackInfo['name']} by ${trackInfo['artist']?['name']}');
            
            // Get track duration from cache or API response
            int? durationMs = trackInfo['duration_ms'];
            final trackUri = trackInfo['uri'] ?? '';
            bool isCurrentlyPlaying = false;
            
            // Check cache first for duration
            if (durationMs == null && trackUri.isNotEmpty && _trackDurationCache.containsKey(trackUri)) {
              durationMs = _trackDurationCache[trackUri];
              print('💾 Using cached duration for track: $trackUri');
            }
            
            // If we have duration, calculate if currently playing
            if (durationMs != null) {
              isCurrentlyPlaying = _isCurrentlyPlaying(friend, durationMs: durationMs);
              print('🎵 Friend activity: ${userInfo['name']} - Currently Playing: $isCurrentlyPlaying');
            } else if (!fastLoad && trackUri.isNotEmpty) {
              // Mark this track as needing duration fetch
              tracksNeedingDuration.add(i);
              print('⏳ Track needs duration fetch: $trackUri');
            } else {
              // In fast load mode or no URI, assume not currently playing
              print('⚡ Fast load or no URI: ${userInfo['name']} - Skipping duration check');
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
          } else {
            print('⚠️ Friend ${userInfo?['name']} has no track or playlist data');
          }
        }
        
        // Sort by timestamp - most recent first
        activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        print('✅ Parsed ${activities.length} activities successfully (${tracksNeedingDuration.length} tracks need duration fetch)');
        
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
      } else {
        print('⚠️ No friends array found in response');
      }
    } catch (e) {
      print('❌ Error parsing activity response: $e');
      print('📦 Raw response: $responseBody');
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
      print('🔄 Starting progressive track duration fetch for ${tracksNeedingDuration.length} tracks...');
      
      var updatedActivities = List<Activity>.from(activities);
      
      for (final friendIndex in tracksNeedingDuration) {
        try {
          final friend = friends[friendIndex];
          final trackInfo = friend['track'];
          final trackUri = trackInfo['uri'] ?? '';
          final userName = friend['user']?['name'] ?? 'Unknown';
          
          if (trackUri.isEmpty) continue;
          
          print('🔍 Fetching duration for track: $trackUri (user: $userName)');
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
              
              print('✅ Updated activity for $userName: ${oldActivity.track!.name} - Currently Playing: $isCurrentlyPlaying');
              
              // Update cached activities
              _cachedBuddyActivities = List<Activity>.from(updatedActivities);
              
              // Notify callback with updated activities
              if (onActivitiesUpdate != null) {
                onActivitiesUpdate(List<Activity>.from(updatedActivities));
              }
            }
          }
        } catch (e) {
          print('⚠️ Failed to fetch duration for track at index $friendIndex: $e');
        }
      }
      
      // Save cache if it was modified
      if (_cacheModified) {
        await _saveTrackDurationCache();
        _cacheModified = false;
      }
      
      print('✅ Completed progressive track duration fetch');
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



  /// Retry logic for API calls with exponential backoff
  static Future<T> _retryApiCall<T>(
    Future<T> Function() apiCall, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 50),
    String operation = 'API call',
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        print('🔄 Attempting $operation (attempt ${attempt + 1}/$maxRetries)');
        return await apiCall().timeout(
          const Duration(seconds: 30), // 30 second timeout per request
          onTimeout: () {
            throw TimeoutException('Request timed out after 30 seconds', const Duration(seconds: 30));
          },
        );
      } catch (e) {
        attempt++;
        
        if (attempt >= maxRetries) {
          print('❌ $operation failed after $maxRetries attempts: $e');
          rethrow;
        }
        
        print('⚠️ $operation failed (attempt $attempt/$maxRetries): $e');
        print('🔄 Retrying in ${delay.inMilliseconds}ms...');
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round()); // Exponential backoff
      }
    }
    
    throw Exception('Failed to complete $operation after $maxRetries attempts');
  }

  /// Gets current user profile using web access token
  /// Gets user profile using Bearer token directly
  Future<User?> getCurrentUserProfileWithToken(String bearerToken) async {
    return _retryApiCall(
      () async {
        print('🔄 Getting user profile with Bearer token...');
        
        final url = 'https://api.spotify.com/v1/me';
        final headers = {
          'Accept': 'application/json',
          'Authorization': 'Bearer $bearerToken',
          'Content-Type': 'application/json',
        };

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        );

        print('📡 User profile API response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          print('✅ Successfully fetched user profile: ${data['display_name']}');
          
          return User.fromSpotifyApi(data);
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Authentication failed: ${response.statusCode} - Please login again');
        } else {
          throw Exception('Failed to fetch user profile: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get User Profile with Bearer Token',
    );
  }

  /// Helper method to get the best image URL from Spotify's images array
  String? _getBestImageUrl(List? images) {
    if (images == null || images.isEmpty) return null;
    
    // Look for a medium-sized image (around 64-300px)
    for (final image in images) {
      final height = image['height'] as int?;
      if (height != null && height >= 64 && height <= 300) {
        return image['url'] as String?;
      }
    }
    
    // Fallback to the first image if no medium size found
    return images.first['url'] as String?;
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
      
      return await _retryApiCall(
        () async {
          print('🔄 Getting top content with GraphQL API...');
          
          // Get Bearer token (direct only)
          String? accessToken = getBearerToken();
          
          if (accessToken == null) {
            throw Exception('Failed to get access token for top content');
          }

          print('✅ Got access token, fetching top content...');
          
          // Convert timeRange to GraphQL format
          final gqlTimeRange = _convertTimeRangeToGraphQL(timeRange);
          
          final url = 'https://api-partner.spotify.com/pathfinder/v2/query';
          final headers = {
            'accept': 'application/json',
            'accept-language': 'en',
            'app-platform': 'WebPlayer',
            'authorization': 'Bearer $accessToken',
            'client-token': _generateClientToken(),
            'content-type': 'application/json;charset=UTF-8',
            'dnt': '1',
            'origin': 'https://open.spotify.com',
            'priority': 'u=1, i',
            'referer': 'https://open.spotify.com/',
            'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
            'spotify-app-version': '1.2.66.322.g4d62a810',
            'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36',
            'Cookie': _completeCookieString!,
          };

          final requestBody = {
            'variables': {
              'includeTopArtists': includeTopArtists,
              'topArtistsInput': {
                'offset': 0,
                'limit': artistsLimit,
                'sortBy': 'AFFINITY',
                'timeRange': gqlTimeRange,
              },
              'includeTopTracks': includeTopTracks,
              'topTracksInput': {
                'offset': 0,
                'limit': tracksLimit,
                'sortBy': 'AFFINITY',
                'timeRange': gqlTimeRange,
              },
            },
            'operationName': 'userTopContent',
            'extensions': {
              'persistedQuery': {
                'version': 1,
                'sha256Hash': 'feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2',
              },
            },
          };

          final response = await http.post(
            Uri.parse(url),
            headers: headers,
            body: json.encode(requestBody),
          );

          print('📡 Top content GraphQL API response: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            print('✅ Successfully fetched top content');
            return data;
          } else if (response.statusCode == 401 || response.statusCode == 403) {
            throw Exception('Authentication failed: ${response.statusCode} - Please login again');
          } else {
            throw Exception('Failed to fetch top content: ${response.statusCode} - ${response.body}');
          }
        },
        operation: 'Get Top Content',
      );
    } catch (e) {
      print('❌ Error in getTopContent: $e');
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
        print('⚠️ Failed to get top content data for tracks');
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
            for (final image in coverArt) {
              final height = image['height'] as int?;
              if (height != null && height >= 300 && height <= 640) {
                imageUrl = image['url'] as String?;
                break;
              }
            }
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
      
      print('✅ Parsed ${tracks.length} top tracks from GraphQL response');
      return tracks;
    } catch (e) {
      print('❌ Error in getTopTracks: $e');
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
        print('⚠️ Failed to get top content data for artists');
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
            for (final image in avatarImages) {
              final height = image['height'] as int?;
              if (height != null && height >= 300 && height <= 640) {
                imageUrl = image['url'] as String?;
                break;
              }
            }
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
            print('💾 Using cached artist details for $artistId: $followers followers');
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
      
      print('✅ Parsed ${artists.length} top artists from GraphQL response');
      
      return artists;
    } catch (e) {
      print('❌ Error in getTopArtists: $e');
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
      print('✅ All artist details already cached');
      return artists;
    }
    
    print('🔄 Fetching details for ${missingIds.length} artists in background...');
    
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
            
            print('✅ Updated artist $artistId with ${artistDetails['followers']?['total']} followers');
            
            // Notify callback with updated list
            if (onUpdate != null) {
              onUpdate(List<Artist>.from(updatedArtists));
            }
          }
        }
      } catch (e) {
        print('⚠️ Failed to fetch details for artist $artistId: $e');
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
    return _retryApiCall(
      () async {
        // Get Bearer token
        final bearerToken = getBearerToken();
        
        final url = 'https://api.spotify.com/v1/artists/$artistId';
        final headers = {
          'Authorization': 'Bearer $bearerToken',
        };

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return data;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Authentication failed: ${response.statusCode} - Please login again');
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
              print('🗑️ Artist details cache expired for $artistId');
            }
          }
        });
        
        print('💾 Loaded ${_artistDetailsCache.length} artist details from cache');
      }
    } catch (e) {
      print('⚠️ Failed to load artist details cache: $e');
      _artistDetailsCache.clear();
    }
  }

  /// Saves artist details cache to SharedPreferences
  Future<void> _saveArtistDetailsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = json.encode(_artistDetailsCache);
      await prefs.setString(_artistDetailsCacheKey, cacheJson);
      print('💾 Saved ${_artistDetailsCache.length} artist details to cache');
    } catch (e) {
      print('⚠️ Failed to save artist details cache: $e');
    }
  }

  /// Converts time range from REST API format to GraphQL format
  String _convertTimeRangeToGraphQL(String timeRange) {
    switch (timeRange) {
      case 'short_term':
        return 'SHORT_TERM';
      case 'medium_term':
        return 'MEDIUM_TERM';
      case 'long_term':
        return 'LONG_TERM';
      default:
        return 'SHORT_TERM';
    }
  }

  /// Generates a client token for the GraphQL API
  /// This is a simplified version - in a real app, this would be more complex
  String _generateClientToken() {
    // This is a placeholder - the actual client token generation is complex
    // For now, we'll use a static token from the example
    return 'AAAyrFCYuQiGGFsq0OYbkiotiZ9YtDPzdjemsDOtMJ6msHslHFxskOjd1h1q28igZTPhiB+n++o4n7/QkdHbIuzznY/QOKMesZKLlV83stuo8yn7hiiDN1R7b0HyInceiDZUgEPotzcBSM7v9ff76LEOJ53Hxl4W8qp+bwi+WAMlKSG6LSKb4905Tyqj0p2nsnWblSZVUw+Lj7huYgvu2y4istr4/zCyTIed9nI6ys3M2C8yhYfF1+5PC58l5gwGasCb7J7EikdPOfjBXZlMfMfh3gnOP4mK1ITzqmfaevpbrZDkJpspdzZFtYJT2eax';
  }
}