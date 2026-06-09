import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/background_service.dart';
import '../services/app_logger.dart';
import '../utils/auth_utils.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    AppLogger.info('🏠 MainNavigationScreen initialized');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerBackgroundUpdates();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AppLogger.info('📱 App resumed, refreshing if needed...');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.authState == AuthState.authenticated) {
          await authProvider.refreshIfNeeded();
        }
      });
    }
  }

  Future<void> _registerBackgroundUpdates() async {
    try {
      await BackgroundService.registerWidgetUpdateTask();
      AppLogger.info('✅ Background widget updates registered');
    } catch (e) {
      AppLogger.error('❌ Failed to register background updates', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('🏠 MainNavigationScreen building with tab index: $_currentIndex');
    return Consumer<SpotifyProvider>(
      builder: (context, spotifyProvider, child) {
        if (spotifyProvider.hasAuthError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            spotifyProvider.clearAuthError();
            AuthUtils.handleAuthenticationError(
              context,
              errorMessage: spotifyProvider.authErrorMessage,
            );
          });
        }
        return _buildMainScaffold();
      },
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      extendBody: true,
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Activities',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
