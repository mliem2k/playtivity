import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/background_service.dart';
import '../services/app_logger.dart';
import '../utils/auth_utils.dart';
import 'activities_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;
  late final ScrollController _activitiesScrollController;
  late final ScrollController _profileScrollController;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _activitiesScrollController = ScrollController();
    _profileScrollController = ScrollController();
    _screens = [
      _KeepAlive(child: ActivitiesScreen(scrollController: _activitiesScrollController)),
      _KeepAlive(child: ProfileScreen(
        scrollController: _profileScrollController,
        outerPageController: _pageController,
      )),
    ];
    AppLogger.info('🏠 MainNavigationScreen initialized');
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerBackgroundUpdates();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _activitiesScrollController.dispose();
    _profileScrollController.dispose();
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
        final spotifyProvider = Provider.of<SpotifyProvider>(context, listen: false);
        if (authProvider.authState == AuthState.authenticated) {
          await authProvider.refreshIfNeeded();
          final bearer = authProvider.bearerToken;
          if (bearer != null) spotifyProvider.setBearer(bearer);
          await spotifyProvider.reloadFriendsFromPersistedCache();
          await spotifyProvider.loadFriendsActivities();
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
    return Selector<SpotifyProvider, bool>(
      selector: (_, sp) => sp.hasAuthError,
      builder: (ctx, hasAuthError, child) {
        if (hasAuthError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final sp = context.read<SpotifyProvider>();
            final errorMessage = sp.authErrorMessage;
            sp.clearAuthError();
            AuthUtils.handleAuthenticationError(
              context,
              errorMessage: errorMessage,
            );
          });
        }
        return _buildScaffold();
      },
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          if (index == _currentIndex) {
            final controller = index == 0
                ? _activitiesScrollController
                : _profileScrollController;
            if (controller.hasClients) {
              controller.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            return;
          }
          setState(() => _currentIndex = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Activities',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
