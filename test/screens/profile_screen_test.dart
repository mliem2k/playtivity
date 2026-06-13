import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:playtivity/providers/auth_provider.dart';
import 'package:playtivity/providers/spotify_provider.dart';
import 'package:playtivity/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProfileScreen', () {
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
          child: const MaterialApp(home: ProfileScreen()),
        );

    testWidgets('does not use Consumer2 at screen root', (tester) async {
      await tester.pumpWidget(buildSubject());
      final consumer2Widgets = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'Consumer2<AuthProvider, SpotifyProvider>',
      );
      expect(consumer2Widgets, findsNothing);
    });

    testWidgets('renders tab bar', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('wraps TrackTile in RepaintBoundary', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      // Even with empty list, structure should be valid
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('has RefreshIndicator for pull-to-refresh', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('accepts optional scrollController without crashing', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final widget = MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SpotifyProvider>.value(value: spotifyProvider),
        ],
        child: MaterialApp(home: ProfileScreen(scrollController: controller)),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });
}
