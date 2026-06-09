import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../services/app_logger.dart';
import 'auth_loading_screen.dart';

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final spotifyProvider = context.read<SpotifyProvider>();
        if (authProvider.authState == AuthState.authenticated &&
            authProvider.bearerToken != null) {
          spotifyProvider.setBearer(authProvider.bearerToken!);
        } else if (authProvider.authState == AuthState.unauthenticated) {
          spotifyProvider.clearBearer();
        }

        AppLogger.debug('🔍 AppWrapper rebuild - AuthProvider state:');
        AppLogger.debug('   - authState: ${authProvider.authState}');
        AppLogger.debug('   - isAuthenticated: ${authProvider.isAuthenticated}');
        AppLogger.debug('   - currentUser: ${authProvider.currentUser?.displayName ?? 'null'}');
        AppLogger.debug('   - bearerToken exists: ${authProvider.bearerToken != null}');

        return switch (authProvider.authState) {
          AuthState.uninitialized || AuthState.loading => AuthLoadingScreen(authProvider: authProvider),
          AuthState.authenticated => const MainNavigationScreen(),
          AuthState.unauthenticated => const LoginScreen(),
        };
      },
    );
  }
}
