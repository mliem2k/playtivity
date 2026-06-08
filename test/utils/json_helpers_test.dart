// test/utils/json_helpers_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/utils/json_helpers.dart';

void main() {
  group('JsonHelpers.getString', () {
    test('returns string value for existing key', () {
      expect(JsonHelpers.getString({'name': 'Alice'}, 'name'), 'Alice');
    });

    test('returns default empty string for missing key', () {
      expect(JsonHelpers.getString({}, 'name'), '');
    });

    test('returns custom default for missing key', () {
      expect(JsonHelpers.getString({}, 'name', 'Unknown'), 'Unknown');
    });

    test('returns default for null value', () {
      expect(JsonHelpers.getString({'name': null}, 'name'), '');
    });
  });

  group('JsonHelpers.getInt', () {
    test('returns int value for existing key', () {
      expect(JsonHelpers.getInt({'count': 5}, 'count'), 5);
    });

    test('returns 0 for missing key', () {
      expect(JsonHelpers.getInt({}, 'count'), 0);
    });

    test('returns custom default for missing key', () {
      expect(JsonHelpers.getInt({}, 'count', -1), -1);
    });
  });

  group('JsonHelpers.getBool', () {
    test('returns bool value for existing key', () {
      expect(JsonHelpers.getBool({'active': true}, 'active'), isTrue);
    });

    test('returns false for missing key', () {
      expect(JsonHelpers.getBool({}, 'active'), isFalse);
    });
  });

  group('JsonHelpers.getNestedString', () {
    test('returns nested string value', () {
      expect(
        JsonHelpers.getNestedString({'album': {'name': 'Dark Side'}}, ['album', 'name']),
        'Dark Side',
      );
    });

    test('returns default for missing path', () {
      expect(
        JsonHelpers.getNestedString({'album': {}}, ['album', 'name']),
        '',
      );
    });

    test('returns default when top-level key missing', () {
      expect(
        JsonHelpers.getNestedString({}, ['album', 'name']),
        '',
      );
    });
  });

  group('JsonHelpers.getNestedInt', () {
    test('returns nested int value', () {
      expect(
        JsonHelpers.getNestedInt({'followers': {'total': 100}}, ['followers', 'total']),
        100,
      );
    });

    test('returns 0 for missing path', () {
      expect(
        JsonHelpers.getNestedInt({'followers': {}}, ['followers', 'total']),
        0,
      );
    });
  });

  group('JsonHelpers.getSpotifyImageUrl', () {
    test('returns first image URL', () {
      final json = {
        'images': [
          {'url': 'https://img1.example.com', 'height': 300},
          {'url': 'https://img2.example.com', 'height': 100},
        ]
      };
      expect(JsonHelpers.getSpotifyImageUrl(json), 'https://img1.example.com');
    });

    test('returns null for empty images array', () {
      expect(JsonHelpers.getSpotifyImageUrl({'images': []}), isNull);
    });

    test('returns null for missing images key', () {
      expect(JsonHelpers.getSpotifyImageUrl({}), isNull);
    });
  });

  group('JsonHelpers.getSpotifyArtists', () {
    test('extracts names and URIs from artists array', () {
      final json = {
        'artists': [
          {'name': 'Radiohead', 'uri': 'spotify:artist:4Z8W4fKeB5YxbusRsdQVPb'},
          {'name': 'Thom Yorke', 'uri': 'spotify:artist:xyz'},
        ]
      };
      final result = JsonHelpers.getSpotifyArtists(json);
      expect(result.names, ['Radiohead', 'Thom Yorke']);
      expect(result.uris, ['spotify:artist:4Z8W4fKeB5YxbusRsdQVPb', 'spotify:artist:xyz']);
    });

    test('falls back to singular artist field', () {
      final json = {
        'artist': {'name': 'Solo Artist', 'uri': 'spotify:artist:solo'}
      };
      final result = JsonHelpers.getSpotifyArtists(json);
      expect(result.names, ['Solo Artist']);
      expect(result.uris, ['spotify:artist:solo']);
    });

    test('returns empty lists when no artist fields', () {
      final result = JsonHelpers.getSpotifyArtists({});
      expect(result.names, isEmpty);
      expect(result.uris, isEmpty);
    });

    test('filters out empty URIs', () {
      final json = {
        'artists': [
          {'name': 'Artist', 'uri': ''},
          {'name': 'Artist 2', 'uri': 'spotify:artist:valid'},
        ]
      };
      final result = JsonHelpers.getSpotifyArtists(json);
      expect(result.uris, ['spotify:artist:valid']);
    });
  });

  group('JsonHelpers.validateRequiredFields', () {
    test('does not throw when all required fields present', () {
      expect(
        () => JsonHelpers.validateRequiredFields({'id': '1', 'name': 'Test'}, ['id', 'name']),
        returnsNormally,
      );
    });

    test('throws ArgumentError when a required field is missing', () {
      expect(
        () => JsonHelpers.validateRequiredFields({'id': '1'}, ['id', 'name']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when a required field is null', () {
      expect(
        () => JsonHelpers.validateRequiredFields({'id': null}, ['id']),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
