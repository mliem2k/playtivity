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

    Widget buildSubject() => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SpotifyProvider>.value(value: spotifyProvider),
          ],
          child: const MaterialApp(home: MainNavigationScreen()),
        );

    testWidgets('renders scaffold with bottom nav', (tester) async {
      await tester.pumpWidget(buildSubject());
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });

    testWidgets('uses Selector not Consumer for SpotifyProvider', (tester) async {
      await tester.pumpWidget(buildSubject());
      // Selector<SpotifyProvider, bool> should be present, not Consumer<SpotifyProvider>
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('Selector') &&
              w.runtimeType.toString().contains('SpotifyProvider'),
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
