import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/providers/spotify_provider.dart';

void main() {
  group('SpotifyProvider notifyListeners batching', () {
    late SpotifyProvider provider;

    setUp(() {
      provider = SpotifyProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('loadFriendsActivities without token sets error without crashing', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // No bearer token set — should set error and call notifyListeners
      await provider.loadFriendsActivities(showLoading: true);

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNotNull);
      // With batching: at most 2 notifies (start loading + done)
      expect(notifyCount, lessThanOrEqualTo(2));
    });

    test('loadCurrentlyPlaying without token calls notifyListeners at most twice', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.loadCurrentlyPlaying(showLoading: true);

      expect(provider.isLoading, isFalse);
      expect(notifyCount, lessThanOrEqualTo(2));
    });

    test('clearError notifies once', () async {
      await provider.loadFriendsActivities(); // sets error
      await Future.microtask(() {});

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);
      provider.clearError();

      expect(notifyCount, 1);
    });

    test('loadTopTracks without token sets error state and notifies once', () async {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.loadTopTracks(showLoading: true);

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNotNull);
      expect(notifyCount, equals(1));
    });
  });
}
