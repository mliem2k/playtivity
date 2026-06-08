// test/models/user_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/user.dart';
import '../helpers/test_fixtures.dart';

void main() {
  group('User.fromJson', () {
    test('parses all fields correctly', () {
      final user = User.fromJson(TestFixtures.userJson());
      expect(user.id, 'user_123');
      expect(user.displayName, 'Test User');
      expect(user.email, 'test@example.com');
      expect(user.imageUrl, 'https://example.com/avatar.jpg');
      expect(user.followers, 42);
      expect(user.country, 'US');
    });

    test('uses empty string defaults for missing string fields', () {
      final user = User.fromJson({});
      expect(user.id, '');
      expect(user.displayName, '');
      expect(user.email, '');
      expect(user.imageUrl, isNull);
      expect(user.followers, 0);
      expect(user.country, '');
    });

    test('imageUrl is null when not present', () {
      final json = Map<String, dynamic>.from(TestFixtures.userJson())
        ..remove('image_url');
      final user = User.fromJson(json);
      expect(user.imageUrl, isNull);
    });
  });

  group('User.fromSpotifyApi', () {
    test('extracts imageUrl from images array', () {
      final user = User.fromSpotifyApi(TestFixtures.spotifyUserApiJson());
      expect(user.imageUrl, 'https://example.com/avatar.jpg');
    });

    test('extracts followers from nested total field', () {
      final user = User.fromSpotifyApi(TestFixtures.spotifyUserApiJson());
      expect(user.followers, 42);
    });

    test('imageUrl is null when images array is empty', () {
      final json = Map<String, dynamic>.from(TestFixtures.spotifyUserApiJson())
        ..['images'] = [];
      final user = User.fromSpotifyApi(json);
      expect(user.imageUrl, isNull);
    });
  });

  group('User.toJson', () {
    test('serializes all fields', () {
      final user = User.fromJson(TestFixtures.userJson());
      final json = user.toJson();
      expect(json['id'], 'user_123');
      expect(json['display_name'], 'Test User');
      expect(json['email'], 'test@example.com');
      expect(json['image_url'], 'https://example.com/avatar.jpg');
      expect(json['followers'], 42);
      expect(json['country'], 'US');
    });

    test('round-trips through fromJson → toJson → fromJson', () {
      final original = User.fromJson(TestFixtures.userJson());
      final roundTripped = User.fromJson(original.toJson());
      expect(roundTripped.id, original.id);
      expect(roundTripped.displayName, original.displayName);
      expect(roundTripped.email, original.email);
      expect(roundTripped.imageUrl, original.imageUrl);
      expect(roundTripped.followers, original.followers);
      expect(roundTripped.country, original.country);
    });
  });
}
