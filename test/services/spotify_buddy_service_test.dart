import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_buddy_service.dart';
import 'package:playtivity/models/activity.dart';

// The service is a singleton; reset observable state between tests.
void _reset() {
  SpotifyBuddyService.instance.clearActivityCache();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _reset();
  });

  tearDown(_reset);

  // ---------------------------------------------------------------------------
  // Buddy list cache management
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService buddy list cache', () {
    test('getBuddyListCacheStatus reports no cache initially', () {
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status['hasCache'], isFalse);
      expect(status['activityCount'], 0);
      expect(status['shouldRefresh'], isTrue);
      expect(status['cacheAge'], isNull);
    });

    test('clearBuddyListCache resets cache status to no-cache state', () {
      // Nothing to clear initially, but clearBuddyListCache must still work
      SpotifyBuddyService.instance.clearBuddyListCache();
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status['hasCache'], isFalse);
    });

    test('clearActivityCache resets cache status to no-cache state', () {
      SpotifyBuddyService.instance.clearActivityCache();
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status['hasCache'], isFalse);
    });

    test('getBuddyListCacheStatus returns correct structure', () {
      final status = SpotifyBuddyService.instance.getBuddyListCacheStatus();
      expect(status.containsKey('hasCache'), isTrue);
      expect(status.containsKey('cacheAge'), isTrue);
      expect(status.containsKey('activityCount'), isTrue);
      expect(status.containsKey('shouldRefresh'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Singleton identity
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService singleton', () {
    test('factory constructor returns the same instance', () {
      final a = SpotifyBuddyService();
      final b = SpotifyBuddyService();
      expect(identical(a, b), isTrue);
    });

    test('instance getter returns the same object as factory constructor', () {
      expect(identical(SpotifyBuddyService.instance, SpotifyBuddyService()), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // getFriendActivity — requires bearer token as parameter
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.getFriendActivity', () {
    test('throws network error when given a fake bearer token (no cached data)', () async {
      // With no cached data, the service will try to make a real HTTP call and fail
      Object? caught;
      try {
        await SpotifyBuddyService.instance.getFriendActivity(
          'fake-bearer-token-12345678901234567890',
        );
      } catch (e) {
        caught = e;
      }
      // Any error is acceptable — what matters is no unhandled type errors
      expect(caught, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // getTopContent — requires bearer token as parameter
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.getTopContent', () {
    test('returns null when network call fails with fake token', () async {
      // getTopContent catches exceptions and returns null
      final result = await SpotifyBuddyService.instance.getTopContent(
        'fake-bearer-token-12345678901234567890',
      );
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // _parseUserFrom2026Api (exercised via getCurrentUserProfileWithToken guard)
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService._parseUserFrom2026Api defaults', () {
    // We can't call the private method directly, but we can verify defaults
    // are applied by calling getCurrentUserProfileWithToken with a fake token
    // that will fail network — only test the guard condition here.
    test('getCurrentUserProfileWithToken throws without network (guard fails fast)', () async {
      // The method makes a real HTTP call; in test environment it will fail.
      // What we verify: it doesn't crash with a Dart type error, only network error.
      Object? caught;
      try {
        await SpotifyBuddyService.instance
            .getCurrentUserProfileWithToken('fake-token');
      } catch (e) {
        caught = e;
      }
      // Any error is acceptable — what matters is no unhandled assertion/type errors
      expect(caught, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // parseFriendsJson — pure JSON parsing for buddylist API response
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.parseFriendsJson — track activity', () {
    // Fixed "now" so isCurrentlyPlaying is deterministic
    const nowMs = 1780948030000; // 30 seconds after the track timestamp below

    const trackBody = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:abc123", "name": "Alice", "imageUrl": "https://example.com/alice.jpg"},
      "track": {
        "uri": "spotify:track:xyz789",
        "name": "Test Song",
        "album": {"name": "Test Album", "uri": "spotify:album:alb123"},
        "artist": {"name": "Test Artist"},
        "imageUrl": "https://example.com/track.jpg",
        "duration_ms": 210000
      }
    }
  ]
}
''';

    test('strips spotify:user: prefix to get user id', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities.length, 1);
      expect(activities[0].user.id, 'abc123');
    });

    test('maps user displayName from name field', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].user.displayName, 'Alice');
    });

    test('maps user imageUrl', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].user.imageUrl, 'https://example.com/alice.jpg');
    });

    test('maps track name', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.name, 'Test Song');
    });

    test('maps track artist into artists list', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.artists, ['Test Artist']);
    });

    test('maps album name', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.album, 'Test Album');
    });

    test('maps albumUri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.albumUri, 'spotify:album:alb123');
    });

    test('maps track imageUrl', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.imageUrl, 'https://example.com/track.jpg');
    });

    test('durationMs is always 0 (not in buddylist response)', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.durationMs, 0);
    });

    test('maps track uri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.uri, 'spotify:track:xyz789');
    });

    test('type is ActivityType.track', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].type, ActivityType.track);
    });

    test('maps timestamp from epoch milliseconds', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(
        activities[0].timestamp,
        DateTime.fromMillisecondsSinceEpoch(1780948000000),
      );
    });

    test('isCurrentlyPlaying is true when elapsed time is within duration window', () {
      // nowMs = 1780948030000, timestamp = 1780948000000, elapsed = 30s = 30000ms
      // duration = 210000ms; 30000 < 210000 + 5000 → playing
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].isCurrentlyPlaying, isTrue);
    });

    test('isCurrentlyPlaying is false when track has finished', () {
      // Set nowMs to 5 minutes after timestamp, duration is 3.5 minutes → finished
      const oldNow = 1780948000000 + (5 * 60 * 1000); // 5 min later
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: oldNow);
      expect(activities[0].isCurrentlyPlaying, isFalse);
    });
  });

  group('SpotifyBuddyService.parseFriendsJson — playlist activity', () {
    const playlistBody = '''
{
  "friends": [
    {
      "timestamp": 1780947000000,
      "user": {"uri": "spotify:user:def456", "name": "Bob", "imageUrl": null},
      "playlist": {
        "uri": "spotify:playlist:plist123",
        "name": "Chill Mix",
        "description": "Great vibes",
        "imageUrl": "https://example.com/playlist.jpg",
        "trackCount": 20,
        "owner": {"id": "owner1", "name": "Owner Name"},
        "public": true
      }
    }
  ]
}
''';

    test('type is ActivityType.playlist', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].type, ActivityType.playlist);
    });

    test('maps playlist name', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.name, 'Chill Mix');
    });

    test('maps playlist description', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.description, 'Great vibes');
    });

    test('maps playlist imageUrl', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.imageUrl, 'https://example.com/playlist.jpg');
    });

    test('maps trackCount', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.trackCount, 20);
    });

    test('maps playlist uri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.uri, 'spotify:playlist:plist123');
    });

    test('extracts playlist id from last URI segment', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.id, 'plist123');
    });

    test('maps ownerId and ownerName', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.ownerId, 'owner1');
      expect(activities[0].playlist!.ownerName, 'Owner Name');
    });

    test('maps isPublic', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].playlist!.isPublic, isTrue);
    });

    test('isCurrentlyPlaying is always false for playlist', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].isCurrentlyPlaying, isFalse);
    });

    test('null user imageUrl is preserved as null', () {
      final activities = SpotifyBuddyService.parseFriendsJson(playlistBody);
      expect(activities[0].user.imageUrl, isNull);
    });
  });

  group('SpotifyBuddyService.parseFriendsJson — episode/podcast activity', () {
    const nowMs = 1780948030000;

    const episodeBody = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:carol789", "name": "Carol", "imageUrl": "https://example.com/carol.jpg"},
      "episode": {
        "uri": "spotify:episode:ep001",
        "name": "The Morning Rundown",
        "imageUrl": "https://example.com/episode.jpg",
        "show": {
          "uri": "spotify:show:show001",
          "name": "Daily News",
          "imageUrl": "https://example.com/show.jpg"
        }
      }
    }
  ]
}
''';

    test('episode entry produces one activity', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities.length, 1);
    });

    test('type is ActivityType.track for episode', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].type, ActivityType.track);
    });

    test('maps episode name to track name', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].track!.name, 'The Morning Rundown');
    });

    test('maps show name to artists and album', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].track!.artists, ['Daily News']);
      expect(activities[0].track!.album, 'Daily News');
    });

    test('maps show uri to albumUri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].track!.albumUri, 'spotify:show:show001');
    });

    test('maps episode imageUrl', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].track!.imageUrl, 'https://example.com/episode.jpg');
    });

    test('maps episode uri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].track!.uri, 'spotify:episode:ep001');
    });

    test('maps user from episode entry', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].user.displayName, 'Carol');
      expect(activities[0].user.id, 'carol789');
    });

    test('isCurrentlyPlaying true when within threshold', () {
      final activities = SpotifyBuddyService.parseFriendsJson(episodeBody, nowMs: nowMs);
      expect(activities[0].isCurrentlyPlaying, isTrue);
    });

    test('mixed track and episode friends both appear', () {
      const mixedBody = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:alice", "name": "Alice", "imageUrl": null},
      "track": {"uri": "spotify:track:t1", "name": "Song", "album": {"name": "Album", "uri": "spotify:album:a1"}, "artist": {"name": "Artist"}, "imageUrl": null}
    },
    {
      "timestamp": 1780948001000,
      "user": {"uri": "spotify:user:carol", "name": "Carol", "imageUrl": null},
      "episode": {"uri": "spotify:episode:e1", "name": "Podcast Ep", "imageUrl": null, "show": {"uri": "spotify:show:s1", "name": "Show"}}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(mixedBody);
      expect(activities.length, 2);
    });
  });

  group('SpotifyBuddyService.parseFriendsJson — sort and edge cases', () {
    test('returns activities sorted by timestamp descending (most recent first)', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780947000000,
      "user": {"uri": "spotify:user:bob", "name": "Bob", "imageUrl": null},
      "track": {"uri": "spotify:track:b", "name": "B Song", "album": {"name": "B Album"}, "artist": {"name": "B Artist"}, "imageUrl": null, "duration_ms": 180000}
    },
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:alice", "name": "Alice", "imageUrl": null},
      "track": {"uri": "spotify:track:a", "name": "A Song", "album": {"name": "A Album"}, "artist": {"name": "A Artist"}, "imageUrl": null, "duration_ms": 180000}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities[0].user.id, 'alice'); // later timestamp first
      expect(activities[1].user.id, 'bob');
    });

    test('returns empty list for empty friends array', () {
      const body = '{"friends": []}';
      expect(SpotifyBuddyService.parseFriendsJson(body), isEmpty);
    });

    test('returns empty list when friends key is absent', () {
      const body = '{"data": []}';
      expect(SpotifyBuddyService.parseFriendsJson(body), isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      expect(SpotifyBuddyService.parseFriendsJson('{bad json}'), isEmpty);
    });

    test('returns empty list for empty string input', () {
      expect(SpotifyBuddyService.parseFriendsJson(''), isEmpty);
    });

    test('missing duration_ms defaults durationMs to 0', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:x", "name": "X", "imageUrl": null},
      "track": {"uri": "spotify:track:t", "name": "T", "album": {"name": "A"}, "artist": {"name": "Ar"}, "imageUrl": null}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities[0].track!.durationMs, 0);
    });

    test('isCurrentlyPlaying is true when elapsed < 5 minutes', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:x", "name": "X", "imageUrl": null},
      "track": {"uri": "spotify:track:t", "name": "T", "album": {"name": "A"}, "artist": {"name": "Ar"}, "imageUrl": null}
    }
  ]
}
''';
      // elapsed = 0ms — well within the 5-minute threshold
      final activities = SpotifyBuddyService.parseFriendsJson(body, nowMs: 1780948000000);
      expect(activities[0].isCurrentlyPlaying, isTrue);
    });

    test('isCurrentlyPlaying is false when elapsed >= 5 minutes', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:x", "name": "X", "imageUrl": null},
      "track": {"uri": "spotify:track:t", "name": "T", "album": {"name": "A"}, "artist": {"name": "Ar"}, "imageUrl": null}
    }
  ]
}
''';
      // elapsed = 6 minutes — exceeds the 5-minute threshold
      final activities = SpotifyBuddyService.parseFriendsJson(
        body,
        nowMs: 1780948000000 + 6 * 60 * 1000,
      );
      expect(activities[0].isCurrentlyPlaying, isFalse);
    });

    test('skips friend entries without track or playlist', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:ghost", "name": "Ghost", "imageUrl": null}
    }
  ]
}
''';
      expect(SpotifyBuddyService.parseFriendsJson(body), isEmpty);
    });

    test('user id without spotify:user: prefix is preserved as-is', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "rawid", "name": "Raw", "imageUrl": null},
      "track": {"uri": "spotify:track:t", "name": "T", "album": {"name": "A"}, "artist": {"name": "Ar"}, "imageUrl": null, "duration_ms": 0}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities[0].user.id, 'rawid');
    });

    test('falls back to album imageUrl when track imageUrl is null', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:x", "name": "X", "imageUrl": null},
      "track": {"uri": "spotify:track:t", "name": "T", "album": {"name": "A", "imageUrl": "https://example.com/album.jpg"}, "artist": {"name": "Ar"}, "duration_ms": 0}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities[0].track!.imageUrl, 'https://example.com/album.jpg');
    });
  });

  group('SpotifyBuddyService.parseFriendsJson — context-only (browsing) activity', () {
    const contextBody = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:browser1", "name": "Browser", "imageUrl": null},
      "context": {"uri": "spotify:playlist:abc123", "name": "Chill Vibes", "imageUrl": "https://example.com/playlist.jpg"}
    }
  ]
}
''';

    test('context-only friend appears in results', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities.length, 1);
    });

    test('context activity has playlist type', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].type, ActivityType.playlist);
    });

    test('context playlist name is mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].playlist!.name, 'Chill Vibes');
    });

    test('context playlist uri is mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].playlist!.uri, 'spotify:playlist:abc123');
    });

    test('context playlist id is last segment of uri', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].playlist!.id, 'abc123');
    });

    test('context playlist imageUrl is mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].playlist!.imageUrl, 'https://example.com/playlist.jpg');
    });

    test('context friend user is mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].user.displayName, 'Browser');
    });

    test('context-only friend is not currently playing', () {
      final activities = SpotifyBuddyService.parseFriendsJson(contextBody);
      expect(activities[0].isCurrentlyPlaying, false);
    });

    test('mixed: track friend and context friend both appear', () {
      const mixedBody = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:u1", "name": "Player", "imageUrl": null},
      "track": {"uri": "spotify:track:t1", "name": "Song", "imageUrl": null, "album": {"name": "Album"}, "artist": {"name": "Artist"}}
    },
    {
      "timestamp": 1780947000000,
      "user": {"uri": "spotify:user:u2", "name": "Browser", "imageUrl": null},
      "context": {"uri": "spotify:playlist:p1", "name": "My Playlist", "imageUrl": null}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(mixedBody);
      expect(activities.length, 2);
      expect(activities[0].user.displayName, 'Player');
      expect(activities[1].user.displayName, 'Browser');
    });

    test('friend with empty context uri is skipped', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:u1", "name": "Ghost", "imageUrl": null},
      "context": {"uri": "", "name": "nothing"}
    }
  ]
}
''';
      expect(SpotifyBuddyService.parseFriendsJson(body), isEmpty);
    });

    test('friend with no activity keys at all is skipped', () {
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:u1", "name": "Ghost", "imageUrl": null}
    }
  ]
}
''';
      expect(SpotifyBuddyService.parseFriendsJson(body), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // parseFriendsJson — envelope-wrapped format {"friend": {...}}
  // This is the format returned by the current spclient API (post-2025 change).
  // ---------------------------------------------------------------------------

  group('SpotifyBuddyService.parseFriendsJson — envelope-wrapped format', () {
    const nowMs = 1780948030000;

    const envelopeTrackBody = '''
{
  "friends": [
    {
      "friend": {
        "timestamp": 1780948000000,
        "user": {"uri": "spotify:user:abc123", "name": "Alice", "imageUrl": "https://example.com/alice.jpg"},
        "track": {
          "uri": "spotify:track:xyz789",
          "name": "Test Song",
          "album": {"name": "Test Album", "uri": "spotify:album:alb123"},
          "artist": {"name": "Test Artist"},
          "imageUrl": "https://example.com/track.jpg"
        }
      }
    }
  ]
}
''';

    test('envelope-wrapped track activity is parsed', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities.length, 1);
    });

    test('envelope: user id extracted from nested user field', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].user.id, 'abc123');
    });

    test('envelope: user displayName mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].user.displayName, 'Alice');
    });

    test('envelope: track name mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].track!.name, 'Test Song');
    });

    test('envelope: track artist mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].track!.artists, ['Test Artist']);
    });

    test('envelope: album name mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].track!.album, 'Test Album');
    });

    test('envelope: track imageUrl mapped', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].track!.imageUrl, 'https://example.com/track.jpg');
    });

    test('envelope: type is ActivityType.track', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].type, ActivityType.track);
    });

    test('envelope: isCurrentlyPlaying true when elapsed < 5 minutes', () {
      final activities = SpotifyBuddyService.parseFriendsJson(envelopeTrackBody, nowMs: nowMs);
      expect(activities[0].isCurrentlyPlaying, isTrue);
    });

    test('envelope-wrapped playlist activity is parsed', () {
      const body = '''
{
  "friends": [
    {
      "friend": {
        "timestamp": 1780947000000,
        "user": {"uri": "spotify:user:def456", "name": "Bob", "imageUrl": null},
        "playlist": {
          "uri": "spotify:playlist:plist123",
          "name": "Chill Mix",
          "imageUrl": "https://example.com/playlist.jpg",
          "trackCount": 20,
          "owner": {"id": "owner1", "name": "Owner Name"},
          "public": true
        }
      }
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities.length, 1);
      expect(activities[0].type, ActivityType.playlist);
      expect(activities[0].playlist!.name, 'Chill Mix');
      expect(activities[0].user.displayName, 'Bob');
    });

    test('envelope-wrapped context-only activity is parsed', () {
      const body = '''
{
  "friends": [
    {
      "friend": {
        "timestamp": 1780948000000,
        "user": {"uri": "spotify:user:browser1", "name": "Browser", "imageUrl": null},
        "context": {"uri": "spotify:playlist:ctx123", "name": "My Mix", "imageUrl": null}
      }
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body);
      expect(activities.length, 1);
      expect(activities[0].type, ActivityType.playlist);
      expect(activities[0].playlist!.name, 'My Mix');
    });

    test('mixed envelope and flat entries in the same response are both parsed', () {
      const body = '''
{
  "friends": [
    {
      "friend": {
        "timestamp": 1780948000000,
        "user": {"uri": "spotify:user:u1", "name": "EnvelopeUser", "imageUrl": null},
        "track": {"uri": "spotify:track:t1", "name": "Envelope Song", "imageUrl": null, "album": {"name": "Album"}, "artist": {"name": "Artist"}}
      }
    },
    {
      "timestamp": 1780947000000,
      "user": {"uri": "spotify:user:u2", "name": "FlatUser", "imageUrl": null},
      "track": {"uri": "spotify:track:t2", "name": "Flat Song", "imageUrl": null, "album": {"name": "Album2"}, "artist": {"name": "Artist2"}}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body, nowMs: nowMs);
      expect(activities.length, 2);
      expect(activities[0].user.displayName, 'EnvelopeUser');
      expect(activities[1].user.displayName, 'FlatUser');
    });

    test('empty friend envelope falls back to top-level data', () {
      // Some API responses include "friend":{} as a marker while real data
      // sits at the top level — the empty envelope must not shadow it.
      const body = '''
{
  "friends": [
    {
      "timestamp": 1780948000000,
      "user": {"uri": "spotify:user:u1", "name": "TopLevel", "imageUrl": null},
      "track": {"uri": "spotify:track:t1", "name": "Top Song", "imageUrl": null, "album": {"name": "Album"}, "artist": {"name": "Artist"}},
      "friend": {}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body, nowMs: nowMs);
      expect(activities.length, 1);
      expect(activities[0].user.displayName, 'TopLevel');
      expect(activities[0].track!.name, 'Top Song');
    });

    test('multiple friends: proper envelope and top-level-with-empty-friend all parsed', () {
      const body = '''
{
  "friends": [
    {
      "friend": {
        "timestamp": 1780948000000,
        "user": {"uri": "spotify:user:u1", "name": "Enveloped", "imageUrl": null},
        "track": {"uri": "spotify:track:t1", "name": "Song A", "imageUrl": null, "album": {"name": "A"}, "artist": {"name": "Ar"}}
      }
    },
    {
      "timestamp": 1780947000000,
      "user": {"uri": "spotify:user:u2", "name": "TopLevel", "imageUrl": null},
      "track": {"uri": "spotify:track:t2", "name": "Song B", "imageUrl": null, "album": {"name": "B"}, "artist": {"name": "Ar"}},
      "friend": {}
    }
  ]
}
''';
      final activities = SpotifyBuddyService.parseFriendsJson(body, nowMs: nowMs);
      expect(activities.length, 2);
      expect(activities[0].user.displayName, 'Enveloped');
      expect(activities[1].user.displayName, 'TopLevel');
    });
  });
}
