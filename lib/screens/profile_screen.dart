import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../widgets/artist_tile.dart';
import '../widgets/track_tile.dart';
import '../widgets/currently_playing_card.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/common/profile_skeleton.dart';
import '../services/app_logger.dart';
import 'settings_screen.dart';
import '../widgets/tab_boundary_passthrough_physics.dart';

class ProfileScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final VoidCallback? onSwipeBack;
  const ProfileScreen({super.key, this.scrollController, this.onSwipeBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _hasError = false;
  String _errorMessage = '';
  bool _swipeBackTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    if (!authProvider.isInitialized) {
      AppLogger.warning('Authentication not yet initialized, skipping data load');
      return;
    }
    if (!authProvider.isAuthenticated) return;
    if (spotifyProvider.topTracks.isNotEmpty || spotifyProvider.topArtists.isNotEmpty) return;
    try {
      await spotifyProvider.refreshProfileData(showLoading: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _onRefresh() async {
    final spotifyProvider = context.read<SpotifyProvider>();
    try {
      await spotifyProvider.refreshProfileData(showLoading: false);
      if (mounted) setState(() { _hasError = false; _errorMessage = ''; });
    } catch (e) {
      if (mounted) setState(() { _hasError = true; _errorMessage = e.toString(); });
    }
  }

  void _retryLoad() {
    setState(() { _hasError = false; _errorMessage = ''; });
    _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Selector2<AuthProvider, SpotifyProvider,
            ({User? user, Track? currentlyPlaying, List<Track> topTracks, List<Artist> topArtists, bool isLoading})>(
          selector: (_, auth, sp) => (
            user: auth.currentUser,
            currentlyPlaying: sp.currentlyPlaying,
            topTracks: sp.topTracks,
            topArtists: sp.topArtists,
            isLoading: sp.isLoading,
          ),
          shouldRebuild: (prev, next) =>
              !identical(prev.user, next.user) ||
              prev.currentlyPlaying?.uri != next.currentlyPlaying?.uri ||
              !identical(prev.topTracks, next.topTracks) ||
              !identical(prev.topArtists, next.topArtists) ||
              prev.isLoading != next.isLoading,
          builder: (ctx, data, _) => RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppTheme.primary,
            child: NestedScrollView(
              controller: widget.scrollController,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(child: _buildHeader(data.user, data.currentlyPlaying)),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabBarDelegate(
                    TabBar(
                      tabs: [Tab(text: 'Top Songs'), Tab(text: 'Top Artists')],
                      indicatorColor: AppTheme.primary,
                      labelColor: AppTheme.textPrimary,
                      unselectedLabelColor: AppTheme.textSecondary,
                      indicatorSize: TabBarIndicatorSize.label,
                    ),
                  ),
                ),
              ],
              body: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is OverscrollNotification &&
                      notification.overscroll < 0 &&
                      !_swipeBackTriggered) {
                    _swipeBackTriggered = true;
                    widget.onSwipeBack?.call();
                  }
                  if (notification is ScrollEndNotification) {
                    _swipeBackTriggered = false;
                  }
                  return false;
                },
                child: TabBarView(
                  physics: const TabBoundaryPassthroughPhysics(),
                  children: [
                    _buildSongsTab(data.topTracks, data.isLoading),
                    _buildArtistsTab(data.topArtists, data.isLoading),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongsTab(List<Track> topTracks, bool isLoading) {
    if (_hasError) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: StateDisplayWidget.error(
              title: 'Could not load',
              error: _errorMessage,
              buttonText: 'Retry',
              onAction: _retryLoad,
            ),
          ),
        ],
      );
    }
    if (isLoading) {
      return const SingleChildScrollView(child: ProfileSkeleton(count: 10));
    }
    if (topTracks.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: StateDisplayWidget.empty(
              title: 'No top tracks found',
              icon: Icons.music_note_outlined,
            ),
          ),
        ],
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i.isOdd) return const Divider(height: 1, color: AppTheme.dividerColor);
                final idx = i ~/ 2;
                return RepaintBoundary(child: TrackTile(track: topTracks[idx], rank: idx + 1));
              },
              childCount: topTracks.length * 2 - 1,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtistsTab(List<Artist> topArtists, bool isLoading) {
    if (isLoading) {
      return const SingleChildScrollView(child: ProfileSkeleton(count: 10));
    }
    if (topArtists.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: StateDisplayWidget.empty(
              title: 'No top artists found',
              icon: Icons.person_outline,
            ),
          ),
        ],
      );
    }
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i.isOdd) return const Divider(height: 1, color: AppTheme.dividerColor);
                final idx = i ~/ 2;
                return RepaintBoundary(child: ArtistTile(artist: topArtists[idx], rank: idx + 1));
              },
              childCount: topArtists.length * 2 - 1,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(User? user, Track? currentlyPlaying) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.primary, AppTheme.background],
          stops: [0.0, 0.7],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.settings, color: AppTheme.textPrimary),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
            GestureDetector(
              onTap: () async {
                if (user != null) {
                  await SpotifyLauncher.launchSpotifyUri('spotify:user:${user.id}');
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.textPrimary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: AppTheme.surfaceElevated,
                  backgroundImage: user?.imageUrl != null
                      ? CachedNetworkImageProvider(
                          user!.imageUrl!,
                          maxWidth: 264,
                          maxHeight: 264,
                        )
                      : null,
                  child: user?.imageUrl == null
                      ? Text(
                          user?.displayName.isNotEmpty == true
                              ? user!.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user?.displayName ?? 'Unknown User',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${user?.followers ?? 0} followers',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (currentlyPlaying != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CurrentlyPlayingCard(track: currentlyPlaying),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: AppTheme.background, child: tabBar);
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}
