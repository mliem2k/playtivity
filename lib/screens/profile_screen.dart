import 'package:flutter/material.dart';
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
import '../services/app_logger.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onSwipeBack;
  const ProfileScreen({super.key, this.onSwipeBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Offset _dragStart = Offset.zero;
  bool _didSwipeBack = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
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
    await spotifyProvider.refreshData(showLoading: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _dragStart = e.position;
          _didSwipeBack = false;
        },
        onPointerMove: (e) {
          if (_didSwipeBack || widget.onSwipeBack == null) return;
          if (_tabController.index != 0) return;
          final dx = e.position.dx - _dragStart.dx;
          final dy = (e.position.dy - _dragStart.dy).abs();
          if (dx > 80 && dx > dy * 1.5) {
            _didSwipeBack = true;
            widget.onSwipeBack!();
          }
        },
        child: NestedScrollView(
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
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
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (topTracks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note_outlined, size: 48, color: AppTheme.textSubdued),
            SizedBox(height: 16),
            Text('No top tracks found',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: topTracks.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppTheme.dividerColor),
      itemBuilder: (_, i) => RepaintBoundary(
        child: TrackTile(track: topTracks[i], rank: i + 1),
      ),
    );
  }

  Widget _buildTopArtists(BuildContext context, List<Artist> topArtists, bool isLoading) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (topArtists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 48, color: AppTheme.textSubdued),
            SizedBox(height: 16),
            Text('No top artists found',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      itemCount: topArtists.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      separatorBuilder: (_, _) =>
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
