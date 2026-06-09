import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/models/activity.dart';
import 'package:playtivity/models/user.dart';
import 'package:playtivity/models/track.dart';
import 'package:playtivity/models/playlist.dart';
import 'package:playtivity/models/artist.dart';
import 'package:playtivity/utils/json_helpers.dart';
import 'http_interceptor.dart';
import 'app_logger.dart';
import 'api_retry_service.dart';
import 'cache_service.dart';
import 'lru_cache_service.dart';
import 'spotify_token_service.dart';

class SpotifyBuddyService {
  static const String _baseUrl = 'https://guc-spclient.spotify.com';
  static const String _trackDurationCacheKey = 'track_duration_cache';
  static const String _artistDetailsCacheKey = 'artist_details_cache';

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
      final cacheData = await CacheService.loadJson(_trackDurationCacheKey);

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

      await CacheService.saveJson(_trackDurationCacheKey, cacheData);
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

  /// Clears activity cache (buddy list cache). Call on logout.
  void clearActivityCache() {
    clearBuddyListCache();
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

  /// Fetches track duration from Spotify API using provided bearer token
  Future<int?> _getTrackDuration(String bearerToken, String trackUri) async {
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


  Future<List<Activity>> getFriendActivity(
    String bearerToken, {
    bool fastLoad = false,
    Function(List<Activity>)? onActivitiesUpdate,
  }) async {
    AppLogger.spotify('🔍 getFriendActivity called');

    // Check if we can use cached data
    if (!_shouldRefreshBuddyList()) {
      AppLogger.spotify('✅ Using cached buddy list data');
      return _cachedBuddyActivities!;
    }

    return ApiRetryService.retryApiCall(
      () async {
        AppLogger.spotify('✅ Got access token, fetching friend activity...');

        // Use the new buddylist endpoint - no hash parameter needed
        final url = '$_baseUrl/presence-view/v1/buddylist';
        final headers = {
          'Authorization': 'Bearer $bearerToken',
        };

        final response = await HttpInterceptor.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Authentication error: ${response.statusCode}');
        }
        if (response.statusCode != 200) {
          throw Exception('Failed to fetch friend activity: ${response.statusCode}');
        }

        final activities = parseFriendsJson(response.body);
        if (!fastLoad) {
          final needsDuration = activities
              .where((a) =>
                  a.type == ActivityType.track &&
                  (a.track?.durationMs ?? 0) == 0 &&
                  (a.track?.uri.isNotEmpty ?? false))
              .toList();
          if (needsDuration.isNotEmpty) {
            _fetchTrackDurationsProgressively(bearerToken, activities, needsDuration, onActivitiesUpdate);
          }
        }
        _cachedBuddyActivities = activities;
        _lastBuddyListFetch = DateTime.now();
        return activities;
      },
      operation: 'Get Friend Activity',
    );
  }

  /// Pure JSON parser for the Spotify buddylist API response.
  /// Converts the raw `responseBody` into a sorted list of [Activity] objects
  /// without any network calls or caching side effects.
  ///
  /// [nowMs] overrides the current timestamp for [isCurrentlyPlaying] calculations.
  /// Defaults to [DateTime.now] when omitted. Exposed as a static method so
  /// tests can call it directly with a fixed clock.
  static List<Activity> parseFriendsJson(String responseBody, {int? nowMs}) {
    try {
      final data = json.decode(responseBody);
      final friends = data['friends'] as List?;
      if (friends == null) return [];

      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final activities = <Activity>[];

      for (final friend in friends) {
        final userInfo = friend['user'];
        final rawTimestamp = friend['timestamp'];
        final ts = rawTimestamp is int ? rawTimestamp : now;

        final userUri = userInfo['uri'] ?? '';
        final userId = userUri.startsWith('spotify:user:')
            ? userUri.substring('spotify:user:'.length)
            : userUri;

        final user = User(
          id: userId,
          displayName: userInfo['name'] ?? 'Unknown User',
          email: '',
          imageUrl: userInfo['imageUrl'] as String?,
          followers: 0,
          country: '',
        );

        final trackInfo = friend['track'];
        final playlistInfo = friend['playlist'];

        if (playlistInfo != null) {
          final playlist = Playlist(
            id: (playlistInfo['uri'] as String?)?.split(':').last ?? '',
            name: playlistInfo['name'] ?? 'Unknown Playlist',
            description: playlistInfo['description'] as String?,
            imageUrl: playlistInfo['imageUrl'] as String?,
            trackCount: playlistInfo['trackCount'] ?? 0,
            uri: playlistInfo['uri'] ?? '',
            ownerId: playlistInfo['owner']?['id'] ?? '',
            ownerName: playlistInfo['owner']?['name'] ?? 'Unknown',
            isPublic: playlistInfo['public'] ?? false,
          );
          activities.add(Activity(
            user: user,
            playlist: playlist,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
            isCurrentlyPlaying: false,
            type: ActivityType.playlist,
          ));
        } else if (trackInfo != null) {
          final albumInfo = trackInfo['album'] ?? <String, dynamic>{};
          final artistInfo = trackInfo['artist'] ?? <String, dynamic>{};
          final durationMs = trackInfo['duration_ms'] as int? ?? 0;

          final elapsedMs = now - ts;
          final isCurrentlyPlaying =
              durationMs > 0 && elapsedMs >= 0 && elapsedMs < (durationMs + 5000);

          final track = Track(
            id: trackInfo['uri'] ?? '',
            name: trackInfo['name'] ?? 'Unknown Track',
            artists: [artistInfo['name'] as String? ?? 'Unknown Artist'],
            album: albumInfo['name'] ?? 'Unknown Album',
            albumUri: albumInfo['uri'] as String?,
            imageUrl: (trackInfo['imageUrl'] ?? albumInfo['imageUrl']) as String?,
            durationMs: durationMs,
            uri: trackInfo['uri'] ?? '',
          );
          activities.add(Activity(
            user: user,
            track: track,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
            isCurrentlyPlaying: isCurrentlyPlaying,
            type: ActivityType.track,
          ));
        }
      }

      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return activities;
    } catch (_) {
      return [];
    }
  }

  /// Fetches track durations progressively and updates activities as they become available
  void _fetchTrackDurationsProgressively(
    String bearerToken,
    List<Activity> activities,
    List<Activity> needingDuration,
    Function(List<Activity>)? onActivitiesUpdate,
  ) {
    Future.microtask(() async {
      var updated = List<Activity>.from(activities);

      for (final activity in needingDuration) {
        try {
          final trackUri = activity.track!.uri;
          final durationMs = await _getTrackDuration(bearerToken, trackUri);
          if (durationMs == null) continue;

          final idx = updated.indexWhere((a) =>
              a.track?.uri == trackUri &&
              a.user.displayName == activity.user.displayName);
          if (idx == -1) continue;

          final old = updated[idx];
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsed = now - old.timestamp.millisecondsSinceEpoch;
          final isPlaying = elapsed >= 0 && elapsed < (durationMs + 5000);

          updated[idx] = Activity(
            user: old.user,
            track: Track(
              id: old.track!.id,
              name: old.track!.name,
              artists: old.track!.artists,
              album: old.track!.album,
              albumUri: old.track!.albumUri,
              imageUrl: old.track!.imageUrl,
              durationMs: durationMs,
              uri: old.track!.uri,
            ),
            timestamp: old.timestamp,
            isCurrentlyPlaying: isPlaying,
            type: old.type,
          );

          _cachedBuddyActivities = List<Activity>.from(updated);
          onActivitiesUpdate?.call(List<Activity>.from(updated));
        } catch (e) {
          AppLogger.spotify('Failed to fetch duration for ${activity.track?.uri}: $e');
        }
      }

      if (_cacheModified) {
        await _saveTrackDurationCache();
        _cacheModified = false;
      }
    });
  }




  /// Gets current user profile using web access token.
  /// Uses the spclient /me endpoint — same token type and domain as the buddy list.
  /// The official api.spotify.com/v1/me is rate-limited (429) for web-player tokens.
  Future<User?> getCurrentUserProfileWithToken(String bearerToken) async {
    try {
      final profile = await _getUserProfileFromSpclient(bearerToken, 'me');
      if (profile != null) {
        AppLogger.spotify('✅ Spclient /me OK: ${profile.displayName}');
        return profile;
      }
      throw Exception('spclient /me returned null');
    } catch (e) {
      AppLogger.spotify('❌ Spclient /me failed: $e');
      throw Exception('Profile failed: $e');
    }
  }

  /// Fetches user profile from the spclient endpoint.
  /// Pass userId = "me" to get the authenticated user's own profile.
  Future<User?> _getUserProfileFromSpclient(String bearerToken, String userId) async {
    final url = '$_baseUrl/user-profile-view/v3/profile/$userId';
    final response = await HttpInterceptor.get(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Accept': 'application/json',
        'App-Platform': 'WebPlayer',
        'User-Agent': SpotifyTokenService.userAgent,
      },
    );
    AppLogger.spotify('📡 Spclient profile/$userId response: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('spclient:${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    // uri is "spotify:user:me" for the /me path — strip prefix to get the ID token.
    final rawUri = data['uri'] as String? ?? '';
    final id = rawUri.startsWith('spotify:user:')
        ? rawUri.substring('spotify:user:'.length)
        : (rawUri.isNotEmpty ? rawUri : userId);
    return User(
      id: id,
      displayName: data['name'] as String? ?? id,
      email: 'user@spotify.com',
      imageUrl: data['image_url'] as String?,
      followers: data['followers_count'] as int? ?? 0,
      country: 'US',
    );
  }

  // ignore: unused_element — kept as fallback reference for the official /v1/me schema
  User _parseUserFrom2026Api(Map<String, dynamic> data) {
    return User(
      id: JsonHelpers.getString(data, 'id'),
      displayName: JsonHelpers.getString(data, 'display_name'),
      email: data['email'] as String? ?? 'user@spotify.com',
      imageUrl: JsonHelpers.getSpotifyImageUrl(data),
      followers: data['followers'] is Map
          ? JsonHelpers.getNestedInt(data, ['followers', 'total'])
          : 0,
      country: data['country'] as String? ?? 'US',
    );
  }

  /// Gets user's top content (tracks and artists) using GraphQL API
  Future<Map<String, dynamic>?> getTopContent(
    String bearerToken, {
    String timeRange = 'SHORT_TERM',
    int tracksLimit = 4,
    int artistsLimit = 10,
    bool includeTopTracks = true,
    bool includeTopArtists = true,
  }) async {
    try {
      return await ApiRetryService.retryApiCall(
        () async {
          AppLogger.spotify('🔄 Getting top content with GraphQL API...');
          AppLogger.spotify('   - Time range: $timeRange');
          AppLogger.spotify('   - Tracks limit: $tracksLimit (enabled: $includeTopTracks)');
          AppLogger.spotify('   - Artists limit: $artistsLimit (enabled: $includeTopArtists)');

          AppLogger.spotify('✅ Got access token, fetching top content...');

          final url = 'https://api-partner.spotify.com/pathfinder/v2/query';
          final headers = {
            'accept': 'application/json',
            'accept-language': 'en',
            'app-platform': 'WebPlayer',
            'authorization': 'Bearer $bearerToken',
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

          if (response.statusCode == 401 || response.statusCode == 403) {
            throw Exception('Authentication error: ${response.statusCode}');
          }
          if (response.statusCode != 200) {
            throw Exception('Failed to fetch top content: ${response.statusCode} - ${response.body}');
          }
          return json.decode(response.body) as Map<String, dynamic>;
        },
        operation: 'Get Top Content',
      );
    } catch (e) {
      AppLogger.spotify('❌ Error in getTopContent: $e');
      return null;
    }
  }

  /// Gets user's top tracks using the new GraphQL API
  Future<List<Track>> getTopTracks(
    String bearerToken, {
    String timeRange = 'medium_term',
    int limit = 20,
  }) async {
    try {
      final data = await getTopContent(
        bearerToken,
        timeRange: 'SHORT_TERM', // GraphQL schema only supports SHORT_TERM currently
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
  Future<List<Artist>> getTopArtists(
    String bearerToken, {
    String timeRange = 'medium_term',
    int limit = 20,
  }) async {
    try {
      final data = await getTopContent(
        bearerToken,
        timeRange: 'SHORT_TERM',
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
            final cachedDetails = _artistDetailsCache.get(artistId)!;
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
  Future<List<Artist>> getTopArtistsWithDetails(
    String bearerToken, {
    String timeRange = 'medium_term',
    int limit = 20,
    Function(List<Artist>)? onArtistDetailsUpdate,
  }) async {
    // First get the basic artist list
    final artists = await getTopArtists(bearerToken, timeRange: timeRange, limit: limit);

    // Fetch missing details in background with callback
    _fetchMissingArtistDetails(bearerToken, artists, onUpdate: onArtistDetailsUpdate);

    return artists;
  }

  /// Fetches missing artist details in background and updates cache
  Future<List<Artist>> _fetchMissingArtistDetails(
    String bearerToken,
    List<Artist> artists, {
    Function(List<Artist>)? onUpdate,
  }) async {
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
        final artistDetails = await _getArtistDetails(bearerToken, artistId);
        if (artistDetails != null) {
          _artistDetailsCache.put(artistId, {
            'followers': artistDetails['followers']?['total'] ?? 0,
            'genres': artistDetails['genres'] ?? [],
            'popularity': artistDetails['popularity'] ?? 0,
            'cached_at': DateTime.now().millisecondsSinceEpoch,
          });
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
        _artistDetailsCache.put(artistId, {
          'followers': 0,
          'genres': [],
          'popularity': 0,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'failed': true,
        });
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
  Future<Map<String, dynamic>?> _getArtistDetails(String bearerToken, String artistId) async {
    return ApiRetryService.retryApiCall(
      () async {
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
              _artistDetailsCache.put(artistId, Map<String, dynamic>.from(details));
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

  /// Generates a client token for the GraphQL API
  /// This is a fallback in case we don't have an intercepted token
  String _generateClientToken() {
    AppLogger.spotify('⚠️ Using fallback client token - this should be replaced with an intercepted token');
    // This is a placeholder - the actual client token generation is complex
    // For now, we'll use a static token from the example
    return 'AAAyrFCYuQiGGFsq0OYbkiotiZ9YtDPzdjemsDOtMJ6msHslHFxskOjd1h1q28igZTPhiB+n++o4n7/QkdHbIuzznY/QOKMesZKLlV83stuo8yn7hiiDN1R7b0HyInceiDZUgEPotzcBSM7v9ff76LEOJ53Hxl4W8qp+bwi+WAMlKSG6LSKb4905Tyqj0p2nsnWblSZVUw+Lj7huYgvu2y4istr4/zCyTIed9nI6ys3M2C8yhYfF1+5PC58l5gwGasCb7J7EikdPOfjBXZlMfMfh3gnOP4mK1ITzqmfaevpbrZDkJpspdzZFtYJT2eax';
  }

}
