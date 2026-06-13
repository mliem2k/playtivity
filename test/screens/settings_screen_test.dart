import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:playtivity/providers/auth_provider.dart';
import 'package:playtivity/providers/spotify_provider.dart';
import 'package:playtivity/screens/settings_screen.dart';
import 'package:playtivity/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/test_fixtures.dart';

Future<void> _waitForInit(AuthProvider provider) async {
  for (var i = 0; i < 50; i++) {
    if (provider.isInitialized) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('SettingsScreen', () {
    late AuthProvider authProvider;
    late SpotifyProvider spotifyProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'enable_nightly_builds': false});
      final prefs = await SharedPreferences.getInstance();
      authProvider = AuthProvider(prefs);
      authProvider.userProfileFetchOverride =
          (_) async => User.fromJson(TestFixtures.userJson());
      spotifyProvider = SpotifyProvider();

      await _waitForInit(authProvider);
      await authProvider.loginComplete(
        'Bearer.token.abc1234567890123456789012345678901234567890',
        {'Cookie': 'sp_dc=validSpDc'},
      );
    });

    tearDown(() {
      authProvider.dispose();
      spotifyProvider.dispose();
    });

    Widget buildSubject() => MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SpotifyProvider>.value(
                value: spotifyProvider),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        );

    testWidgets('renders display name in account header', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('renders email in account header', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('renders country tile in ACCOUNT section', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('Country'), findsOneWidget);
      expect(find.text('US'), findsOneWidget);
    });

    testWidgets('renders all three section headers', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('UPDATES'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
    });

    testWidgets('renders Nightly Builds tile with Switch', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Nightly Builds'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('renders Check for Updates tile', (tester) async {
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('renders chevron icons on tappable tiles', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });

    testWidgets('renders Log Out tile', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      expect(find.text('Log Out'), findsOneWidget);
    });

    testWidgets('Log Out tap opens confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildSubject());
      await tester.pump();
      await tester.tap(find.text('Log Out'));
      await tester.pump();
      expect(find.text('Logout'), findsAtLeastNWidgets(1));
    });
  });
}
