import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/activity.dart';
import '../widgets/activity_card.dart';
import '../widgets/activity_skeleton.dart';
import '../widgets/performance_selectors.dart';
import '../services/debounced_refresh_service.dart';
import '../utils/auth_utils.dart';
import '../utils/theme.dart';
import '../services/app_logger.dart';
import '../constants/app_constants.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSwipeToProfile;
  const HomeScreen({super.key, this.onSwipeToProfile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with DebouncedRefreshMixin {
  Timer? _refreshTimer;
  Offset _dragStart = Offset.zero;
  bool _didSwipeToProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    DebouncedRefreshService.cancel(DebounceKeys.homeRefresh);
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        DebouncedRefreshService.throttle(
          DebounceKeys.homeRefresh,
          const Duration(seconds: 5),
          _refreshData,
        );
      }
    });
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    if (!authProvider.isInitialized) {
      AppLogger.warning('Authentication not yet initialized, skipping data load');
      return;
    }
    if (authProvider.isAuthenticated) {
      await spotifyProvider.fastInitialLoad();
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning('No authentication available - cannot load friend activities');
    }
  }

  Future<void> _refreshData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    if (!authProvider.isInitialized) {
      AppLogger.warning('Authentication not yet initialized, skipping data refresh');
      return;
    }
    if (authProvider.isAuthenticated) {
      await spotifyProvider.silentRefresh();
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning('No authentication available - cannot refresh friend activities');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _dragStart = e.position;
          _didSwipeToProfile = false;
        },
        onPointerMove: (e) {
          if (_didSwipeToProfile || widget.onSwipeToProfile == null) return;
          final dx = e.position.dx - _dragStart.dx;
          final dy = (e.position.dy - _dragStart.dy).abs();
          if (dx < -80 && -dx > dy * 1.5) {
            _didSwipeToProfile = true;
            widget.onSwipeToProfile!();
          }
        },
        child: HomeScreenDataSelector(
          builder: (context, isAuthenticated, isLoading, activities, error) {
            if (!isAuthenticated) return _buildUnauthenticated();
            return RefreshIndicator(
              onRefresh: _refreshData,
              color: AppTheme.primary,
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(isLoading && activities.isNotEmpty),
                  if (isLoading && activities.isEmpty)
                    _buildSkeletonSliver()
                  else if (error != null)
                    SliverFillRemaining(child: _buildError(error))
                  else if (activities.isEmpty)
                    SliverFillRemaining(child: _buildEmpty())
                  else
                    _buildActivityList(activities),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(bool showProgress) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      toolbarHeight: 52,
      expandedHeight: 52,
      backgroundColor: AppTheme.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: const Text(
        'Friend Activity',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      titleSpacing: 16,
      bottom: showProgress
          ? const PreferredSize(
              preferredSize: Size.fromHeight(2),
              child: LinearProgressIndicator(
                color: AppTheme.primary,
                backgroundColor: Colors.transparent,
              ),
            )
          : null,
    );
  }

  Widget _buildSkeletonSliver() => const _SkeletonList();

  Widget _buildActivityList(List<Activity> activities) {
    // Layout: even indices = cards, odd indices = dividers, last index = nav-bar spacer.
    // childCount = n (cards) + (n-1) (dividers) + 1 (spacer) = 2n
    final childCount = activities.length * 2;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == childCount - 1) {
            return SizedBox(height: MediaQuery.of(context).padding.bottom);
          }
          if (index.isEven) {
            return RepaintBoundary(child: ActivityCard(activity: activities[index ~/ 2]));
          }
          return const Divider(height: 1, color: AppTheme.dividerColor);
        },
        childCount: childCount,
      ),
    );
  }

  Widget _buildUnauthenticated() {
    return const _CenteredState(
      icon: Icons.lock_outline,
      title: 'Authentication Required',
      subtitle: 'Please log in to view friends\' activities',
    );
  }

  Widget _buildEmpty() {
    return const _CenteredState(
      icon: Icons.people_outline,
      title: 'No friend activity',
      subtitle: 'Your friends haven\'t listened recently',
    );
  }

  Widget _buildError(String error) {
    final isAuthError = error.contains('Authentication expired');
    return _CenteredState(
      icon: isAuthError ? Icons.lock_outline : Icons.wifi_off,
      title: isAuthError ? 'Authentication Required' : 'Could not load',
      subtitle: error,
      action: isAuthError
          ? TextButton(
              onPressed: () async {
                final ok = await AuthUtils.handleReAuthentication(context);
                if (ok && mounted) {
                  debouncedRefresh(
                      DebounceKeys.homeRefresh,
                      const Duration(milliseconds: 500),
                      _loadData);
                }
              },
              child: const Text('Login Again',
                  style: TextStyle(color: AppTheme.primary)),
            )
          : TextButton(
              onPressed: () {
                context.read<SpotifyProvider>().clearError();
                debouncedRefresh(DebounceKeys.homeRefresh,
                    const Duration(milliseconds: 300), _refreshData);
              },
              child: const Text('Try again',
                  style: TextStyle(color: AppTheme.primary)),
            ),
    );
  }
}

class _SkeletonList extends StatefulWidget {
  const _SkeletonList();

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 6) return SizedBox(height: MediaQuery.of(context).padding.bottom);
          return ActivitySkeleton(animation: _animation);
        },
        childCount: 7,
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _CenteredState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.largePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppTheme.textSubdued),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
