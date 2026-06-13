import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/providers/spotify_provider.dart';
import 'package:playtivity/services/spotify_buddy_service.dart';
import 'package:playtivity/models/activity.dart';

import '../helpers/test_fixtures.dart';

/// Fake buddy service that lets a test control what [getFriendActivity]
/// returns (or throws) and what [cachedActivities] holds, without any network.
class _FakeBuddyService extends SpotifyBuddyService {
  _FakeBuddyService() : super.forTesting();

  List<Activity> result = [];
  Object? throwError;
  List<Activity>? cache;

  @override
  Future<List<Activity>> getFriendActivity(String bearerToken) async {
    final err = throwError;
    if (err != null) throw err;
    return result;
  }

  @override
  List<Activity>? get cachedActivities => cache;
}

Activity _activity(String userId) {
  final json = Map<String, dynamic>.from(TestFixtures.trackActivityJson());
  json['user'] = {
    ...TestFixtures.userJson(),
    'id': userId,
    'display_name': 'Friend $userId',
  };
  return Activity.fromJson(json);
}

void main() {
  group('SpotifyProvider constructor primes from persisted cache', () {
    test('primes friendsActivities from cache without auth', () async {
      final fake = _FakeBuddyService()
        ..cache = [_activity('a'), _activity('b')];
      final provider = SpotifyProvider(buddyService: fake);
      addTearDown(provider.dispose);

      // persistenceReady is Future.value() in forTesting(), so it resolves on
      // the next microtask. Drain the microtask queue.
      await Future.microtask(() {});

      expect(provider.friendsActivities, hasLength(2),
          reason: 'stale friends should appear before any auth or network call');
    });

    test('does not notify when cache is empty', () async {
      final fake = _FakeBuddyService(); // cache = null
      final provider = SpotifyProvider(buddyService: fake);
      addTearDown(provider.dispose);

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      await Future.microtask(() {});

      expect(notifyCount, 0,
          reason: 'no notify should fire when there is nothing to prime with');
    });

    test('does not overwrite existing friendsActivities', () async {
      final fake = _FakeBuddyService()
        ..result = [_activity('live')]
        ..cache = [_activity('stale-a'), _activity('stale-b')];
      final provider = SpotifyProvider(buddyService: fake);
      provider.setBearer('dummy-token');
      addTearDown(provider.dispose);

      // Simulate a live fetch populating the list first.
      await provider.loadFriendsActivities();
      final afterLive = provider.friendsActivities.length;

      // Drain the priming microtask — it must not clobber the live result.
      await Future.microtask(() {});

      expect(provider.friendsActivities, hasLength(afterLive),
          reason: 'constructor priming must not overwrite data already loaded');
    });
  });

  group('SpotifyProvider preserves friends on failed/empty refresh', () {
    late _FakeBuddyService fake;
    late SpotifyProvider provider;

    setUp(() {
      fake = _FakeBuddyService();
      provider = SpotifyProvider(buddyService: fake);
      provider.setBearer('dummy-token');
    });

    tearDown(() => provider.dispose());

    test('a refresh that throws does not wipe the friends already shown',
        () async {
      fake.result = [_activity('a'), _activity('b')];
      await provider.loadFriendsActivities();
      expect(provider.friendsActivities, hasLength(2));

      // A later silent refresh hits a transient (non-auth) error.
      fake.throwError = Exception('Failed to fetch friend activity: 500');
      await provider.loadFriendsActivities();

      // The widget keeps showing data, so the app page must too.
      expect(provider.friendsActivities, hasLength(2),
          reason: 'failed refresh must not drop to zero cards');
    });

    test('when current list is empty, a throwing refresh recovers from cache',
        () async {
      // Nothing on screen yet, but the buddy service has accumulated data
      // (the same source the home widget renders from).
      fake.throwError = Exception('Failed to fetch friend activity: 500');
      fake.cache = [_activity('a'), _activity('b'), _activity('c')];

      await provider.loadFriendsActivities();

      expect(provider.friendsActivities, hasLength(3),
          reason: 'should fall back to the widget cache instead of showing 0');
    });

    test('a successful empty refresh does not wipe a populated feed', () async {
      fake.result = [_activity('a')];
      await provider.loadFriendsActivities();
      expect(provider.friendsActivities, hasLength(1));

      // Spotify's buddylist intermittently returns an empty feed even when
      // friends are active. The home widget never blanks on an empty refresh,
      // so the in-app list must stay consistent and keep showing the friends.
      fake.result = [];
      await provider.loadFriendsActivities();
      expect(provider.friendsActivities, hasLength(1),
          reason: 'empty success must not drop to zero cards');
    });

    test('an empty refresh with nothing on screen recovers from cache',
        () async {
      // Cold start: live fetch comes back empty, but the buddy service has
      // accumulated data (the same source the home widget renders from).
      fake.result = [];
      fake.cache = [_activity('a'), _activity('b')];

      await provider.loadFriendsActivities();

      expect(provider.friendsActivities, hasLength(2),
          reason: 'should fall back to the widget cache instead of showing 0');
    });

    test('a live result shorter than the accumulated cache keeps the cache',
        () async {
      // The home widget renders from the accumulated cache. If a live fetch
      // somehow returns fewer friends than the cache, the app must not drop
      // the accumulated friends and end up showing less than the widget.
      fake.cache = [_activity('a'), _activity('b'), _activity('c')];
      fake.result = [_activity('d')];

      await provider.loadFriendsActivities();

      expect(provider.friendsActivities, hasLength(3),
          reason: 'should keep accumulated cache when live result is shorter');
    });

    test('a live result longer than the accumulated cache uses the live result',
        () async {
      // When the live fetch accumulates more friends than the in-memory cache,
      // the app should show the larger merged result.
      fake.cache = [_activity('a')];
      fake.result = [_activity('a'), _activity('b'), _activity('c')];

      await provider.loadFriendsActivities();

      expect(provider.friendsActivities, hasLength(3),
          reason: 'should use live result when it is larger than cache');
    });
  });
}
