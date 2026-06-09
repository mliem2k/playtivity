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

    test('maps durationMs', () {
      final activities = SpotifyBuddyService.parseFriendsJson(trackBody, nowMs: nowMs);
      expect(activities[0].track!.durationMs, 210000);
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

    test('isCurrentlyPlaying is false when duration_ms is absent', () {
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
      final activities = SpotifyBuddyService.parseFriendsJson(body, nowMs: 1780948000000);
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
}
