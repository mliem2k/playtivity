// test/models/playlist_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/playlist.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Playlist.fromJson', () {
    test('parses all fields correctly', () {
      final playlist = Playlist.fromJson(TestFixtures.playlistJson());
      expect(playlist.id, 'playlist_123');
      expect(playlist.name, 'My Playlist');
      expect(playlist.description, 'A test playlist');
      expect(playlist.imageUrl, 'https://example.com/playlist.jpg');
      expect(playlist.trackCount, 25);
      expect(playlist.uri, 'spotify:playlist:123');
      expect(playlist.ownerId, 'owner_456');
      expect(playlist.ownerName, 'Owner Name');
      expect(playlist.isPublic, isTrue);
    });

    test('uses defaults for missing fields', () {
      final playlist = Playlist.fromJson({});
      expect(playlist.id, '');
      expect(playlist.name, '');
      expect(playlist.imageUrl, isNull);
      expect(playlist.trackCount, 0);
      expect(playlist.isPublic, isFalse);
    });

    test('imageUrl is null when images array is empty', () {
      final json = Map<String, dynamic>.from(TestFixtures.playlistJson())
        ..['images'] = [];
      final playlist = Playlist.fromJson(json);
      expect(playlist.imageUrl, isNull);
    });

    test('toJson serializes all fields correctly', () {
      final original = Playlist.fromJson(TestFixtures.playlistJson());
      final json = original.toJson();
      expect(json['id'], original.id);
      expect(json['name'], original.name);
      expect(json['track_count'], original.trackCount);
      expect(json['uri'], original.uri);
      expect(json['owner_id'], original.ownerId);
      expect(json['owner_name'], original.ownerName);
      expect(json['is_public'], original.isPublic);
    });

    test('round-trip preserves all fields through persistence serialization', () {
      final original = Playlist.fromJson(TestFixtures.playlistJson());
      final roundTripped = Playlist.fromJson(original.toJson());
      expect(roundTripped.id, original.id);
      expect(roundTripped.name, original.name);
      expect(roundTripped.description, original.description);
      expect(roundTripped.imageUrl, original.imageUrl);
      expect(roundTripped.trackCount, original.trackCount);
      expect(roundTripped.uri, original.uri);
      expect(roundTripped.ownerId, original.ownerId);
      expect(roundTripped.ownerName, original.ownerName);
      expect(roundTripped.isPublic, original.isPublic);
    });
  });
}
