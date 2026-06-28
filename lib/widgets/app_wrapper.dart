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
  AuthProvider? _authProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_authProvider != auth) {
      _authProvider?.removeListener(_syncBearer);
      _authProvider = auth;
      _authProvider!.addListener(_syncBearer);
      _syncBearer();
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_syncBearer);
    super.dispose();
  }

  void _syncBearer() {
    if (!mounted) return;
    final auth = _authProvider!;
    final spotify = context.read<SpotifyProvider>();
    if (auth.authState == AuthState.authenticated && auth.bearerToken != null) {
      spotify.setBearer(auth.bearerToken!);
    } else if (auth.authState == AuthState.unauthenticated) {
      spotify.clearBearer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, AuthState>(
      selector: (_, auth) => auth.authState,
      builder: (context, authState, _) {
        AppLogger.debug('AppWrapper: authState=${authState.name}');
        return switch (authState) {
          AuthState.uninitialized || AuthState.loading => AuthLoadingScreen(authProvider: _authProvider!),
          AuthState.authenticated => const MainNavigationScreen(),
          AuthState.unauthenticated => const LoginScreen(),
        };
      },
    );
  }
}
