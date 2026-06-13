import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../models/activity.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../services/app_logger.dart';
import '../services/debounced_refresh_service.dart';
import '../utils/auth_utils.dart';
import '../utils/theme.dart';
import '../widgets/activity_card.dart';
import '../widgets/activity_skeleton.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/performance_selectors.dart';

/// The Activities page shows the authenticated user's Spotify friend activity.
///
/// This screen is intentionally self-contained: it owns its own data loading,
/// pull-to-refresh, automatic background refresh, and all of its empty/error
/// states. The body scrollable uses [ClampingScrollPhysics] so the list never
/// overscrolls past its bounds, while [AlwaysScrollableScrollPhysics] keeps
/// pull-to-refresh usable even when the list is shorter than the screen.
/// A custom [_ClampBottomWhenShortPhysics] prevents the content from scrolling
/// down when it already fits on screen, so a short friend list stays pinned at
/// the top instead of drifting.
/// The "Friend Activity" header lives in [Scaffold.appBar] so it stays fixed
/// and does not move during pull-to-refresh or overscroll.
class ActivitiesScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const ActivitiesScreen({super.key, this.scrollController});

  @override
  State<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends State<ActivitiesScreen>
    with DebouncedRefreshMixin {
  static const _autoRefreshInterval = Duration(seconds: 30);

  Timer? _refreshTimer;
  late final ScrollController _scrollController;
  bool _ownScrollController = false;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownScrollController = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    DebouncedRefreshService.cancel(DebounceKeys.activitiesRefresh);
    if (_ownScrollController) _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (mounted) {
        DebouncedRefreshService.throttle(
          DebounceKeys.activitiesRefresh,
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
      AppLogger.warning(
          'Authentication not yet initialized, skipping data load');
      return;
    }

    if (authProvider.isAuthenticated) {
      await spotifyProvider.fastInitialLoad();
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning(
          'No authentication available - cannot load friend activities');
    }
  }

  Future<void> _refreshData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();

    if (!authProvider.isInitialized) {
      AppLogger.warning(
          'Authentication not yet initialized, skipping data refresh');
      return;
    }

    if (authProvider.isAuthenticated) {
      await spotifyProvider.silentRefresh();
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning(
          'No authentication available - cannot refresh friend activities');
    }
  }

  Future<void> _handleReAuth(BuildContext context) async {
    HapticFeedback.lightImpact();
    final ok = await AuthUtils.handleReAuthentication(context);
    if (ok && mounted) {
      debouncedRefresh(
        DebounceKeys.activitiesRefresh,
        const Duration(milliseconds: 500),
        _loadData,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActivitiesScreenDataSelector(
      builder: (context, isAuthenticated, isLoading, activities, error) {
        if (!isAuthenticated) {
          return Scaffold(
            body: _NoBounceScrollable(
              child: StateDisplayWidget.authRequired(
                title: 'Authentication Required',
                subtitle: 'Please log in to view friends\' activities',
              ),
            ),
          );
        }

        return Scaffold(
          appBar: _HeaderAppBar(showProgress: isLoading && activities.isNotEmpty),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceRaised,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const _ClampBottomWhenShortPhysics(
                parent: ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
              ),
              slivers: [
                _ContentSlivers(
                  isLoading: isLoading,
                  activities: activities,
                  error: error,
                  onRetry: _onRetry,
                  onReAuth: _handleReAuth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onRetry() {
    debouncedRefresh(
      DebounceKeys.activitiesRefresh,
      const Duration(milliseconds: 300),
      _refreshData,
    );
  }
}

/// Scrollable wrapper for single-screen states that prevents any overscroll
/// past the viewport bounds.
class _NoBounceScrollable extends StatelessWidget {
  final Widget child;

  const _NoBounceScrollable({required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }
}

/// Scroll physics that clamps the bottom edge when the content fits on screen.
///
/// This keeps [AlwaysScrollableScrollPhysics] enabled for pull-to-refresh, but
/// prevents the list from scrolling down (showing empty space below the cards)
/// when there are not enough items to fill the viewport.
class _ClampBottomWhenShortPhysics extends ScrollPhysics {
  const _ClampBottomWhenShortPhysics({super.parent});

  @override
  _ClampBottomWhenShortPhysics applyTo(ScrollPhysics? ancestor) {
    return _ClampBottomWhenShortPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // When the content is shorter than the viewport, maxScrollExtent equals
    // minScrollExtent. In that state, reject any scroll that would move the
    // content down (positive pixels). Pull-to-refresh still works because
    // negative overscroll (value < pixels) is allowed through to the parent.
    if (position.maxScrollExtent <= position.minScrollExtent &&
        value > position.pixels) {
      return value - position.pixels;
    }
    return super.applyBoundaryConditions(position, value);
  }
}

class _HeaderAppBar extends AppBar {
  _HeaderAppBar({required bool showProgress})
      : super(
          automaticallyImplyLeading: false,
          backgroundColor: AppTheme.background,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          toolbarHeight: 52,
          titleSpacing: 16,
          centerTitle: false,
          title: const _HeaderTitle(),
          bottom: showProgress
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    color: AppTheme.primary,
                    backgroundColor: Colors.transparent,
                    minHeight: 2,
                  ),
                )
              : null,
        );
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle();

  @override
  Widget build(BuildContext context) {
    final spotifyProvider = context.read<SpotifyProvider>();
    final apiCount = spotifyProvider.buddylistApiCount;
    final parsedCount = spotifyProvider.buddylistParsedCount;
    final hasMismatch = apiCount > 0 && parsedCount >= 0 && parsedCount < apiCount;
    final countLabel = hasMismatch ? ' ($parsedCount/$apiCount)' : '';

    return GestureDetector(
      onLongPress: () => _copyDiagnostic(context, spotifyProvider),
      child: Text(
        'Friend Activity$countLabel',
        style: TextStyle(
          color: hasMismatch ? Colors.orange : AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

void _copyDiagnostic(BuildContext context, SpotifyProvider provider) {
  Clipboard.setData(ClipboardData(text: provider.buddylistDiagnostic));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Debug info copied'),
      duration: Duration(seconds: 2),
    ),
  );
}

class _ContentSlivers extends StatelessWidget {
  final bool isLoading;
  final List<Activity> activities;
  final String? error;
  final VoidCallback onRetry;
  final Future<void> Function(BuildContext) onReAuth;

  const _ContentSlivers({
    required this.isLoading,
    required this.activities,
    required this.error,
    required this.onRetry,
    required this.onReAuth,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && activities.isEmpty) {
      return const _SkeletonSliverList(count: 6);
    }

    if (error != null) {
      final isAuthError = error!.contains('Authentication expired');
      return SliverFillRemaining(
        hasScrollBody: false,
        child: isAuthError
            ? StateDisplayWidget.authRequired(
                title: 'Authentication Required',
                subtitle: error,
                buttonText: 'Login Again',
                onAction: () => onReAuth(context),
                secondaryButtonText: 'Retry',
                onSecondaryAction: () {
                  HapticFeedback.lightImpact();
                  context.read<SpotifyProvider>().clearError();
                  onRetry();
                },
              )
            : StateDisplayWidget.error(
                title: 'Could not load',
                error: error!,
                buttonText: 'Try again',
                onAction: () {
                  HapticFeedback.lightImpact();
                  context.read<SpotifyProvider>().clearError();
                  onRetry();
                },
              ),
      );
    }

    if (activities.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyState(),
      );
    }

    return _ActivityList(activities: activities);
  }
}

class _ActivityList extends StatelessWidget {
  final List<Activity> activities;

  const _ActivityList({required this.activities});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index.isOdd) {
              return const Divider(height: 1, color: AppTheme.dividerColor);
            }
            final activityIndex = index ~/ 2;
            return RepaintBoundary(
              child: ActivityCard(activity: activities[activityIndex]),
            );
          },
          childCount: activities.length * 2 - 1,
        ),
      ),
    );
  }
}

class _SkeletonSliverList extends StatefulWidget {
  final int count;

  const _SkeletonSliverList({required this.count});

  @override
  State<_SkeletonSliverList> createState() => _SkeletonSliverListState();
}

class _SkeletonSliverListState extends State<_SkeletonSliverList>
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
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => ActivitySkeleton(animation: _animation),
          childCount: widget.count,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final diagnostic = context.read<SpotifyProvider>().buddylistDiagnostic;
    return _DiagnosticEmpty(diagnostic: diagnostic);
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
            const Icon(
              Icons.people_outline,
              size: 48,
              color: AppTheme.textSubdued,
            ),
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
