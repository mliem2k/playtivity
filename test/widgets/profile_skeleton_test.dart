import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/widgets/common/profile_skeleton.dart';

void main() {
  group('ProfileSkeleton', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProfileSkeleton(count: 3)),
      ));
      expect(find.byType(ProfileSkeleton), findsOneWidget);
    });

    testWidgets('is a StatefulWidget', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProfileSkeleton(count: 3)),
      ));
      final widget = tester.widget(find.byType(ProfileSkeleton));
      expect(widget, isA<StatefulWidget>());
    });

    testWidgets('uses FadeTransition for shimmer animation', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ProfileSkeleton(count: 2)),
      ));
      expect(find.byType(FadeTransition), findsWidgets);
    });
  });
}
