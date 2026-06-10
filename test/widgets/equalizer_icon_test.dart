import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/utils/theme.dart';
import 'package:playtivity/widgets/equalizer_icon.dart';

void main() {
  group('EqualizerIcon', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: EqualizerIcon())),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EqualizerIcon), findsOneWidget);
    });

    testWidgets('has default green active color', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: EqualizerIcon())),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final widget = tester.widget<EqualizerIcon>(find.byType(EqualizerIcon));
      expect(widget.color, AppTheme.primaryActive);
    });

    testWidgets('accepts custom color', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: EqualizerIcon(color: Colors.red)),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final widget = tester.widget<EqualizerIcon>(find.byType(EqualizerIcon));
      expect(widget.color, Colors.red);
    });

    testWidgets('updates bar color when widget color changes', (tester) async {
      Color barColor = Colors.red;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  EqualizerIcon(color: barColor),
                  ElevatedButton(
                    onPressed: () => setState(() => barColor = Colors.blue),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Change'));
      await tester.pump(const Duration(milliseconds: 300));

      final widget = tester.widget<EqualizerIcon>(find.byType(EqualizerIcon));
      expect(widget.color, Colors.blue);
    });
  });
}
