import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/widgets/activity_skeleton.dart';

void main() {
  group('ActivitySkeleton', () {
    testWidgets('renders with an external animation', (tester) async {
      const anim = AlwaysStoppedAnimation(0.6);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ActivitySkeleton(animation: anim)),
      ));
      expect(find.byType(ActivitySkeleton), findsOneWidget);
    });

    testWidgets('uses FadeTransition not Opacity widget', (tester) async {
      const anim = AlwaysStoppedAnimation(0.6);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ActivitySkeleton(animation: anim)),
      ));
      final skeletonFinder = find.byType(ActivitySkeleton);
      expect(
        find.descendant(of: skeletonFinder, matching: find.byType(FadeTransition)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: skeletonFinder, matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('is a StatelessWidget', (tester) async {
      const anim = AlwaysStoppedAnimation(0.6);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ActivitySkeleton(animation: anim)),
      ));
      final widget = tester.widget(find.byType(ActivitySkeleton));
      expect(widget, isA<StatelessWidget>());
    });
  });
}
