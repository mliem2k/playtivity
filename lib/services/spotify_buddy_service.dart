import 'dart:convert';
import 'package:flutter/foundation.dart';
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
import 'lru_cache_service.dart';
import 'spotify_token_service.dart';

class SpotifyBuddyService {
  static const String _baseUrl = 'https://guc-spclient.spotify.com';
  static const String _artistDetailsCacheKey = 'artist_details_cache';
  // Timestamp threshold for "currently playing": if elapsed < 5 min since the
  // friend started this track, show as now-playing. No duration API call needed.
  static const int _currentlyPlayingThresholdMs = 5 * 60 * 1000;

  // Singleton pattern
  static SpotifyBuddyService? _instance;
  static SpotifyBuddyService get instance {
    _instance ??= SpotifyBuddyService._internal();
    return _instance!;
  }

  // Private constructor for singleton
  SpotifyBuddyService._internal() {
    _artistDetailsCache = LRUCache<String, Map<String, dynamic>>(200);
    _loadArtistDetailsCache();
  }

  // Public factory constructor that returns the singleton
  factory SpotifyBuddyService() => instance;

  late final LRUCache<String, Map<String, dynamic>> _artistDetailsCache;

  bool _artistCacheModified = false;

  // Cache for buddy list activities to reduce API hits
  List<Activity>? _cachedBuddyActivities;
  DateTime? _lastBuddyListFetch;

  // Adaptive cache duration:
  //   • ≥1 friend currently playing → 30s (tracks change often, stay responsive)
  //   • nobody playing             → 5min (save battery/data when feed is quiet)
  static const Duration _activeCacheDuration = Duration(seconds: 30);
  static const Duration _quietCacheDuration = Duration(minutes: 5);

  Duration get _buddyListCacheDuration {
    if (_cachedBuddyActivities == null || _cachedBuddyActivities!.isEmpty) {
      return _activeCacheDuration; // no data yet — poll soon
    }
    final hasActive = _cachedBuddyActivities!.any(
      (a) => a.type == ActivityType.track && a.isCurrentlyPlaying,
    );
    return hasActive ? _activeCacheDuration : _quietCacheDuration;
  }


  /// Clears the buddy list cache to force a fresh fetch on next request
  void clearBuddyListCache() {
    _cachedBuddyActivities = null;
    _lastBuddyListFetch = null;
    AppLogger.spotify('🗑️ Cleared buddy list cache - next request will fetch fresh data');
  }

  void clearActivityCache() {
    clearBuddyListCache();
  }

  @visibleForTesting
  void clearArtistDetailsCache() {
    _artistDetailsCache.clear();
    _artistCacheModified = false;
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

  /// Checks if we should refresh the buddy list cache based on cache expiration or track completion
  bool _shouldRefreshBuddyList() {
    final now = DateTime.now();

    if (_cachedBuddyActivities == null || _lastBuddyListFetch == null) {
      AppLogger.spotify('📊 Cache refresh needed: No cached data');
      return true;
    }

    final cacheDuration = _buddyListCacheDuration;
    final cacheAge = now.difference(_lastBuddyListFetch!);
    if (cacheAge >= cacheDuration) {
      AppLogger.spotify('📊 Cache refresh needed: ${cacheAge.inSeconds}s > ${cacheDuration.inSeconds}s');
      return true;
    }

    // Check if any currently playing track has exceeded the threshold
    for (final activity in _cachedBuddyActivities!) {
      if (activity.type == ActivityType.track && activity.isCurrentlyPlaying) {
        final elapsedMs = now.difference(activity.timestamp).inMilliseconds;
        if (elapsedMs >= _currentlyPlayingThresholdMs) {
          AppLogger.spotify('📊 Cache refresh needed: Track "${activity.track?.name}" by ${activity.user.displayName} exceeded threshold');
          return true;
        }
      }
    }

    AppLogger.spotify('📊 Cache still valid: Age=${cacheAge.inSeconds}s, no tracks finished');
    return false;
  }


  Future<List<Activity>> getFriendActivity(String bearerToken) async {
    AppLogger.spotify('🔍 getFriendActivity called');

    if (!_shouldRefreshBuddyList()) {
      AppLogger.spotify('✅ Using cached buddy list data');
      return _cachedBuddyActivities!;
    }

    return ApiRetryService.retryApiCall(
      () async {
        AppLogger.spotify('✅ Got access token, fetching friend activity...');

        final url = '$_baseUrl/presence-view/v1/buddylist';
        final response = await HttpInterceptor.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $bearerToken'},
        );

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Authentication error: ${response.statusCode}');
        }
        if (response.statusCode != 200) {
          throw Exception('Failed to fetch friend activity: ${response.statusCode}');
        }

        AppLogger.warning('Buddylist raw (${response.body.length}b): '
            '${response.body.substring(0, response.body.length.clamp(0, 1200))}');
        final activities = parseFriendsJson(response.body);
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
  /// Safely extracts a String from a dynamic value; returns null for any
  /// non-String type rather than throwing a TypeError.
  static String? _str(dynamic v) => v is String ? v : null;

  static List<Activity> parseFriendsJson(String responseBody, {int? nowMs}) {
    try {
      final data = json.decode(responseBody);
      final friends = data['friends'] as List?;
      if (friends == null) return [];

      AppLogger.spotify('Buddylist: ${friends.length} friends from API');
      final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final activities = <Activity>[];

      for (final friend in friends) {
        if (friend == null) continue;
        try {
          final userInfo = friend['user'];
          if (userInfo == null) continue;
          final rawTimestamp = friend['timestamp'];
          final ts = rawTimestamp is int ? rawTimestamp : now;

          final userUri = _str(userInfo['uri']) ?? '';
          final userId = userUri.startsWith('spotify:user:')
              ? userUri.substring('spotify:user:'.length)
              : userUri;

          final user = User(
            id: userId,
            displayName: _str(userInfo['name']) ?? 'Unknown User',
            email: '',
            imageUrl: _str(userInfo['imageUrl']),
            followers: 0,
            country: '',
          );

          final trackInfo = friend['track'] is Map ? friend['track'] as Map : null;
          final playlistInfo = friend['playlist'] is Map ? friend['playlist'] as Map : null;
          final episodeInfo = friend['episode'] is Map ? friend['episode'] as Map : null;

          AppLogger.warning(
            'Friend "${user.displayName}": keys=${friend is Map ? friend.keys.toList() : "?"}',
          );

          if (playlistInfo != null) {
            final playlistUri = _str(playlistInfo['uri']) ?? '';
            final playlist = Playlist(
              id: playlistUri.split(':').last,
              name: _str(playlistInfo['name']) ?? 'Unknown Playlist',
              description: _str(playlistInfo['description']),
              imageUrl: _str(playlistInfo['imageUrl']),
              trackCount: playlistInfo['trackCount'] is int ? playlistInfo['trackCount'] as int : 0,
              uri: playlistUri,
              ownerId: _str(playlistInfo['owner']?['id']) ?? '',
              ownerName: _str(playlistInfo['owner']?['name']) ?? 'Unknown',
              isPublic: playlistInfo['public'] == true,
            );
            activities.add(Activity(
              user: user,
              playlist: playlist,
              timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
              isCurrentlyPlaying: false,
              type: ActivityType.playlist,
            ));
          } else if (trackInfo != null) {
            final albumInfo = trackInfo['album'] is Map ? trackInfo['album'] as Map : <String, dynamic>{};
            final artistInfo = trackInfo['artist'] is Map ? trackInfo['artist'] as Map : <String, dynamic>{};

            final elapsedMs = now - ts;
            final isCurrentlyPlaying = elapsedMs >= 0 && elapsedMs < _currentlyPlayingThresholdMs;

            final track = Track(
              id: _str(trackInfo['uri']) ?? '',
              name: _str(trackInfo['name']) ?? 'Unknown Track',
              artists: [_str(artistInfo['name']) ?? 'Unknown Artist'],
              album: _str(albumInfo['name']) ?? 'Unknown Album',
              albumUri: _str(albumInfo['uri']),
              imageUrl: _str(trackInfo['imageUrl']) ?? _str(albumInfo['imageUrl']),
              durationMs: 0,
              uri: _str(trackInfo['uri']) ?? '',
            );
            activities.add(Activity(
              user: user,
              track: track,
              timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
              isCurrentlyPlaying: isCurrentlyPlaying,
              type: ActivityType.track,
            ));
          } else if (episodeInfo != null) {
            final showInfo = episodeInfo['show'] is Map ? episodeInfo['show'] as Map : <String, dynamic>{};

            final elapsedMs = now - ts;
            final isCurrentlyPlaying = elapsedMs >= 0 && elapsedMs < _currentlyPlayingThresholdMs;

            final showName = _str(showInfo['name']) ?? 'Unknown Podcast';
            final track = Track(
              id: _str(episodeInfo['uri']) ?? '',
              name: _str(episodeInfo['name']) ?? 'Unknown Episode',
              artists: [showName],
              album: showName,
              albumUri: _str(showInfo['uri']),
              imageUrl: _str(episodeInfo['imageUrl']) ?? _str(showInfo['imageUrl']),
              durationMs: 0,
              uri: _str(episodeInfo['uri']) ?? '',
            );
            activities.add(Activity(
              user: user,
              track: track,
              timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
              isCurrentlyPlaying: isCurrentlyPlaying,
              type: ActivityType.track,
            ));
          } else {
            // Friends browsing without actively playing have only a context
            // key (playlist/album/show URI). Treat as a playlist activity so
            // they appear in the feed rather than being silently dropped.
            final rawContext = friend['context'];
            final contextInfo = rawContext is Map ? rawContext : null;
            final contextUri = _str(contextInfo?['uri']) ?? '';
            if (contextUri.isNotEmpty) {
              final playlist = Playlist(
                id: contextUri.split(':').last,
                name: _str(contextInfo?['name']) ?? 'Spotify',
                description: null,
                imageUrl: _str(contextInfo?['imageUrl']),
                trackCount: 0,
                uri: contextUri,
                ownerId: '',
                ownerName: '',
                isPublic: true,
              );
              activities.add(Activity(
                user: user,
                playlist: playlist,
                timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
                isCurrentlyPlaying: false,
                type: ActivityType.playlist,
              ));
            } else {
              AppLogger.warning(
                'Skipped "${user.displayName}" — no track/episode/playlist/context'
                ' (friend keys: ${friend is Map ? friend.keys.toList() : "not a map"})',
              );
            }
          }
        } catch (e, st) {
          AppLogger.error('Failed to parse friend entry: $e\n$st', e);
        }
      }

      AppLogger.spotify('Parsed ${activities.length}/${friends.length} activities');
      activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return activities;
    } catch (e) {
      AppLogger.error('parseFriendsJson: failed to decode response', e);
      return [];
    }
  }


  /// Gets the authenticated user's profile via api.spotify.com/v1/me.
  /// NOTE: spclient/profile/me is NOT equivalent — "me" is a literal Spotify
  /// username (belongs to a different account) and returns the wrong profile.
  Future<User?> getCurrentUserProfileWithToken(String bearerToken) async {
    final response = await HttpInterceptor.get(
      Uri.parse('https://api.spotify.com/v1/me'),
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Accept': 'application/json',
        'App-Platform': 'WebPlayer',
        'User-Agent': SpotifyTokenService.userAgent,
      },
    );
    AppLogger.spotify('📡 /v1/me response: ${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('/v1/me: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final user = _parseUserFrom2026Api(data);
    AppLogger.spotify('✅ /v1/me OK: ${user.displayName}');
    return user;
  }

  User _parseUserFrom2026Api(Map<String, dynamic> data) {
    return User(
      id: JsonHelpers.getString(data, 'id'),
      displayName: JsonHelpers.getString(data, 'display_name'),
      email: data['email'] as String? ?? '',
      imageUrl: JsonHelpers.getSpotifyImageUrl(data),
      followers: data['followers'] is Map
          ? JsonHelpers.getNestedInt(data, ['followers', 'total'])
          : 0,
      country: data['country'] as String? ?? '',
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
            'content-type': 'application/json;charset=UTF-8',
            'origin': 'https://open.spotify.com',
            'referer': 'https://open.spotify.com/',
            'user-agent': SpotifyTokenService.userAgent,
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

          int followers = -1;
          int monthlyListeners = -1;

          if (_artistDetailsCache.containsKey(artistId)) {
            final cachedDetails = _artistDetailsCache.get(artistId)!;
            followers = cachedDetails['followers'] as int? ?? -1;
            monthlyListeners = cachedDetails['monthly_listeners'] as int? ?? -1;
          }

          artists.add(Artist(
            id: artistId,
            name: artistData['profile']?['name'] ?? 'Unknown Artist',
            imageUrl: imageUrl,
            followers: followers,
            monthlyListeners: monthlyListeners,
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
      if (artist.monthlyListeners == -1) {
        missingIds.add(artist.id);
      }
    }

    if (missingIds.isEmpty) {
      return artists;
    }

    var updatedArtists = List<Artist>.from(artists);

    for (final artistId in missingIds) {
      try {
        final details = await _getArtistDetails(bearerToken, artistId);
        if (details != null) {
          final followers = details['followers'] as int? ?? 0;
          final monthlyListeners = details['monthly_listeners'] as int? ?? 0;

          _artistDetailsCache.put(artistId, {
            'followers': followers,
            'monthly_listeners': monthlyListeners,
            'cached_at': DateTime.now().millisecondsSinceEpoch,
          });
          _artistCacheModified = true;

          final idx = updatedArtists.indexWhere((a) => a.id == artistId);
          if (idx != -1) {
            final old = updatedArtists[idx];
            updatedArtists[idx] = Artist(
              id: old.id,
              name: old.name,
              imageUrl: old.imageUrl,
              followers: followers,
              monthlyListeners: monthlyListeners,
              uri: old.uri,
            );
            if (onUpdate != null) onUpdate(List<Artist>.from(updatedArtists));
          }
        }
      } catch (e) {
        AppLogger.spotify('⚠️ Failed to fetch details for artist $artistId: $e');
        _artistDetailsCache.put(artistId, {
          'followers': 0,
          'monthly_listeners': 0,
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

  /// Fetches artist stats via api-partner pathfinder (not rate-limited for web-player tokens).
  /// Returns a map with keys: followers (int), monthly_listeners (int).
  Future<Map<String, dynamic>?> _getArtistDetails(String bearerToken, String artistId) async {
    return ApiRetryService.retryApiCall(
      () async {
        final variables = json.encode({
          'uri': 'spotify:artist:$artistId',
          'locale': '',
          'includePrerelease': true,
        });
        final extensions = json.encode({
          'persistedQuery': {
            'version': 1,
            'sha256Hash': 'd66221ea13998b2f81883c5187d174c8646e4041d67f5b1e103bc262d447e3a0',
          }
        });
        final uri = Uri.parse('https://api-partner.spotify.com/pathfinder/v1/query')
            .replace(queryParameters: {
          'operationName': 'queryArtistOverview',
          'variables': variables,
          'extensions': extensions,
        });

        final response = await HttpInterceptor.get(uri, headers: {
          'accept': 'application/json',
          'app-platform': 'WebPlayer',
          'authorization': 'Bearer $bearerToken',
          'origin': 'https://open.spotify.com',
          'referer': 'https://open.spotify.com/',
          'user-agent': SpotifyTokenService.userAgent,
        });

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final stats = data['data']?['artist']?['stats'] as Map<String, dynamic>?;
          return {
            'followers': stats?['followers'] as int? ?? 0,
            'monthly_listeners': stats?['monthlyListeners'] as int? ?? 0,
          };
        }
        throw Exception('queryArtistOverview ${response.statusCode}');
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

}
