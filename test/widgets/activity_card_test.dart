import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/models/activity.dart';
import 'package:playtivity/widgets/activity_card.dart';

Activity _makeActivity({bool isPlaying = false}) {
  // isCurrentlyPlaying is recomputed from the timestamp in fromJson, so use a
  // recent timestamp for "playing" and an old one for "not playing".
  final timestamp = isPlaying
      ? DateTime.now().subtract(const Duration(seconds: 30)).toIso8601String()
      : '2026-01-01T10:00:00.000Z';
  return Activity.fromJson({
    'user': {
      'id': 'u1',
      'display_name': 'Alice',
      'email': 'alice@example.com',
      'image_url': null,
      'followers': 0,
      'country': 'US',
    },
    'track': {
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
    },
    'playlist': null,
    'timestamp': timestamp,
    'is_currently_playing': isPlaying,
    'type': 'track',
  });
}

void main() {
  group('ActivityCard', () {
    testWidgets('renders user name and track name', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ActivityCard(activity: _makeActivity())),
      ));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Test Song'), findsOneWidget);
    });

    testWidgets('does not use Card widget (flat row)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ActivityCard(activity: _makeActivity())),
      ));
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('shows EqualizerIcon when currently playing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ActivityCard(activity: _makeActivity(isPlaying: true))),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'EqualizerIcon'), findsOneWidget);
    });
  });
}
