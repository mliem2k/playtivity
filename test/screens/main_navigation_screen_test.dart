import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:playtivity/providers/auth_provider.dart';
import 'package:playtivity/providers/spotify_provider.dart';
import 'package:playtivity/screens/main_navigation_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MainNavigationScreen', () {
    late AuthProvider authProvider;
    late SpotifyProvider spotifyProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      authProvider = AuthProvider(prefs);
      spotifyProvider = SpotifyProvider();
    });

    tearDown(() {
      authProvider.dispose();
      spotifyProvider.dispose();
    });

    Widget buildSubject() => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SpotifyProvider>.value(value: spotifyProvider),
          ],
          child: const MaterialApp(home: MainNavigationScreen()),
        );

    testWidgets('renders scaffold with bottom nav bar', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(Scaffold), findsAtLeastNWidgets(1));
    });

    testWidgets('shows both navigation tabs', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.text('Activities'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('tapping active tab does not crash', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      // Tap Activities tab (already active at index 0)
      await tester.tap(find.text('Activities'));
      await tester.pump();
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });
  });
}
