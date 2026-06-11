// test/models/activity_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/activity.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Activity.fromJson - track type', () {
    test('parses track activity correctly', () {
      final activity = Activity.fromJson(TestFixtures.trackActivityJson());
      expect(activity.type, ActivityType.track);
      expect(activity.track, isNotNull);
      expect(activity.playlist, isNull);
      expect(activity.isCurrentlyPlaying, isTrue);
      expect(activity.user.id, 'user_123');
      expect(activity.track!.name, 'Test Song');
    });

    test('parses timestamp as UTC DateTime', () {
      final activity = Activity.fromJson(TestFixtures.trackActivityJson());
      expect(activity.timestamp, DateTime.parse('2026-06-08T10:00:00.000Z'));
    });
  });

  group('Activity.fromJson - playlist type', () {
    test('parses playlist activity correctly', () {
      final activity = Activity.fromJson(TestFixtures.playlistActivityJson());
      expect(activity.type, ActivityType.playlist);
      expect(activity.playlist, isNotNull);
      expect(activity.track, isNull);
      expect(activity.isCurrentlyPlaying, isFalse);
      expect(activity.playlist!.name, 'My Playlist');
    });
  });

  group('Activity computed getters', () {
    test('contentName returns track name for track activity', () {
      final activity = Activity.fromJson(TestFixtures.trackActivityJson());
      expect(activity.contentName, 'Test Song');
    });

    test('contentName returns playlist name for playlist activity', () {
      final activity = Activity.fromJson(TestFixtures.playlistActivityJson());
      expect(activity.contentName, 'My Playlist');
    });

    test('contentSubtitle returns artists for track activity', () {
      final activity = Activity.fromJson(TestFixtures.trackActivityJson());
      expect(activity.contentSubtitle, 'Artist One, Artist Two');
    });

    test('contentSubtitle returns track count for playlist activity', () {
      final activity = Activity.fromJson(TestFixtures.playlistActivityJson());
      expect(activity.contentSubtitle, contains('Playlist'));
      expect(activity.contentSubtitle, contains('25'));
    });
  });

  group('Activity.toJson', () {
    test('serializes track activity fields correctly', () {
      final activity = Activity.fromJson(TestFixtures.trackActivityJson());
      final json = activity.toJson();
      expect(json['type'], 'track');
      expect(json['is_currently_playing'], isTrue);
      expect(json['track'], isNotNull);
      expect(json['playlist'], isNull);
      expect(json['timestamp'], '2026-06-08T10:00:00.000Z');
    });

    test('serializes playlist activity fields correctly', () {
      final activity = Activity.fromJson(TestFixtures.playlistActivityJson());
      final json = activity.toJson();
      expect(json['type'], 'playlist');
      expect(json['is_currently_playing'], isFalse);
      expect(json['playlist'], isNotNull);
      expect(json['track'], isNull);
    });
  });

  group('Activity round-trip (toJson -> fromJson)', () {
    test('track activity survives persistence serialization', () {
      final original = Activity.fromJson(TestFixtures.trackActivityJson());
      final roundTripped = Activity.fromJson(original.toJson());
      expect(roundTripped.type, ActivityType.track);
      expect(roundTripped.user.id, original.user.id);
      expect(roundTripped.user.displayName, original.user.displayName);
      expect(roundTripped.track!.name, original.track!.name);
      expect(roundTripped.track!.artists, original.track!.artists);
      expect(roundTripped.track!.album, original.track!.album);
      expect(roundTripped.track!.albumUri, original.track!.albumUri);
      expect(roundTripped.track!.imageUrl, original.track!.imageUrl);
      expect(roundTripped.timestamp, original.timestamp);
      expect(roundTripped.isCurrentlyPlaying, original.isCurrentlyPlaying);
    });

    test('playlist activity survives persistence serialization', () {
      final original = Activity.fromJson(TestFixtures.playlistActivityJson());
      final roundTripped = Activity.fromJson(original.toJson());
      expect(roundTripped.type, ActivityType.playlist);
      expect(roundTripped.user.id, original.user.id);
      expect(roundTripped.playlist!.name, original.playlist!.name);
      expect(roundTripped.playlist!.imageUrl, original.playlist!.imageUrl);
      expect(roundTripped.playlist!.trackCount, original.playlist!.trackCount);
      expect(roundTripped.playlist!.ownerId, original.playlist!.ownerId);
      expect(roundTripped.timestamp, original.timestamp);
    });
  });
}
