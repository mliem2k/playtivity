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
// import 'package:playtivity/services/spotify_service.dart';

class SpotifyBuddyService {
  static const String _baseUrl = 'https://guc-spclient.spotify.com';
  
  // Cache for access token and sp_dc cookie to avoid repeated requests
  String? _cachedAccessToken;
  String? _lastValidSpDcCookie;
  DateTime? _tokenExpiry;
    // Spotify service for fetching track details
  // final SpotifyService _spotifyService = SpotifyService();
  
  // In-memory cache for track durations
  final Map<String, int> _trackDurationCache = {};
  
  // Track if cache has been modified since last save
  bool _cacheModified = false;
  
  // SharedPreferences key for persistent track duration cache
  static const String _trackDurationCacheKey = 'track_duration_cache';
  
  // Cache for buddy list activities to reduce API hits
  List<Activity>? _cachedBuddyActivities;
  DateTime? _lastBuddyListFetch;
  
  // Cache duration - refresh every 1.5 minutes
  static const Duration _buddyListCacheDuration = Duration(minutes: 1, seconds: 30);

  String base32FromBytes(Uint8List e, String secretSauce) {
    var t = 0;
    var n = 0;
    var r = "";
    for (int i = 0; i < e.length; i++) {
      n = n << 8 | e[i];
      t += 8;
      while (t >= 5) {
        r += secretSauce[n >>> t - 5 & 31];
        t -= 5;
      }
    }
    if (t > 0) {
      r += secretSauce[n << 5 - t & 31];
    }
    return r;
  }

  Uint8List cleanBuffer(String e) {
    e = e.replaceAll(" ", "");
    final t = List.filled(e.length ~/ 2, 0);
    final n = Uint8List.fromList(t);
    for (int r = 0; r < e.length; r += 2) {
      n[r ~/ 2] = int.parse(e.substring(r, r + 2), radix: 16);
    }
    return n;
  }

  Future<String> generateTotp() async {
    const secretSauce = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    final secretCipherBytes = [
      12, 56, 76, 33, 88, 44, 88, 33, 78, 78, 11, 66, 22, 22, 55, 69, 54
    ];
    
    final secretBytes = secretCipherBytes.asMap().entries.map((entry) {
      return entry.value ^ (entry.key % 33 + 9);
    }).toList();

    final secretBytesHex = cleanBuffer(
      utf8.encode(secretBytes.join("")).map((e) => e.toRadixString(16)).join(),
    );

    final secret = base32FromBytes(secretBytesHex, secretSauce);

    // Get server time
    final serverTimeResponse = await http.get(
      Uri.parse('https://open.spotify.com/server-time'),
      headers: {
        'Host': 'open.spotify.com',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'accept': '*/*',
      },
    );

    final serverTimeData = json.decode(serverTimeResponse.body);
    final serverTimeSeconds = serverTimeData['serverTime'] as int;

    // Generate TOTP
    final time = DateTime.fromMillisecondsSinceEpoch(serverTimeSeconds * 1000);
    final timeStep = (time.millisecondsSinceEpoch ~/ 1000) ~/ 30;
    
    return _generateTOTP(secret, timeStep);
  }

  String _generateTOTP(String secret, int timeStep) {
    final key = _base32Decode(secret);
    final timeBytes = _intToBytes(timeStep);
    
    // Use proper HMAC-SHA1 from crypto package
    final hmacSha1 = Hmac(sha1, key);
    final digest = hmacSha1.convert(timeBytes);
    final hmac = digest.bytes;
    
    final offset = hmac[hmac.length - 1] & 0xf;
    final code = ((hmac[offset] & 0x7f) << 24) |
        ((hmac[offset + 1] & 0xff) << 16) |
        ((hmac[offset + 2] & 0xff) << 8) |
        (hmac[offset + 3] & 0xff);
    return (code % 1000000).toString().padLeft(6, '0');
  }

  Uint8List _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final output = <int>[];
    var bits = 0;
    var value = 0;

    for (int i = 0; i < input.length; i++) {
      value = (value << 5) | alphabet.indexOf(input[i].toUpperCase());
      bits += 5;

      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 255);
        bits -= 8;
      }
    }

    return Uint8List.fromList(output);
  }

  Uint8List _intToBytes(int value) {
    final bytes = Uint8List(8);
    for (int i = 7; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    return bytes;
  }

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

  /// Fetches track duration from Spotify API using OAuth token
  Future<int?> _getTrackDuration(String trackUri, String oauthAccessToken) async {
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
        
        final url = 'https://api.spotify.com/v1/tracks/$trackId';
        final headers = {
          'Authorization': 'Bearer $oauthAccessToken',
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
        } else {
          throw Exception('Failed to fetch track duration: ${response.statusCode} - ${response.body}');
        }
        
        throw Exception('Track duration not found in response');
      },
      operation: 'Get Track Duration',
    );
  }

  /// Gets a cached access token or fetches a new one if needed
  Future<String?> getCachedOrFreshAccessToken(String spDcCookie) async {
    // Check if we have a valid cached token for the same sp_dc cookie
    if (_cachedAccessToken != null && 
        _lastValidSpDcCookie == spDcCookie && 
        _tokenExpiry != null && 
        DateTime.now().isBefore(_tokenExpiry!)) {
      print('✅ Using cached access token');
      return _cachedAccessToken;
    }
    
    print('🔄 Fetching new access token (cache expired or cookie changed)');
    final accessToken = await getWebAccessToken(spDcCookie);
    
    if (accessToken != null) {
      _cachedAccessToken = accessToken;
      _lastValidSpDcCookie = spDcCookie;
      // Spotify web access tokens typically expire after 1 hour
      _tokenExpiry = DateTime.now().add(const Duration(minutes: 55));
      print('✅ Cached new access token (expires at ${_tokenExpiry})');
    }
    
    return accessToken;
  }

  Future<String?> getWebAccessToken(String spDcCookie) async {
    return _retryApiCall(
      () async {
        final totp = await generateTotp();
        final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor();

        var accessTokenUrl = Uri.parse(
          'https://open.spotify.com/get_access_token?reason=transport&productType=web-player'
          '&totp=$totp&totpVer=5&ts=$timestamp',
        );

        final headers = {
          'Cookie': 'sp_dc=$spDcCookie',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        };

        var response = await http.get(
          accessTokenUrl,
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final accessToken = data['accessToken'];
          
          if (accessToken != null && (accessToken as String).length == 374) {
            return accessToken;
          } else {
            // Try with mode=init if transport didn't work or token is wrong length
            accessTokenUrl = Uri.parse(
              'https://open.spotify.com/get_access_token?reason=init&productType=web-player'
              '&totp=$totp&totpVer=5&ts=$timestamp',
            );

            final initHeaders = {
              'Cookie': 'sp_dc=$spDcCookie',
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            };

            response = await http.get(
              accessTokenUrl,
              headers: initHeaders,
            );

            if (response.statusCode == 200) {
              final initData = json.decode(response.body);
              final accessToken = initData['accessToken'];
              if (accessToken != null) {
                return accessToken;
              }
            }
          }
        }
        
        throw Exception('Failed to get web access token: ${response.statusCode} - ${response.body}');
      },
      operation: 'Get Web Access Token',
    );
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
  //   }
  //   
  //   // Add URL
  //   buffer.write(' "$url"');
  //   
  //   return buffer.toString();
  // }

  Future<List<Activity>> getFriendActivity(String spDcCookie, {String? oauthAccessToken, bool fastLoad = false}) async {
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
        
        print('🔄 Getting access token with sp_dc cookie...');
        String? accessToken = await getCachedOrFreshAccessToken(spDcCookie);
        
        if (accessToken == null) {
          throw Exception('Failed to get access token');
        }

        print('✅ Got access token, fetching friend activity...');
        
        final url = '$_baseUrl/presence-view/v1/buddylist';
        final headers = {
          'Authorization': 'Bearer $accessToken',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        };

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
          _lastValidSpDcCookie = null;
          _tokenExpiry = null;
          
          // Retry with fresh token
          accessToken = await getCachedOrFreshAccessToken(spDcCookie);
          if (accessToken == null) {
            throw Exception('Failed to get fresh access token after unauthorized response');
          }
          
          final retryHeaders = {
            'Authorization': 'Bearer $accessToken',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          };
          
          final retryResponse = await http.get(
            Uri.parse(url),
            headers: retryHeaders,
          );
          
          print('📡 Retry response: ${retryResponse.statusCode}');
          
          if (retryResponse.statusCode == 200) {
            final activities = await _parseActivityResponse(retryResponse.body, oauthAccessToken, fastLoad: fastLoad);
            // Cache the successful response
            _cachedBuddyActivities = activities;
            _lastBuddyListFetch = DateTime.now();
            return activities;
          } else {
            throw Exception('Retry also failed with status: ${retryResponse.statusCode}');
          }
        }

        if (response.statusCode == 200) {
          final activities = await _parseActivityResponse(response.body, oauthAccessToken, fastLoad: fastLoad);
          // Cache the successful response
          _cachedBuddyActivities = activities;
          _lastBuddyListFetch = DateTime.now();
          print('💾 Cached buddy list data with ${activities.length} activities');
          return activities;
        } else {
          throw Exception('Failed to fetch friend activity: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get Friend Activity',
    );
  }

  Future<List<Activity>> _parseActivityResponse(String responseBody, String? oauthAccessToken, {bool fastLoad = false}) async {
    try {
      final data = json.decode(responseBody);
      final friends = data['friends'] as List?;
      
      if (friends != null) {
        final activities = <Activity>[];
        
        for (final friend in friends) {
          final userInfo = friend['user'];
          final timestamp = friend['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
          
          // Create User object
          final user = User(
            id: userInfo['uri'] ?? '',
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
            // Get track duration from Spotify API if available and not in fast load mode
            int? durationMs = trackInfo['duration_ms'];
            final trackUri = trackInfo['uri'] ?? '';
            bool isCurrentlyPlaying = false;
            
            if (!fastLoad) {
              if (durationMs == null && oauthAccessToken != null && trackUri.isNotEmpty) {
                print('🔍 Fetching duration for track: $trackUri');
                durationMs = await _getTrackDuration(trackUri, oauthAccessToken);
              }
              
              // Check if currently playing based on timestamp and song duration
              isCurrentlyPlaying = _isCurrentlyPlaying(friend, durationMs: durationMs);
              
              print('🎵 Friend activity: ${userInfo['name']} - Currently Playing: $isCurrentlyPlaying');
            } else {
              // In fast load mode, assume not currently playing to avoid API calls
              print('⚡ Fast load: ${userInfo['name']} - Skipping duration check');
            }
            
            // Create Track object
            final albumInfo = trackInfo['album'] ?? {};
            final artistInfo = trackInfo['artist'] ?? {};
            
            final track = Track(
              id: trackInfo['uri'] ?? '',
              name: trackInfo['name'] ?? 'Unknown Track',
              artists: [artistInfo['name'] ?? 'Unknown Artist'],
              album: albumInfo['name'] ?? 'Unknown Album',
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
        
        // Save cache if it was modified
        if (_cacheModified) {
          await _saveTrackDurationCache();
          _cacheModified = false;
        }
        
        return activities;
      }
    } catch (e) {
      print('❌ Error parsing activity response: $e');
    }
    
    return [];
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
}