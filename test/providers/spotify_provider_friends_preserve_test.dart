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

    test('a successful empty refresh is still honored', () async {
      fake.result = [_activity('a')];
      await provider.loadFriendsActivities();
      expect(provider.friendsActivities, hasLength(1));

      // Service genuinely reports an empty (post-merge) result — honor it.
      fake.result = [];
      await provider.loadFriendsActivities();
      expect(provider.friendsActivities, isEmpty);
    });
  });
}
