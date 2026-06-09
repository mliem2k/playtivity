import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/track.dart';
import 'package:playtivity/widgets/track_tile.dart';

Track _makeTrack() => Track.fromJson({
      'id': 'track_abc',
      'name': 'Test Song',
      'artists': [
        {'name': 'Artist One', 'uri': 'spotify:artist:111'},
      ],
      'album': {
        'name': 'Test Album',
        'uri': 'spotify:album:xyz',
        'images': <Map<String, dynamic>>[],
      },
      'duration_ms': 210000,
      'preview_url': null,
      'uri': 'spotify:track:abc',
    });

void main() {
  group('TrackTile', () {
    testWidgets('renders track name', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrackTile(track: _makeTrack(), rank: 1)),
      ));
      expect(find.text('Test Song'), findsOneWidget);
    });

    testWidgets('does not use Card widget (flat row)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrackTile(track: _makeTrack(), rank: 1)),
      ));
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows rank number', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrackTile(track: _makeTrack(), rank: 5)),
      ));
      expect(find.text('5'), findsOneWidget);
    });
  });
}
