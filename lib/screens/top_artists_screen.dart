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
import '../widgets/currently_playing_card.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/common/profile_skeleton.dart';
import 'profile_screen.dart' show ProfileTabBar;
import 'settings_screen.dart';

class TopArtistsScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final PageController? outerPageController;
  const TopArtistsScreen({super.key, this.scrollController, this.outerPageController});

  @override
  State<TopArtistsScreen> createState() => _TopArtistsScreenState();
}

class _TopArtistsScreenState extends State<TopArtistsScreen> {
  late final ScrollController _scrollController;
  bool _ownScrollController = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _ownScrollController = widget.scrollController == null;
  }

  @override
  void dispose() {
    if (_ownScrollController) _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    final spotifyProvider = context.read<SpotifyProvider>();
    await spotifyProvider.refreshProfileData(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primary,
        child: Selector2<AuthProvider, SpotifyProvider,
            ({User? user, Track? currentlyPlaying, List<Artist> topArtists, bool isLoading})>(
          selector: (_, auth, sp) => (
            user: auth.currentUser,
            currentlyPlaying: sp.currentlyPlaying,
            topArtists: sp.topArtists,
            isLoading: sp.isLoading,
          ),
          shouldRebuild: (prev, next) =>
              !identical(prev.user, next.user) ||
              prev.currentlyPlaying?.uri != next.currentlyPlaying?.uri ||
              !identical(prev.topArtists, next.topArtists) ||
              prev.isLoading != next.isLoading,
          builder: (ctx, data, _) => CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(data.user, data.currentlyPlaying)),
              _buildContentSliver(data.topArtists, data.isLoading),
            ],
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
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (currentlyPlaying != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CurrentlyPlayingCard(track: currentlyPlaying),
              ),
            const SizedBox(height: 8),
            ProfileTabBar(
              showSongsActive: false,
              onSongsTap: () {
                HapticFeedback.selectionClick();
                widget.outerPageController?.animateToPage(
                  1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSliver(List<Artist> topArtists, bool isLoading) {
    if (isLoading) {
      return const SliverToBoxAdapter(child: ProfileSkeleton(count: 10));
    }
    if (topArtists.isEmpty) {
      return SliverFillRemaining(
        child: StateDisplayWidget.empty(
          title: 'No top artists found',
          icon: Icons.person_outline,
        ),
      );
    }
    return SliverPadding(
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
    );
  }
}
