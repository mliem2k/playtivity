// test/helpers/test_fixtures.dart
class TestFixtures {
  static Map<String, dynamic> userJson() => {
    'id': 'user_123',
    'display_name': 'Test User',
    'email': 'test@example.com',
    'image_url': 'https://example.com/avatar.jpg',
    'followers': 42,
    'country': 'US',
  };

  static Map<String, dynamic> spotifyUserApiJson() => {
    'id': 'user_123',
    'display_name': 'Test User',
    'email': 'test@example.com',
    'images': [
      {'url': 'https://example.com/avatar.jpg', 'height': 300, 'width': 300}
    ],
    'followers': {'total': 42, 'href': null},
    'country': 'US',
  };

  static Map<String, dynamic> trackJson() => {
    'id': 'track_abc',
    'name': 'Test Song',
    'artists': [
      {'name': 'Artist One', 'uri': 'spotify:artist:111'},
      {'name': 'Artist Two', 'uri': 'spotify:artist:222'},
    ],
    'album': {
      'name': 'Test Album',
      'uri': 'spotify:album:xyz',
      'images': [
        {'url': 'https://example.com/album.jpg', 'height': 300, 'width': 300}
      ],
    },
    'duration_ms': 210000,
    'preview_url': 'https://example.com/preview.mp3',
    'uri': 'spotify:track:abc',
  };

  static Map<String, dynamic> playlistJson() => {
    'id': 'playlist_123',
    'name': 'My Playlist',
    'description': 'A test playlist',
    'images': [
      {'url': 'https://example.com/playlist.jpg'}
    ],
    'tracks': {'total': 25},
    'uri': 'spotify:playlist:123',
    'owner': {'id': 'owner_456', 'display_name': 'Owner Name'},
    'public': true,
  };

  static Map<String, dynamic> trackActivityJson() => {
    'user': userJson(),
    'track': trackJson(),
    'playlist': null,
    'timestamp': '2026-06-08T10:00:00.000Z',
    'is_currently_playing': true,
    'type': 'track',
  };

  static Map<String, dynamic> playlistActivityJson() => {
    'user': userJson(),
    'track': null,
    'playlist': playlistJson(),
    'timestamp': '2026-06-08T09:30:00.000Z',
    'is_currently_playing': false,
    'type': 'playlist',
  };
}
