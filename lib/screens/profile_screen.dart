import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../widgets/track_tile.dart';
import '../widgets/artist_tile.dart';
import '../widgets/currently_playing_card.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/common/profile_skeleton.dart';
import '../services/app_logger.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const ProfileScreen({super.key, this.scrollController});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late final ScrollController _scrollController;
  bool _ownScrollController = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownScrollController = true;
    }
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    if (_ownScrollController) _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primary,
        notificationPredicate: (notification) => notification.depth == 0,
        child: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (sliverContext, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Selector2<AuthProvider, SpotifyProvider,
                  ({User? user, Track? currentlyPlaying})>(
                selector: (_, auth, sp) => (
                  user: auth.currentUser,
                  currentlyPlaying: sp.currentlyPlaying,
                ),
                shouldRebuild: (prev, next) =>
                    !identical(prev.user, next.user) ||
                    prev.currentlyPlaying?.uri != next.currentlyPlaying?.uri,
                builder: (ctx, data, _) =>
                    _buildHeader(data.user, data.currentlyPlaying),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(controller: _tabController, tabs: const [
                  Tab(text: 'Top Songs'),
                  Tab(text: 'Top Artists'),
                ]),
              ),
            ),
          ],
          body: Selector<SpotifyProvider,
              ({List<Track> topTracks, List<Artist> topArtists, bool isLoading})>(
            selector: (_, sp) => (
              topTracks: sp.topTracks,
              topArtists: sp.topArtists,
              isLoading: sp.isLoading,
            ),
            shouldRebuild: (prev, next) =>
                !identical(prev.topTracks, next.topTracks) ||
                !identical(prev.topArtists, next.topArtists) ||
                prev.isLoading != next.isLoading,
            builder: (ctx, data, _) => TabBarView(
              controller: _tabController,
              children: [
                _buildTopSongs(ctx, data.topTracks, data.isLoading),
                _buildTopArtists(ctx, data.topArtists, data.isLoading),
              ],
            ),
          ),
        ),
      ),
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
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            if (currentlyPlaying != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CurrentlyPlayingCard(track: currentlyPlaying),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSongs(BuildContext context, List<Track> topTracks, bool isLoading) {
    if (_hasError) {
      return StateDisplayWidget.error(
        title: 'Could not load',
        error: _errorMessage,
        buttonText: 'Retry',
        onAction: _retryLoad,
      );
    }
    if (isLoading) {
      return ProfileSkeleton(count: 10);
    }
    if (topTracks.isEmpty) {
      return StateDisplayWidget.empty(
        title: 'No top tracks found',
        icon: Icons.music_note_outlined,
      );
    }
    return ListView.separated(
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: topTracks.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.dividerColor),
      itemBuilder: (_, i) => RepaintBoundary(
        child: TrackTile(track: topTracks[i], rank: i + 1),
      ),
    );
  }

  Widget _buildTopArtists(BuildContext context, List<Artist> topArtists, bool isLoading) {
    if (_hasError) {
      return StateDisplayWidget.error(
        title: 'Could not load',
        error: _errorMessage,
        buttonText: 'Retry',
        onAction: _retryLoad,
      );
    }
    if (isLoading) {
      return ProfileSkeleton(count: 10);
    }
    if (topArtists.isEmpty) {
      return StateDisplayWidget.empty(
        title: 'No top artists found',
        icon: Icons.person_outline,
      );
    }
    return ListView.separated(
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: topArtists.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.dividerColor),
      itemBuilder: (_, i) => RepaintBoundary(
        child: ArtistTile(artist: topArtists[i], rank: i + 1),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
