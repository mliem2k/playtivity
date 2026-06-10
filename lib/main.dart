import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/spotify_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'services/widget_service.dart';
import 'services/background_service.dart';
import 'services/update_service.dart';
import 'utils/theme.dart';
import 'utils/navigator_key.dart';
import 'dart:async';
import 'services/app_logger.dart';
import 'services/spotify_secrets_service.dart';
import 'widgets/app_wrapper.dart';
import 'widgets/update/update_checker_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  await WidgetService.initialize();
  await BackgroundService.initialize();
  await SpotifySecretsService.loadAndApply();

  _checkForUpdatesOnStartup();

  runApp(MyApp(prefs: prefs));
}

Future<void> _checkForUpdatesOnStartup() async {
  try {
    await UpdateService.autoEnableNightlyIfApplicable();
    if (await UpdateService.shouldCheckForUpdates()) {
      final updateResult = await UpdateService.checkForUpdates();
      if (updateResult.hasUpdate) {
        AppLogger.info('Update available: ${updateResult.updateInfo?.version}');
      }
    }
  } catch (e) {
    AppLogger.error('Error checking for updates on startup', e);
  }
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(prefs)),
        ChangeNotifierProvider(create: (_) => SpotifyProvider()),
      ],
      child: MaterialApp(
        title: 'Playtivity',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        navigatorKey: navigatorKey,
        builder: (context, child) => UpdateCheckerWrapper(child: child!),
        home: const AppWrapper(),
        routes: {
          '/login': (context) {
            AppLogger.info('🔗 Navigating to LoginScreen via route');
            return const LoginScreen();
          },
          '/home': (context) {
            AppLogger.info('🔗 Navigating to HomeScreen via route');
            return const HomeScreen();
          },
          '/profile': (context) {
            AppLogger.info('🔗 Navigating to ProfileScreen via route');
            return const ProfileScreen();
          },
          '/settings': (context) {
            AppLogger.info('🔗 Navigating to SettingsScreen via route');
            return const SettingsScreen();
          },
        },
      ),
    );
  }
}
