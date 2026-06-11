import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtivity/services/spotify_buddy_service.dart';
import 'package:playtivity/services/http_interceptor.dart';
import 'package:playtivity/models/artist.dart';

// ---------------------------------------------------------------------------
// Fake GraphQL response fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _topContentResponse({
  List<Map<String, dynamic>> tracks = const [],
  List<Map<String, dynamic>> artists = const [],
}) =>
    {
      'data': {
        'me': {
          'profile': {
            'topTracks': {'items': tracks},
            'topArtists': {'items': artists},
          }
        }
      }
    };

Map<String, dynamic> _trackItem(String id, String name, String artist) => {
      'data': {
        'uri': 'spotify:track:$id',
        'name': name,
        'duration': {'totalMilliseconds': 210000},
        'albumOfTrack': {
          'name': 'Test Album',
          'uri': 'spotify:album:alb1',
          'coverArt': {
            'sources': [
              {'height': 300, 'width': 300, 'url': 'https://example.com/300.jpg'},
              {'height': 640, 'width': 640, 'url': 'https://example.com/640.jpg'},
            ]
          }
        },
        'artists': {
          'items': [
            {'profile': {'name': artist}}
          ]
        }
      }
    };

Map<String, dynamic> _artistItem(String id, String name) => {
      'data': {
        '__typename': 'Artist',
        'uri': 'spotify:artist:$id',
        'profile': {'name': name},
        'visuals': {
          'avatarImage': {
            'sources': [
              {'height': 640, 'width': 640, 'url': 'https://example.com/artist-640.jpg'},
              {'height': 320, 'width': 320, 'url': 'https://example.com/artist-320.jpg'},
              {'height': 160, 'width': 160, 'url': 'https://example.com/artist-160.jpg'},
            ]
          }
        }
      }
    };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sets [HttpInterceptor.testClient] to return [body] with HTTP 200 for any
/// request, and captures every request made so tests can assert on headers.
List<http.Request> _installMock(String body, {int statusCode = 200}) {
  final captured = <http.Request>[];
  HttpInterceptor.testClient = MockClient((req) async {
    captured.add(req);
    return http.Response(body, statusCode);
  });
  return captured;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SpotifyBuddyService.instance.clearActivityCache();
    SpotifyBuddyService.instance.clearArtistDetailsCache();
  });

  tearDown(() {
    HttpInterceptor.testClient = null;
    SpotifyBuddyService.instance.clearArtistDetailsCache();
  });

  // ---------------------------------------------------------------------------
  // getTopContent — header contract
  // ---------------------------------------------------------------------------

  group('getTopContent — request headers', () {
    test('does NOT send a client-token header', () async {
      final requests = _installMock(
        json.encode(_topContentResponse()),
      );

      await SpotifyBuddyService.instance
          .getTopContent('fake-token-abc12345678901234567890');

      expect(requests, hasLength(1));
      expect(requests.first.headers.containsKey('client-token'), isFalse);
    });

    test('sends authorization header with Bearer token', () async {
      final requests = _installMock(json.encode(_topContentResponse()));

      await SpotifyBuddyService.instance
          .getTopContent('mytoken12345678901234567890');

      expect(requests, hasLength(1));
      expect(
        requests.first.headers['authorization'],
        'Bearer mytoken12345678901234567890',
      );
    });

    test('sends app-platform WebPlayer header', () async {
      final requests = _installMock(json.encode(_topContentResponse()));

      await SpotifyBuddyService.instance
          .getTopContent('fake-token-abc12345678901234567890');

      expect(requests.first.headers['app-platform'], 'WebPlayer');
    });
  });

  // ---------------------------------------------------------------------------
  // getTopTracks — parsing
  // ---------------------------------------------------------------------------

  group('getTopTracks — response parsing', () {
    test('returns tracks with correct names and artist', () async {
      _installMock(json.encode(_topContentResponse(
        tracks: [
          _trackItem('t1', 'Blinding Lights', 'The Weeknd'),
          _trackItem('t2', 'Counting Stars', 'OneRepublic'),
        ],
      )));

      final tracks = await SpotifyBuddyService.instance
          .getTopTracks('fake-token-abc12345678901234567890');

      expect(tracks, hasLength(2));
      expect(tracks[0].name, 'Blinding Lights');
      expect(tracks[0].artists, contains('The Weeknd'));
      expect(tracks[1].name, 'Counting Stars');
    });

    test('prefers 300px cover art over higher resolution', () async {
      _installMock(json.encode(_topContentResponse(
        tracks: [_trackItem('t1', 'Track', 'Artist')],
      )));

      final tracks = await SpotifyBuddyService.instance
          .getTopTracks('fake-token-abc12345678901234567890');

      expect(tracks[0].imageUrl, 'https://example.com/300.jpg');
    });

    test('returns empty list when API returns null data', () async {
      _installMock('{"data":{"me":{"profile":{"topTracks":{"items":[]}}}}}');

      final tracks = await SpotifyBuddyService.instance
          .getTopTracks('fake-token-abc12345678901234567890');

      expect(tracks, isEmpty);
    });

    test('returns empty list on HTTP 401', () async {
      _installMock('', statusCode: 401);

      final tracks = await SpotifyBuddyService.instance
          .getTopTracks('fake-token-abc12345678901234567890');

      expect(tracks, isEmpty);
    });

    test('returns empty list on network error', () async {
      HttpInterceptor.testClient = MockClient((_) async => throw Exception('timeout'));

      final tracks = await SpotifyBuddyService.instance
          .getTopTracks('fake-token-abc12345678901234567890');

      expect(tracks, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getTopArtists — parsing
  // ---------------------------------------------------------------------------

  group('getTopArtists — response parsing', () {
    test('returns artists with correct names', () async {
      _installMock(json.encode(_topContentResponse(
        artists: [
          _artistItem('a1', 'The Weeknd'),
          _artistItem('a2', 'OneRepublic'),
        ],
      )));

      final artists = await SpotifyBuddyService.instance
          .getTopArtists('fake-token-abc12345678901234567890');

      expect(artists, hasLength(2));
      expect(artists[0].name, 'The Weeknd');
      expect(artists[1].name, 'OneRepublic');
    });

    test('prefers 320px avatar over higher resolution', () async {
      _installMock(json.encode(_topContentResponse(
        artists: [_artistItem('a1', 'Artist')],
      )));

      final artists = await SpotifyBuddyService.instance
          .getTopArtists('fake-token-abc12345678901234567890');

      expect(artists[0].imageUrl, 'https://example.com/artist-320.jpg');
    });

    test('returns empty list when API returns no artists', () async {
      _installMock('{"data":{"me":{"profile":{"topArtists":{"items":[]}}}}}');

      final artists = await SpotifyBuddyService.instance
          .getTopArtists('fake-token-abc12345678901234567890');

      expect(artists, isEmpty);
    });

    test('returns empty list on HTTP 401', () async {
      _installMock('', statusCode: 401);

      final artists = await SpotifyBuddyService.instance
          .getTopArtists('fake-token-abc12345678901234567890');

      expect(artists, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Artist model
  // ---------------------------------------------------------------------------

  group('Artist.fromJson / toJson', () {
    test('round-trips monthlyListeners', () {
      final a = Artist(
        id: 'a1', name: 'The Weeknd', imageUrl: 'https://img', uri: 'spotify:artist:a1',
        followers: 123000000, monthlyListeners: 114000000,
      );
      final json = a.toJson();
      final b = Artist.fromJson(json);
      expect(b.monthlyListeners, 114000000);
      expect(b.followers, 123000000);
      expect(b.name, 'The Weeknd');
    });

    test('defaults to -1 when fields absent', () {
      final a = Artist.fromJson({'id': 'x', 'name': 'X', 'uri': 'spotify:artist:x'});
      expect(a.followers, -1);
      expect(a.monthlyListeners, -1);
    });
  });

  // ---------------------------------------------------------------------------
  // Artist details background fetch — pathfinder queryArtistOverview
  // ---------------------------------------------------------------------------

  Map<String, dynamic> artistOverviewResponse(int followers, int monthlyListeners) => {
    'data': {
      'artist': {
        'stats': {
          'followers': followers,
          'monthlyListeners': monthlyListeners,
        }
      }
    }
  };

  group('artist details background fetch', () {
    test('calls pathfinder v1/query queryArtistOverview (not v1/artists)', () async {
      final urls = <String>[];
      HttpInterceptor.testClient = MockClient((req) async {
        urls.add(req.url.toString());
        if (req.url.path.contains('/v2/query')) {
          return http.Response(
            json.encode(_topContentResponse(artists: [_artistItem('a1', 'The Weeknd')])), 200);
        }
        if (req.url.path.contains('/v1/query')) {
          return http.Response(json.encode(artistOverviewResponse(100, 90000000)), 200);
        }
        return http.Response('{}', 404);
      });

      final completer = Completer<List<Artist>>();
      await SpotifyBuddyService.instance.getTopArtistsWithDetails(
        'fake-token-abc12345678901234567890',
        onArtistDetailsUpdate: (updated) {
          if (!completer.isCompleted) completer.complete(updated);
        },
      );
      await completer.future.timeout(const Duration(seconds: 5));

      // Must have called v1/query for artist overview, NOT v1/artists
      expect(urls.any((u) => u.contains('pathfinder/v1/query')), isTrue);
      expect(urls.any((u) => u.contains('api.spotify.com/v1/artists')), isFalse);
    });

    test('populates monthlyListeners from pathfinder response', () async {
      HttpInterceptor.testClient = MockClient((req) async {
        if (req.url.path.contains('/v2/query')) {
          return http.Response(
            json.encode(_topContentResponse(artists: [_artistItem('a1', 'The Weeknd')])), 200);
        }
        return http.Response(json.encode(artistOverviewResponse(123000000, 114000000)), 200);
      });

      final completer = Completer<List<Artist>>();
      await SpotifyBuddyService.instance.getTopArtistsWithDetails(
        'fake-token-abc12345678901234567890',
        onArtistDetailsUpdate: (updated) {
          if (!completer.isCompleted) completer.complete(updated);
        },
      );
      final artists = await completer.future.timeout(const Duration(seconds: 5));

      expect(artists[0].monthlyListeners, 114000000);
      expect(artists[0].followers, 123000000);
    });

    test('includes queryArtistOverview operationName in request URL', () async {
      final urls = <String>[];
      HttpInterceptor.testClient = MockClient((req) async {
        urls.add(req.url.toString());
        if (req.url.path.contains('/v2/query')) {
          return http.Response(
            json.encode(_topContentResponse(artists: [_artistItem('a1', 'Artist')])), 200);
        }
        return http.Response(json.encode(artistOverviewResponse(1000, 2000)), 200);
      });

      final completer = Completer<List<Artist>>();
      await SpotifyBuddyService.instance.getTopArtistsWithDetails(
        'fake-token-abc12345678901234567890',
        onArtistDetailsUpdate: (a) { if (!completer.isCompleted) completer.complete(a); },
      );
      await completer.future.timeout(const Duration(seconds: 5));

      final overviewUrl = urls.firstWhere((u) => u.contains('/v1/query'), orElse: () => '');
      expect(overviewUrl, contains('queryArtistOverview'));
      expect(overviewUrl, contains('spotify%3Aartist%3Aa1'));
    });

    test('leaves monthlyListeners as -1 when pathfinder returns 401', () async {
      HttpInterceptor.testClient = MockClient((req) async {
        if (req.url.path.contains('/v2/query')) {
          return http.Response(
            json.encode(_topContentResponse(artists: [_artistItem('a1', 'Artist')])), 200);
        }
        return http.Response('', 401);
      });

      final completer = Completer<void>();
      final initial = await SpotifyBuddyService.instance.getTopArtistsWithDetails(
        'fake-token-abc12345678901234567890',
        onArtistDetailsUpdate: (_) { if (!completer.isCompleted) completer.complete(); },
      );
      // Background fetch may still run — give it time to finish/fail
      await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {});

      // Initial list has -1 (not yet fetched)
      expect(initial[0].monthlyListeners, -1);
    });
  });
}
