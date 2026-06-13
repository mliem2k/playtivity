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
  final PageController? outerPageController;
  const ProfileScreen({super.key, this.scrollController, this.outerPageController});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late final ScrollController _songsScrollController;
  final ScrollController _artistsScrollController = ScrollController();
  bool _ownSongsScrollController = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _songsScrollController = widget.scrollController ?? ScrollController();
    _ownSongsScrollController = widget.scrollController == null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_ownSongsScrollController) _songsScrollController.dispose();
    _artistsScrollController.dispose();
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

  void _handleSwipe(DragEndDetails details) {
    final vx = details.velocity.pixelsPerSecond.dx;
    if (vx.abs() < 300) return;
    if (vx < 0) {
      // Left swipe: Songs → Artists
      if (_tabController.index == 0) _tabController.animateTo(1);
    } else {
      // Right swipe
      if (_tabController.index == 1) {
        // Artists → Songs
        _tabController.animateTo(0);
      } else {
        // Songs → Activities
        widget.outerPageController?.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _handleSwipe,
        child: Column(
          children: [
            Selector2<AuthProvider, SpotifyProvider,
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
            Container(
              color: AppTheme.background,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Top Songs'),
                  Tab(text: 'Top Artists'),
                ],
              ),
            ),
            Expanded(
              child: Selector<SpotifyProvider,
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
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildTopSongs(ctx, data.topTracks, data.isLoading),
                    _buildTopArtists(ctx, data.topArtists, data.isLoading),
                  ],
                ),
              ),
            ),
          ],
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
      return const ProfileSkeleton(count: 10);
    }
    if (topTracks.isEmpty) {
      return StateDisplayWidget.empty(
        title: 'No top tracks found',
        icon: Icons.music_note_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        controller: _songsScrollController,
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: topTracks.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppTheme.dividerColor),
        itemBuilder: (_, i) => RepaintBoundary(
          child: TrackTile(track: topTracks[i], rank: i + 1),
        ),
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
      return const ProfileSkeleton(count: 10);
    }
    if (topArtists.isEmpty) {
      return StateDisplayWidget.empty(
        title: 'No top artists found',
        icon: Icons.person_outline,
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        controller: _artistsScrollController,
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: topArtists.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppTheme.dividerColor),
        itemBuilder: (_, i) => RepaintBoundary(
          child: ArtistTile(artist: topArtists[i], rank: i + 1),
        ),
      ),
    );
  }
}
