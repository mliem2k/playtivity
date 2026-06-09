import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../widgets/track_tile.dart';
import '../widgets/artist_tile.dart';
import '../widgets/currently_playing_card.dart';
import '../services/app_logger.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

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
    if (authProvider.isAuthenticated) {
      final showLoading = spotifyProvider.topTracks.isEmpty &&
          spotifyProvider.topArtists.isEmpty;
      await spotifyProvider.refreshData(showLoading: showLoading);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, SpotifyProvider>(
      builder: (context, authProvider, spotifyProvider, _) {
        final user = authProvider.currentUser;
        return Scaffold(
          extendBodyBehindAppBar: true,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(child: _buildHeader(context, user, spotifyProvider)),
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
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildTopSongs(spotifyProvider),
                _buildTopArtists(spotifyProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, dynamic user, SpotifyProvider sp) {
    return Container(
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
            // Settings button row
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
            // Avatar
            GestureDetector(
              onTap: () async {
                if (user != null) {
                  await SpotifyLauncher.launchSpotifyUri(
                      'spotify:user:${user.id}');
                }
              },
              child: Container(
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
                      ? CachedNetworkImageProvider(user!.imageUrl!)
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
            if (sp.currentlyPlaying != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CurrentlyPlayingCard(track: sp.currentlyPlaying!),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSongs(SpotifyProvider sp) {
    if (sp.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (sp.topTracks.isEmpty) {
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
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: sp.topTracks.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppTheme.dividerColor),
      itemBuilder: (_, i) => TrackTile(track: sp.topTracks[i], rank: i + 1),
    );
  }

  Widget _buildTopArtists(SpotifyProvider sp) {
    if (sp.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (sp.topArtists.isEmpty) {
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
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: sp.topArtists.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppTheme.dividerColor),
      itemBuilder: (_, i) =>
          ArtistTile(artist: sp.topArtists[i], rank: i + 1),
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
