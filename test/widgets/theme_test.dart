import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/utils/theme.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('AppTheme color tokens', () {
    test('background is #121212', () {
      expect(AppTheme.background, const Color(0xFF121212));
    });

    test('primary is #1DB954', () {
      expect(AppTheme.primary, const Color(0xFF1DB954));
    });

    test('primaryActive is #1ED760', () {
      expect(AppTheme.primaryActive, const Color(0xFF1ED760));
    });

    test('textSecondary is #A7A7A7', () {
      expect(AppTheme.textSecondary, const Color(0xFFA7A7A7));
    });

    test('onPrimary is black (Spotify button text)', () {
      expect(AppTheme.onPrimary, const Color(0xFF000000));
    });

    testWidgets('darkTheme scaffold background matches background token',
        (WidgetTester tester) async {
      expect(AppTheme.darkTheme.scaffoldBackgroundColor, AppTheme.background);
    });

    testWidgets('darkTheme primary color matches primary token',
        (WidgetTester tester) async {
      expect(AppTheme.darkTheme.primaryColor, AppTheme.primary);
    });
  });
}
