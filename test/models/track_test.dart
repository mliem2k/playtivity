// test/models/track_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/track.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('Track.fromJson', () {
    test('parses all fields correctly', () {
      final track = Track.fromJson(TestFixtures.trackJson());
      expect(track.id, 'track_abc');
      expect(track.name, 'Test Song');
      expect(track.artists, ['Artist One', 'Artist Two']);
      expect(track.artistUris, ['spotify:artist:111', 'spotify:artist:222']);
      expect(track.album, 'Test Album');
      expect(track.albumUri, 'spotify:album:xyz');
      expect(track.imageUrl, 'https://example.com/album.jpg');
      expect(track.durationMs, 210000);
      expect(track.previewUrl, 'https://example.com/preview.mp3');
      expect(track.uri, 'spotify:track:abc');
    });

    test('handles missing artists gracefully', () {
      final json = Map<String, dynamic>.from(TestFixtures.trackJson())
        ..remove('artists');
      final track = Track.fromJson(json);
      expect(track.artists, isEmpty);
      expect(track.artistUris, isEmpty);
    });

    test('handles missing album gracefully', () {
      final json = Map<String, dynamic>.from(TestFixtures.trackJson())
        ..remove('album');
      final track = Track.fromJson(json);
      expect(track.album, '');
      expect(track.albumUri, isNull);
      expect(track.imageUrl, isNull);
    });

    test('previewUrl is null when not present', () {
      final json = Map<String, dynamic>.from(TestFixtures.trackJson())
        ..['preview_url'] = null;
      final track = Track.fromJson(json);
      expect(track.previewUrl, isNull);
    });
  });

  group('Track computed properties', () {
    late Track track;
    setUp(() => track = Track.fromJson(TestFixtures.trackJson()));

    test('artistsString joins with comma', () {
      expect(track.artistsString, 'Artist One, Artist Two');
    });

    test('duration formats mm:ss correctly', () {
      // 210000ms = 3 minutes 30 seconds
      expect(track.duration, '3:30');
    });

    test('firstArtistUri returns first URI', () {
      expect(track.firstArtistUri, 'spotify:artist:111');
    });

    test('firstArtistUri is null when no artist URIs', () {
      final json = Map<String, dynamic>.from(TestFixtures.trackJson())
        ..remove('artists');
      final emptyTrack = Track.fromJson(json);
      expect(emptyTrack.firstArtistUri, isNull);
    });
  });

  group('Track.toJson', () {
    test('serializes all fields correctly', () {
      final track = Track.fromJson(TestFixtures.trackJson());
      final json = track.toJson();
      expect(json['id'], 'track_abc');
      expect(json['name'], 'Test Song');
      expect(json['artists'], ['Artist One', 'Artist Two']);
      expect(json['artist_uris'], ['spotify:artist:111', 'spotify:artist:222']);
      expect(json['album'], 'Test Album');
      expect(json['album_uri'], 'spotify:album:xyz');
      expect(json['image_url'], 'https://example.com/album.jpg');
      expect(json['duration_ms'], 210000);
      expect(json['preview_url'], 'https://example.com/preview.mp3');
      expect(json['uri'], 'spotify:track:abc');
    });
  });
}
