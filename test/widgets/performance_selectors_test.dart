import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/activity.dart';

// isCurrentlyPlaying is recomputed from the timestamp in Activity.fromJson, so
// control the result through the timestamp rather than the stored flag.
Activity _makeActivity({
  required String userId,
  bool isCurrentlyPlaying = false,
  String? timestamp,
}) {
  final ts = timestamp ??
      (isCurrentlyPlaying
          ? DateTime.now().subtract(const Duration(seconds: 30)).toIso8601String()
          : '2026-01-01T10:00:00.000Z');
  return Activity.fromJson({
    'user': {
      'id': userId,
      'display_name': 'User $userId',
      'email': 'u@example.com',
      'image_url': null,
      'followers': 0,
      'country': 'US',
    },
    'track': {
      'id': 'track_1',
      'name': 'Song',
      'artists': [{'name': 'Artist', 'uri': 'spotify:artist:1'}],
      'album': {
        'name': 'Album',
        'uri': 'spotify:album:1',
        'images': <Map<String, dynamic>>[],
      },
      'duration_ms': 200000,
      'preview_url': null,
      'uri': 'spotify:track:1',
    },
    'playlist': null,
    'timestamp': ts,
    'is_currently_playing': isCurrentlyPlaying,
    'type': 'track',
  });
}

// Mirror the shouldRebuild logic from ActivitiesScreenDataSelector
bool _shouldRebuild(List<Activity> previous, List<Activity> next) {
  if (previous.length != next.length) return true;
  for (int i = 0; i < previous.length; i++) {
    if (previous[i].isCurrentlyPlaying != next[i].isCurrentlyPlaying ||
        previous[i].timestamp != next[i].timestamp ||
        previous[i].contentUri != next[i].contentUri) {
      return true;
    }
  }
  return false;
}

void main() {
  group('ActivitiesScreenDataSelector shouldRebuild logic', () {
    test('returns false when lists are identical', () {
      final a = _makeActivity(userId: 'u1', isCurrentlyPlaying: false);
      expect(_shouldRebuild([a], [a]), isFalse);
    });

    test('returns true when list length changes', () {
      final a = _makeActivity(userId: 'u1', isCurrentlyPlaying: false);
      expect(_shouldRebuild([], [a]), isTrue);
    });

    test('returns true when isCurrentlyPlaying changes without length change', () {
      final before = _makeActivity(userId: 'u1', isCurrentlyPlaying: false);
      final after = _makeActivity(userId: 'u1', isCurrentlyPlaying: true);
      expect(_shouldRebuild([before], [after]), isTrue);
    });

    test('returns false when same number of activities with same content', () {
      // Share a fixed recent timestamp so both activities have identical fields.
      final recentTs =
          DateTime.now().subtract(const Duration(seconds: 30)).toIso8601String();
      final a = _makeActivity(userId: 'u1', isCurrentlyPlaying: true, timestamp: recentTs);
      final b = _makeActivity(userId: 'u1', isCurrentlyPlaying: true, timestamp: recentTs);
      expect(_shouldRebuild([a], [b]), isFalse);
    });

    test('returns true when timestamp changes', () {
      final before = _makeActivity(
        userId: 'u1',
        isCurrentlyPlaying: false,
        timestamp: '2026-06-10T10:00:00.000Z',
      );
      final after = _makeActivity(
        userId: 'u1',
        isCurrentlyPlaying: false,
        timestamp: '2026-06-10T11:00:00.000Z',
      );
      expect(_shouldRebuild([before], [after]), isTrue);
    });
  });
}
