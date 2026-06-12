import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with DebouncedRefreshMixin {
  Timer? _refreshTimer;

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
      body: HomeScreenDataSelector(
        builder: (context, isAuthenticated, isLoading, activities, error) {
          if (!isAuthenticated) {
            return _buildSingleScreenScroll(_buildUnauthenticated());
          }
          return RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primary,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(isLoading && activities.isNotEmpty),
                ),
                _buildContentSlivers(isLoading, activities, error),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool showProgress) {
    final sp = context.read<SpotifyProvider>();
    final apiCount = sp.buddylistApiCount;
    final parsedCount = sp.buddylistParsedCount;
    final hasMismatch = apiCount > 0 && parsedCount >= 0 && parsedCount < apiCount;
    final countLabel = hasMismatch ? ' ($parsedCount/$apiCount)' : '';

    return Material(
      color: AppTheme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: sp.buddylistDiagnostic));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Debug info copied'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Text(
                      'Friend Activity$countLabel',
                      style: TextStyle(
                        color: hasMismatch ? Colors.orange : AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showProgress)
              const LinearProgressIndicator(
                color: AppTheme.primary,
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSlivers(
    bool isLoading,
    List<Activity> activities,
    String? error,
  ) {
    if (isLoading && activities.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: _SkeletonList(),
      );
    }
    if (error != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildError(error),
      );
    }
    if (activities.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildEmpty(),
      );
    }
    return _buildActivitySlivers(activities);
  }

  // Wraps a widget in a CustomScrollView so it fills the viewport and
  // RefreshIndicator can always trigger, even when the list is shorter than
  // the viewport. BouncingScrollPhysics provides the overscroll behavior
  // needed for pull-to-refresh on Android while keeping the list scrollable.
  Widget _buildSingleScreenScroll(Widget child) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }

  Widget _buildActivitySlivers(List<Activity> activities) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (i.isOdd) {
              return const Divider(height: 1, color: AppTheme.dividerColor);
            }
            final index = i ~/ 2;
            return RepaintBoundary(
              child: ActivityCard(activity: activities[index]),
            );
          },
          childCount: activities.length * 2 - 1,
        ),
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
    final diag = context.read<SpotifyProvider>().buddylistDiagnostic;
    return _DiagnosticEmpty(diagnostic: diag);
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        6,
        (index) => ActivitySkeleton(animation: _animation),
      ),
    );
  }
}

class _DiagnosticEmpty extends StatelessWidget {
  final String diagnostic;
  const _DiagnosticEmpty({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.largePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 48, color: AppTheme.textSubdued),
            const SizedBox(height: 16),
            const Text(
              'No friend activity',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: diagnostic));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Debug info copied'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                diagnostic,
                textAlign: TextAlign.left,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSubdued,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
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
