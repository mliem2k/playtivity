import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/widgets/common/state_display_widget.dart';

void main() {
  group('StateDisplayWidget', () {
    testWidgets('error factory renders title and subtitle', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StateDisplayWidget(
            type: StateType.error,
            icon: Icons.wifi_off,
            title: 'Could not load',
            subtitle: 'Network error',
            buttonText: 'Retry',
          ),
        ),
      ));
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
    });

    testWidgets('uses TextButton not ElevatedButton for action', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StateDisplayWidget(
            type: StateType.error,
            icon: Icons.wifi_off,
            title: 'Error',
            buttonText: 'Retry',
            onAction: () {},
          ),
        ),
      ));
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('loading factory renders without crashing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StateDisplayWidget(type: StateType.loading, title: 'Loading...')),
      ));
      expect(find.byType(StateDisplayWidget), findsOneWidget);
    });

    testWidgets('empty factory shows title and subtitle', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StateDisplayWidget(
            type: StateType.empty,
            icon: Icons.music_note_outlined,
            title: 'No tracks found',
            subtitle: 'Try again later',
          ),
        ),
      ));
      expect(find.text('No tracks found'), findsOneWidget);
      expect(find.text('Try again later'), findsOneWidget);
    });
  });
}
