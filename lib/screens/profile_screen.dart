import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../widgets/track_tile.dart';
import '../widgets/currently_playing_card.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/common/profile_skeleton.dart';
import '../services/app_logger.dart';
import 'settings_screen.dart';

class TopSongsScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final PageController? outerPageController;
  const TopSongsScreen({super.key, this.scrollController, this.outerPageController});

  @override
  State<TopSongsScreen> createState() => _TopSongsScreenState();
}

class _TopSongsScreenState extends State<TopSongsScreen> {
  late final ScrollController _scrollController;
  bool _ownScrollController = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _ownScrollController = widget.scrollController == null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    if (_ownScrollController) _scrollController.dispose();
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
        child: Selector2<AuthProvider, SpotifyProvider,
            ({User? user, Track? currentlyPlaying, List<Track> topTracks, bool isLoading})>(
          selector: (_, auth, sp) => (
            user: auth.currentUser,
            currentlyPlaying: sp.currentlyPlaying,
            topTracks: sp.topTracks,
            isLoading: sp.isLoading,
          ),
          shouldRebuild: (prev, next) =>
              !identical(prev.user, next.user) ||
              prev.currentlyPlaying?.uri != next.currentlyPlaying?.uri ||
              !identical(prev.topTracks, next.topTracks) ||
              prev.isLoading != next.isLoading,
          builder: (ctx, data, _) => CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(data.user, data.currentlyPlaying)),
              _buildContentSliver(data.topTracks, data.isLoading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSliver(List<Track> topTracks, bool isLoading) {
    if (_hasError) {
      return SliverFillRemaining(
        child: StateDisplayWidget.error(
          title: 'Could not load',
          error: _errorMessage,
          buttonText: 'Retry',
          onAction: _retryLoad,
        ),
      );
    }
    if (isLoading) {
      return const SliverToBoxAdapter(child: ProfileSkeleton(count: 10));
    }
    if (topTracks.isEmpty) {
      return SliverFillRemaining(
        child: StateDisplayWidget.empty(
          title: 'No top tracks found',
          icon: Icons.music_note_outlined,
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
            return RepaintBoundary(child: TrackTile(track: topTracks[idx], rank: idx + 1));
          },
          childCount: topTracks.length * 2 - 1,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
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
              showSongsActive: true,
              onArtistsTap: () {
                HapticFeedback.selectionClick();
                widget.outerPageController?.animateToPage(
                  2,
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
}

/// Shared tab bar used by both [TopSongsScreen] and [TopArtistsScreen].
/// Both screens use identical headers so during a swipe between them the
/// header appears stationary — only the list content slides.
class ProfileTabBar extends StatelessWidget {
  final bool showSongsActive;
  final VoidCallback? onSongsTap;
  final VoidCallback? onArtistsTap;

  const ProfileTabBar({
    super.key,
    required this.showSongsActive,
    this.onSongsTap,
    this.onArtistsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProfileTab(
            label: 'Top Songs',
            isActive: showSongsActive,
            onTap: onSongsTap,
          ),
        ),
        Expanded(
          child: _ProfileTab(
            label: 'Top Artists',
            isActive: !showSongsActive,
            onTap: onArtistsTap,
          ),
        ),
      ],
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _ProfileTab({
    required this.label,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? AppTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
